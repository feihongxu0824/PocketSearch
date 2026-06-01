import Flutter
import EventKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private let eventStore = EKEventStore()
  private var pendingFileImportResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      registerPersonalSourcesChannel(on: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  func registerPersonalSourcesChannel(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "app.pocketsearch/personal_sources",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "fetchDocuments":
        self.fetchEventKitDocuments(result)
      case "importFiles":
        self.importFiles(result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func fetchEventKitDocuments(_ result: @escaping FlutterResult) {
    let group = DispatchGroup()
    var documents: [[String: Any]] = []

    group.enter()
    requestCalendarAccess { granted in
      if granted {
        documents.append(contentsOf: self.calendarDocuments())
      }
      group.leave()
    }

    group.enter()
    requestReminderAccess { granted in
      if granted {
        self.reminderDocuments { docs in
          documents.append(contentsOf: docs)
          group.leave()
        }
      } else {
        group.leave()
      }
    }

    group.notify(queue: .main) {
      result(documents)
    }
  }

  private func requestCalendarAccess(_ completion: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, *) {
      eventStore.requestFullAccessToEvents { granted, _ in completion(granted) }
    } else {
      eventStore.requestAccess(to: .event) { granted, _ in completion(granted) }
    }
  }

  private func requestReminderAccess(_ completion: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, *) {
      eventStore.requestFullAccessToReminders { granted, _ in completion(granted) }
    } else {
      eventStore.requestAccess(to: .reminder) { granted, _ in completion(granted) }
    }
  }

  private func calendarDocuments() -> [[String: Any]] {
    let now = Date()
    guard
      let start = Calendar.current.date(byAdding: .year, value: -1, to: now),
      let end = Calendar.current.date(byAdding: .year, value: 2, to: now)
    else {
      return []
    }
    let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
    return eventStore.events(matching: predicate).map { event in
      let attendees = event.attendees?
        .compactMap { $0.name }
        .filter { !$0.isEmpty }
        .joined(separator: ", ") ?? ""
      let body = [
        event.location,
        event.notes,
        attendees.isEmpty ? nil : "Attendees: \(attendees)"
      ]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")

      return [
        "id": "calendar:\(event.eventIdentifier ?? event.calendarItemIdentifier)",
        "sourceType": "calendar",
        "title": event.title ?? "Untitled event",
        "body": body,
        "sourceName": event.calendar.title,
        "startAt": millis(event.startDate),
        "endAt": millis(event.endDate),
        "indexedAt": millis(Date()),
        "metadata": [
          "calendar": event.calendar.title,
          "location": event.location ?? "",
          "allDay": event.isAllDay
        ]
      ]
    }
  }

  private func reminderDocuments(_ completion: @escaping ([[String: Any]]) -> Void) {
    let predicate = eventStore.predicateForReminders(in: nil)
    eventStore.fetchReminders(matching: predicate) { reminders in
      let docs = (reminders ?? []).map { reminder in
        let dueDate = reminder.dueDateComponents?.date
        let body = [
          reminder.notes,
          dueDate.map { "Due: \(Self.shortDateFormatter.string(from: $0))" },
          reminder.isCompleted ? "Completed" : "Open"
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        return [
          "id": "reminder:\(reminder.calendarItemIdentifier)",
          "sourceType": "reminder",
          "title": reminder.title ?? "Untitled reminder",
          "body": body,
          "sourceName": reminder.calendar.title,
          "startAt": dueDate.map { self.millis($0) } ?? 0,
          "indexedAt": self.millis(Date()),
          "metadata": [
            "list": reminder.calendar.title,
            "completed": reminder.isCompleted,
            "priority": reminder.priority
          ]
        ]
      }
      completion(docs)
    }
  }

  private func importFiles(_ result: @escaping FlutterResult) {
    guard pendingFileImportResult == nil else {
      result(FlutterError(
        code: "busy",
        message: "A file import is already in progress.",
        details: nil
      ))
      return
    }

    pendingFileImportResult = result
    let supportedTypes = [
      "public.text",
      "public.utf8-plain-text",
      "public.json",
      "public.comma-separated-values-text"
    ]
    let picker = UIDocumentPickerViewController(
      documentTypes: supportedTypes,
      in: .import
    )
    picker.delegate = self
    picker.allowsMultipleSelection = true
    window?.rootViewController?.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingFileImportResult?([])
    pendingFileImportResult = nil
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    let docs = urls.compactMap { url -> [String: Any]? in
      let didStart = url.startAccessingSecurityScopedResource()
      defer {
        if didStart {
          url.stopAccessingSecurityScopedResource()
        }
      }
      guard
        let data = try? Data(contentsOf: url),
        let body = String(data: data, encoding: .utf8)
          ?? String(data: data, encoding: .utf16),
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return nil
      }

      return [
        "id": "file:\(url.absoluteString)",
        "sourceType": "file",
        "title": url.lastPathComponent,
        "body": body,
        "sourceName": "Files",
        "uri": url.absoluteString,
        "indexedAt": millis(Date()),
        "metadata": [
          "path": url.path,
          "size": data.count
        ]
      ]
    }
    pendingFileImportResult?(docs)
    pendingFileImportResult = nil
  }

  private func millis(_ date: Date) -> Int64 {
    return Int64(date.timeIntervalSince1970 * 1000)
  }

  private static let shortDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()
}

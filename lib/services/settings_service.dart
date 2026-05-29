import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketsearch/services/query_rewriter.dart';

/// Two mutually-exclusive query-rewriting modes.
///
/// The whole rest of the app is unchanged regardless of which mode is
/// active — [QueryRewriter] is the only injection point.
enum LlmMode {
  /// No rewriting. The CLIP encoder sees the user's raw query verbatim.
  /// Fully offline; no outbound traffic.
  off,

  /// Remote OpenAI-compatible chat-completions endpoint. Sends only the
  /// query text — never any photo / embedding / metadata — to the
  /// configured endpoint. The agent expands the query into a structured
  /// JSON (visual + optional date / geo filters).
  remote,
}

/// Persistent user-tunable settings. All fields default to the offline
/// state ([LlmMode.off]).
class SettingsService extends ChangeNotifier {
  static const _kMode = 'llm.mode';
  // Legacy key from the bool-only era — read once and migrated.
  static const _kLegacyEnabled = 'llm.rewriter.enabled';

  static const _kBaseUrl = 'llm.rewriter.baseUrl';
  static const _kApiKey = 'llm.rewriter.apiKey';
  static const _kModel = 'llm.rewriter.model';

  static const String defaultBaseUrl =
      'https://dashscope.aliyuncs.com/compatible-mode/v1';
  static const String defaultModel = 'qwen-turbo';

  late final SharedPreferences _prefs;
  bool _initialized = false;

  LlmMode _mode = LlmMode.remote;
  String _baseUrl = defaultBaseUrl;
  String _apiKey = '';
  String _model = defaultModel;

  bool get isInitialized => _initialized;

  LlmMode get mode => _mode;
  String get baseUrl => _baseUrl;
  String get apiKey => _apiKey;
  String get model => _model;

  /// True only when the *remote* path has both the toggle on and an
  /// API key. UI uses this to surface "enabled but missing key" warnings.
  bool get remoteReady =>
      _mode == LlmMode.remote && _apiKey.trim().isNotEmpty;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    // Migrate legacy bool flag → mode.remote for users who already
    // configured the remote rewriter on a previous app version.
    // The previous on-device LLM mode is also coerced to off here.
    final modeStr = _prefs.getString(_kMode);
    if (modeStr != null) {
      _mode = LlmMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => LlmMode.off,
      );
    } else {
      final legacy = _prefs.getBool(_kLegacyEnabled) ?? false;
      _mode = legacy ? LlmMode.remote : LlmMode.off;
    }

    _baseUrl = _prefs.getString(_kBaseUrl) ?? defaultBaseUrl;
    _apiKey = _prefs.getString(_kApiKey) ?? '';
    _model = _prefs.getString(_kModel) ?? defaultModel;

    _initialized = true;
    notifyListeners();
  }

  Future<void> setMode(LlmMode v) async {
    if (_mode == v) return;
    _mode = v;
    await _prefs.setString(_kMode, v.name);
    notifyListeners();
  }

  Future<void> setBaseUrl(String v) async {
    final clean = v.trim();
    final next = clean.isEmpty ? defaultBaseUrl : clean;
    if (_baseUrl == next) return;
    _baseUrl = next;
    await _prefs.setString(_kBaseUrl, _baseUrl);
    notifyListeners();
  }

  Future<void> setApiKey(String v) async {
    if (_apiKey == v) return;
    _apiKey = v;
    await _prefs.setString(_kApiKey, v);
    notifyListeners();
  }

  Future<void> setModel(String v) async {
    final clean = v.trim();
    final next = clean.isEmpty ? defaultModel : clean;
    if (_model == next) return;
    _model = next;
    await _prefs.setString(_kModel, _model);
    notifyListeners();
  }

  /// Builds the rewriter the search pipeline should currently use.
  /// Returns [IdentityQueryRewriter] whenever LLM rewriting is OFF or
  /// the active mode is not yet ready, so callers never need to
  /// special-case anything.
  QueryRewriter buildRewriter() {
    switch (_mode) {
      case LlmMode.off:
        return const IdentityQueryRewriter();
      case LlmMode.remote:
        if (!remoteReady) return const IdentityQueryRewriter();
        return OpenAICompatibleQueryRewriter(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          model: _model,
        );
    }
  }
}

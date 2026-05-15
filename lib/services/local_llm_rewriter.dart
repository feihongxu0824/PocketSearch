// On-device LLM query rewriter, backed by `flutter_gemma` (MediaPipe
// LiteRT-LM). Together with [SettingsService.LlmMode.local] this lets
// the entire app — search + rewrite — stay 100% offline once the
// model is downloaded once.
//
// Privacy posture compared to the remote OpenAI-compatible rewriter:
// the local path performs ZERO outbound network traffic at inference
// time. The only network usage is the *one-time* model download
// triggered explicitly from Settings.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'package:zvec_photo_search/services/query_rewriter.dart';

/// Lifecycle states for the on-device LLM model.
enum LocalLlmStatus {
  /// Local LLM not configured yet (no URL / model type chosen).
  idle,

  /// Configured but the model file is not yet on disk.
  notInstalled,

  /// Model file is being downloaded (see [LocalLlmManager.downloadProgress]).
  downloading,

  /// Model file is on disk but not yet loaded into memory.
  installed,

  /// Model is being loaded into memory (one-time per app launch).
  loading,

  /// Model is loaded and ready to serve rewrites.
  ready,

  /// Last operation failed; see [LocalLlmManager.lastError].
  error,
}

/// Catalog of recommended on-device models. Users can override the URL
/// per preset in Settings, e.g. point at a different quantization.
///
/// The URLs below are *defaults* — they assume a public HuggingFace
/// resolve URL. If a particular file is gated, the user must supply a
/// HuggingFace token in Settings.
class LocalLlmPreset {
  final String id;
  final String displayName;
  final ModelType modelType;
  final String defaultUrl;
  final String approxSize;
  final String description;

  const LocalLlmPreset({
    required this.id,
    required this.displayName,
    required this.modelType,
    required this.defaultUrl,
    required this.approxSize,
    required this.description,
  });

  static const gemma3_1b = LocalLlmPreset(
    id: 'gemma3-1b',
    displayName: 'Gemma 3 1B IT (multilingual)',
    modelType: ModelType.gemmaIt,
    defaultUrl:
        'https://hf-mirror.com/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv1280.task',
    approxSize: '~530 MB',
    description:
        'Multilingual (incl. Chinese). ⚠️ Gated model — requires a '
        'HuggingFace token (free account, accept licence on HF page).',
  );

  static const qwen25_15b = LocalLlmPreset(
    id: 'qwen2.5-1.5b',
    displayName: 'Qwen 2.5 1.5B Instruct',
    modelType: ModelType.qwen,
    defaultUrl:
        'https://hf-mirror.com/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    approxSize: '~1.6 GB',
    description:
        'Strong Chinese / English. Larger memory footprint — pick on '
        '6 GB+ RAM devices only.',
  );

  static const smolLm135m = LocalLlmPreset(
    id: 'smollm-135m',
    displayName: 'SmolLM 135M (English only)',
    modelType: ModelType.general,
    defaultUrl:
        'https://hf-mirror.com/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
    approxSize: '~135 MB',
    description:
        'Tiny / extremely fast. English only — best when paired with '
        'photos described in English.',
  );

  static const all = <LocalLlmPreset>[qwen25_15b, gemma3_1b, smolLm135m];

  static LocalLlmPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Singleton owner of the on-device model lifecycle. Kept as a singleton
/// because the underlying [InferenceModel] is heavyweight (hundreds of
/// MB resident memory) and must not be loaded twice.
class LocalLlmManager extends ChangeNotifier {
  LocalLlmManager._();
  static final LocalLlmManager instance = LocalLlmManager._();

  LocalLlmStatus _status = LocalLlmStatus.idle;
  int _downloadProgress = 0;
  String? _lastError;
  InferenceModel? _model;

  /// Cached identity of the currently-loaded model so we know when to
  /// reload (e.g. user picked a different preset).
  String? _loadedPresetId;

  LocalLlmStatus get status => _status;
  int get downloadProgress => _downloadProgress;
  String? get lastError => _lastError;
  String? get loadedPresetId => _loadedPresetId;
  bool get isReady =>
      _status == LocalLlmStatus.ready && _model != null;

  void _setStatus(LocalLlmStatus s, {String? error}) {
    _status = s;
    _lastError = error;
    notifyListeners();
  }

  /// Download (or re-activate if already installed) the given model.
  /// Idempotent: if the model is already on disk `flutter_gemma` will
  /// skip the download and just mark it active.
  Future<void> install({
    required LocalLlmPreset preset,
    required String url,
    String? hfToken,
  }) async {
    _downloadProgress = 0;
    _setStatus(LocalLlmStatus.downloading);
    try {
      await FlutterGemma.installModel(modelType: preset.modelType)
          .fromNetwork(url, token: _emptyToNull(hfToken))
          .withProgress((p) {
            _downloadProgress = p;
            notifyListeners();
          })
          .install();
      _setStatus(LocalLlmStatus.installed);
      // Eagerly load so the first rewrite doesn't pay the load cost.
      await load(preset: preset);
    } catch (e) {
      _setStatus(LocalLlmStatus.error, error: '$e');
    }
  }

  /// Bring the on-disk model into memory. Safe to call repeatedly.
  Future<void> load({required LocalLlmPreset preset, int maxTokens = 1024}) async {
    if (_status == LocalLlmStatus.ready &&
        _model != null &&
        _loadedPresetId == preset.id) {
      return;
    }
    _setStatus(LocalLlmStatus.loading);
    try {
      if (!FlutterGemma.hasActiveModel()) {
        _setStatus(LocalLlmStatus.notInstalled);
        return;
      }
      // Tear down any previous model if the user switched presets.
      if (_model != null && _loadedPresetId != preset.id) {
        try {
          await _model!.close();
        } catch (_) {}
        _model = null;
      }
      _model = await FlutterGemma.getActiveModel(maxTokens: maxTokens);
      _loadedPresetId = preset.id;
      _setStatus(LocalLlmStatus.ready);
    } catch (e) {
      _setStatus(LocalLlmStatus.error, error: '$e');
    }
  }

  /// Delete every installed model and unload from memory. Used when
  /// the user wants to free disk / RAM, or switch to a different
  /// preset cleanly.
  Future<void> uninstallAll() async {
    try {
      await _model?.close();
    } catch (_) {}
    _model = null;
    _loadedPresetId = null;
    try {
      final installed = await FlutterGemma.listInstalledModels();
      for (final id in installed) {
        try {
          await FlutterGemma.uninstallModel(id);
        } catch (_) {}
      }
    } catch (_) {}
    _downloadProgress = 0;
    _setStatus(LocalLlmStatus.idle);
  }

  /// Run one rewrite generation. Returns null on failure so the caller
  /// can fall back to the original query.
  Future<String?> generate(
    String systemInstruction,
    String userQuery, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!isReady || _model == null) return null;
    InferenceModelSession? session;
    try {
      session = await _model!.createSession(
        temperature: 0.0,
        randomSeed: 1,
        topK: 1,
        systemInstruction: systemInstruction,
      );
      await session.addQueryChunk(Message(text: userQuery, isUser: true));
      final out = await session.getResponse().timeout(timeout);
      return out;
    } catch (e) {
      _lastError = '$e';
      notifyListeners();
      return null;
    } finally {
      try {
        await session?.close();
      } catch (_) {}
    }
  }

  static String? _emptyToNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  /// For tests: reset internal state.
  @visibleForTesting
  void resetForTest() {
    _model = null;
    _loadedPresetId = null;
    _downloadProgress = 0;
    _status = LocalLlmStatus.idle;
    _lastError = null;
  }
}

/// [QueryRewriter] adapter on top of [LocalLlmManager]. Constructed by
/// `SettingsService.buildRewriter()` whenever the user has selected
/// `LlmMode.local`. The instance itself is cheap — the heavy state
/// lives in the singleton manager.
class LocalLlmQueryRewriter implements QueryRewriter {
  final LocalLlmManager manager;
  final LocalLlmPreset preset;
  final Duration timeout;

  const LocalLlmQueryRewriter({
    required this.manager,
    required this.preset,
    this.timeout = const Duration(seconds: 60),
  });

  @override
  Future<RewriteResult> rewrite(String userQuery) async {
    // On-device LLM inference is too slow for real-time query rewriting
    // on most mobile devices (30-60s+ for 1.5B models). To preserve UX,
    // local mode passes the query through unchanged — the user gets
    // instant CLIP-based search. Full agent rewriting (with date/geo
    // filters) is available via the remote API mode.
    return RewriteResult.identity(userQuery);
  }
}

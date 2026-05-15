import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zvec_photo_search/services/query_rewriter.dart';

/// Three mutually-exclusive query-rewriting modes.
///
/// The whole rest of the app is unchanged regardless of which mode is
/// active — [QueryRewriter] is the only injection point.
enum LlmMode {
  /// No rewriting. The CLIP encoder sees the user's raw query verbatim.
  /// This is the *default* and the only mode the offline / privacy
  /// guarantees of the app are validated against.
  off,

  /// On-device LLM via flutter_gemma (MediaPipe LiteRT-LM). Requires a
  /// one-time model download (300 MB – 1.6 GB depending on the preset).
  /// After that, search performs zero outbound traffic.
  local,

  /// Remote OpenAI-compatible chat-completions endpoint. Sends only the
  /// query text — never any photo / embedding / metadata — to the
  /// configured endpoint. Useful when an on-device model is too heavy
  /// for the user's phone or they already pay for an API key.
  remote,
}

/// Persistent user-tunable settings. All fields default to the offline
/// state ([LlmMode.off]).
class SettingsService extends ChangeNotifier {
  // Mode + remote-endpoint config -----------------------------------------
  static const _kMode = 'llm.mode';
  // Legacy key from the bool-only era — read once and migrated.
  static const _kLegacyEnabled = 'llm.rewriter.enabled';

  static const _kBaseUrl = 'llm.rewriter.baseUrl';
  static const _kApiKey = 'llm.rewriter.apiKey';
  static const _kModel = 'llm.rewriter.model';

  // Local LLM config ------------------------------------------------------
  static const _kLocalPresetId = 'llm.local.presetId';
  static const _kLocalUrl = 'llm.local.url';
  static const _kHfToken = 'llm.local.hfToken';

  static const String defaultBaseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  static const String defaultModel = 'qwen-turbo';
  static const String defaultLocalPresetId = 'qwen2.5-1.5b';

  late final SharedPreferences _prefs;
  bool _initialized = false;

  LlmMode _mode = LlmMode.remote;
  String _baseUrl = defaultBaseUrl;
  String _apiKey = '';
  String _model = defaultModel;
  String _localPresetId = defaultLocalPresetId;
  String _localUrl = '';
  String _hfToken = '';

  bool get isInitialized => _initialized;

  LlmMode get mode => _mode;
  String get baseUrl => _baseUrl;
  String get apiKey => _apiKey;
  String get model => _model;
  String get localPresetId => _localPresetId;
  String get localUrl =>
      _localUrl.trim().isEmpty ? '' : _localUrl;
  String get hfToken => _hfToken;

  /// True only when the *remote* path has both the toggle on and an
  /// API key. UI uses this to surface "enabled but missing key" warnings.
  bool get remoteReady =>
      _mode == LlmMode.remote && _apiKey.trim().isNotEmpty;

  /// True when the local path is selected (note: actual readiness also
  /// requires the model to be downloaded — that's tracked by
  /// [LocalLlmManager.status], not here).
  bool get localSelected => _mode == LlmMode.local;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    // Migrate legacy bool flag → mode.remote for users who already
    // configured the remote rewriter on a previous app version.
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
    _localPresetId = _prefs.getString(_kLocalPresetId) ?? defaultLocalPresetId;
    _localUrl = _prefs.getString(_kLocalUrl) ?? '';
    _hfToken = _prefs.getString(_kHfToken) ?? '';

    // Migration: clear stale URLs from previous defaults.
    // 1. Gemma3 became gated; 2. All presets moved to hf-mirror.com.
    if (_localUrl.contains('Gemma3-1B-IT') ||
        _localUrl.contains('huggingface.co/litert-community')) {
      _localUrl = '';
      await _prefs.setString(_kLocalUrl, _localUrl);
    }
    if (_localPresetId == 'gemma3-1b') {
      _localPresetId = defaultLocalPresetId;
      await _prefs.setString(_kLocalPresetId, _localPresetId);
    }

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

  Future<void> setLocalPresetId(String v) async {
    if (_localPresetId == v) return;
    _localPresetId = v;
    // Reset the URL override when the preset changes so users get the
    // new preset's default URL.
    _localUrl = '';
    await _prefs.setString(_kLocalPresetId, v);
    await _prefs.setString(_kLocalUrl, '');
    notifyListeners();
  }

  Future<void> setLocalUrl(String v) async {
    final clean = v.trim();
    if (_localUrl == clean) return;
    _localUrl = clean;
    await _prefs.setString(_kLocalUrl, clean);
    notifyListeners();
  }

  Future<void> setHfToken(String v) async {
    if (_hfToken == v) return;
    _hfToken = v;
    await _prefs.setString(_kHfToken, v);
    notifyListeners();
  }

  /// Builds the rewriter the search pipeline should currently use.
  /// Returns [IdentityQueryRewriter] whenever LLM rewriting is OFF or
  /// the active mode is not yet ready, so callers never need to
  /// special-case anything.
  QueryRewriter buildRewriter() {
    switch (_mode) {
      case LlmMode.off:
      case LlmMode.local:
        // Local LLM is no longer actively used (too slow on mobile).
        // Kept in enum for backward-compat with stored prefs.
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

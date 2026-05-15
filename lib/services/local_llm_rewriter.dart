// On-device LLM query rewriter — DEPRECATED.
//
// The local LLM approach (flutter_gemma / MediaPipe LiteRT-LM) was removed
// after real-device testing showed 1.5B-class models require 60s+ per
// inference on mobile hardware, making the UX unacceptable.
//
// This file retains stub classes so that SettingsService and tests that
// reference LocalLlmPreset / LocalLlmManager / LocalLlmQueryRewriter
// continue to compile. No native runtime is loaded.

import 'package:flutter/foundation.dart';

import 'package:zvec_photo_search/services/query_rewriter.dart';

/// Lifecycle states for the on-device LLM model (deprecated).
enum LocalLlmStatus {
  idle,
  notInstalled,
  downloading,
  installed,
  loading,
  ready,
  error,
}

/// Catalog of recommended on-device models (deprecated — kept for reference).
class LocalLlmPreset {
  final String id;
  final String displayName;
  final String defaultUrl;
  final String approxSize;
  final String description;

  const LocalLlmPreset({
    required this.id,
    required this.displayName,
    required this.defaultUrl,
    required this.approxSize,
    required this.description,
  });

  static const qwen25_15b = LocalLlmPreset(
    id: 'qwen2.5-1.5b',
    displayName: 'Qwen 2.5 1.5B Instruct',
    defaultUrl: '',
    approxSize: '~1.6 GB',
    description: 'Deprecated — too slow on mobile.',
  );

  static const all = <LocalLlmPreset>[qwen25_15b];

  static LocalLlmPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Stub singleton — no longer loads any native model.
class LocalLlmManager extends ChangeNotifier {
  LocalLlmManager._();
  static final LocalLlmManager instance = LocalLlmManager._();

  LocalLlmStatus get status => LocalLlmStatus.idle;
  int get downloadProgress => 0;
  String? get lastError => null;
  String? get loadedPresetId => null;
  bool get isReady => false;

  @visibleForTesting
  void resetForTest() {}
}

/// [QueryRewriter] stub that passes through unchanged.
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
    return RewriteResult.identity(userQuery);
  }
}

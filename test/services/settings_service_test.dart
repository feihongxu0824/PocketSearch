import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zvec_photo_search/services/query_rewriter.dart';
import 'package:zvec_photo_search/services/settings_service.dart';

/// Verifies the three-way LlmMode dispatch in `SettingsService.buildRewriter`
/// and the legacy bool → mode.remote migration path.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsService.buildRewriter', () {
    test('defaults to LlmMode.off and returns IdentityQueryRewriter', () async {
      final s = SettingsService();
      await s.load();

      expect(s.mode, LlmMode.off);
      expect(s.buildRewriter(), isA<IdentityQueryRewriter>());
    });

    test('LlmMode.remote without API key falls back to identity', () async {
      SharedPreferences.setMockInitialValues({
        'llm.mode': LlmMode.remote.name,
        'llm.rewriter.apiKey': '',
      });
      final s = SettingsService();
      await s.load();

      expect(s.mode, LlmMode.remote);
      expect(s.remoteReady, isFalse);
      expect(s.buildRewriter(), isA<IdentityQueryRewriter>());
    });

    test('LlmMode.remote with API key builds OpenAICompatibleQueryRewriter',
        () async {
      SharedPreferences.setMockInitialValues({
        'llm.mode': LlmMode.remote.name,
        'llm.rewriter.baseUrl': 'https://api.example.com/v1',
        'llm.rewriter.apiKey': 'sk-test',
        'llm.rewriter.model': 'gpt-4o-mini',
      });
      final s = SettingsService();
      await s.load();

      expect(s.remoteReady, isTrue);
      expect(s.buildRewriter(), isA<OpenAICompatibleQueryRewriter>());
    });

    test('legacy LlmMode.local pref migrates to LlmMode.off (local LLM removed)',
        () async {
      // Older app versions may have persisted the now-removed 'local' enum
      // value. The settings loader must coerce it back to off so the user
      // does not get stuck without a working rewriter.
      SharedPreferences.setMockInitialValues({
        'llm.mode': 'local',
      });
      final s = SettingsService();
      await s.load();

      expect(s.mode, LlmMode.off);
      expect(s.buildRewriter(), isA<IdentityQueryRewriter>());
    });
  });

  group('SettingsService legacy migration', () {
    test('absent mode + legacy bool=true migrates to LlmMode.remote', () async {
      SharedPreferences.setMockInitialValues({
        'llm.rewriter.enabled': true,
      });
      final s = SettingsService();
      await s.load();
      expect(s.mode, LlmMode.remote);
    });

    test('absent mode + legacy bool=false migrates to LlmMode.off', () async {
      SharedPreferences.setMockInitialValues({
        'llm.rewriter.enabled': false,
      });
      final s = SettingsService();
      await s.load();
      expect(s.mode, LlmMode.off);
    });

    test('absent mode + absent legacy defaults to LlmMode.off', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsService();
      await s.load();
      expect(s.mode, LlmMode.off);
    });
  });
}

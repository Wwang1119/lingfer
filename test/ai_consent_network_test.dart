import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The legacy plugin exposes its in-memory test backend in the platform interface.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:lingfer/features/companion/reading_assistant.dart';
import 'package:lingfer/features/companion/reading_preferences.dart';
import 'package:lingfer/models/translation_mode.dart';
import 'package:lingfer/models/vocabulary_level.dart';
import 'package:lingfer/services/ai_consent_store.dart';
import 'package:lingfer/services/ai_translation_service.dart';

class _RecordingPreferences extends InMemorySharedPreferencesStore {
  _RecordingPreferences(super.data) : super.withData();

  final snapshots = <Map<String, Object>>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final saved = await super.setValue(valueType, key, value);
    snapshots.add(await getAll());
    return saved;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Permission defaults off, is versioned, and can be withdrawn without losing local data',
    () async {
      SharedPreferences.setMockInitialValues({
        'companion_saved_v1': '[public fixture]',
        'progress_topChunk_fixture': 7,
        'companion_known_v1': ['maintain'],
      });
      expect((await AiConsentStore.read()).decided, isFalse);
      expect(await AiConsentStore.isAllowed(), isFalse);
      expect((await AiConsentStore.setAllowed(true)).allowed, isTrue);
      expect(await AiConsentStore.isAllowed(), isTrue);
      expect((await AiConsentStore.setAllowed(false)).decided, isTrue);
      expect(await AiConsentStore.isAllowed(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('companion_saved_v1'), '[public fixture]');
      expect(prefs.getInt('progress_topChunk_fixture'), 7);
      expect(prefs.getStringList('companion_known_v1'), ['maintain']);
      await prefs.setBool(AiConsentStore.allowedKey, true);
      await prefs.setInt(
        AiConsentStore.versionKey,
        AiConsentStore.currentVersion - 1,
      );
      expect(await AiConsentStore.isAllowed(), isFalse);
    },
  );

  test(
    'Declining an outdated approval keeps consent off after each write',
    () async {
      const version = 'flutter.${AiConsentStore.versionKey}';
      const allowed = 'flutter.${AiConsentStore.allowedKey}';
      final store = _RecordingPreferences({
        version: AiConsentStore.currentVersion - 1,
        allowed: true,
      });
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferences.setMockInitialValues({}));

      expect(await AiConsentStore.isAllowed(), isFalse);
      final refusal = await AiConsentStore.setAllowed(false);

      expect(refusal.decided, isTrue);
      expect(store.snapshots, hasLength(2));
      for (final snapshot in store.snapshots) {
        expect(
          snapshot[version] == AiConsentStore.currentVersion &&
              snapshot[allowed] == true,
          isFalse,
          reason:
              'A native reader could see this committed snapshot: $snapshot',
        );
      }
      expect(store.snapshots.last[version], AiConsentStore.currentVersion);
      expect(store.snapshots.last[allowed], isFalse);
    },
  );

  test(
    'All AiTranslationService requests stay on device before consent',
    () async {
      var created = 0, requests = 0;
      final service = AiTranslationService(
        proxyUrl: 'https://public-fixture.invalid/proxy',
        appSecret: 'fixture-only',
        clientFactory: () {
          created++;
          return MockClient((_) async {
            requests++;
            return http.Response('{}', 200);
          });
        },
      );
      expect(
        await service.fetchVocabJson(
          raw: 'We maintain a garden.',
          level: VocabularyLevel.cet4,
          mode: TranslationMode.enToZh,
        ),
        isNull,
      );
      expect(
        await service.translatePlainText(
          raw: 'We maintain a garden.',
          mode: TranslationMode.enToZh,
        ),
        isNull,
      );
      expect(
        await service.fetchCoreVocabularyJson(
          raw: 'We maintain a garden.',
          level: VocabularyLevel.cet4,
        ),
        isNull,
      );
      expect(
        await service.cleanupOcrPlainText(raw: 'A public fixture.'),
        'A public fixture.',
      );
      expect(
        await service.translateChunk(
          raw: 'A public fixture.',
          level: VocabularyLevel.cet4,
          mode: TranslationMode.enToZh,
        ),
        'A public fixture.',
      );
      expect(created, 0);
      expect(requests, 0);
    },
  );

  test(
    'All ReadingAssistant requests including health checks are blocked before consent',
    () async {
      var requests = 0;
      final assistant = ReadingAssistant(
        proxyUrl: 'https://public-fixture.invalid/proxy',
        appSecret: 'fixture-only',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(assistant.dispose);
      await expectLater(
        assistant.explain(text: 'Public fixture.', level: '四级'),
        throwsA(isA<AssistantUnavailable>()),
      );
      await expectLater(
        assistant.selectVocabulary(
          segments: const [
            {'id': 's0', 'text': 'Public fixture.'},
          ],
          preferences: const ReadingPreferences(),
          level: '四级',
        ),
        throwsA(isA<AssistantUnavailable>()),
      );
      await expectLater(
        assistant.translateParagraphs(
          paragraphs: const [
            {'id': 'p0', 'text': 'Public fixture.'},
          ],
          source: ReadingLanguage.en,
          target: ReadingLanguage.zh,
        ),
        throwsA(isA<AssistantUnavailable>()),
      );
      expect(await assistant.checkConnection(), contains('未开启'));
      expect(requests, 0);
    },
  );

  test(
    'Explicit consent enables a fixture request and revocation blocks the next one',
    () async {
      var requests = 0;
      final service = AiTranslationService(
        proxyUrl: 'https://public-fixture.invalid/proxy',
        appSecret: 'fixture-only',
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '{"maintain":"保持"}'},
                  },
                ],
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await AiConsentStore.setAllowed(true);
      expect(
        await service.fetchVocabJson(
          raw: 'We maintain a garden.',
          level: VocabularyLevel.cet4,
          mode: TranslationMode.enToZh,
        ),
        '{"maintain":"保持"}',
      );
      expect(requests, 1);
      await AiConsentStore.setAllowed(false);
      expect(
        await service.fetchVocabJson(
          raw: 'We maintain a garden.',
          level: VocabularyLevel.cet4,
          mode: TranslationMode.enToZh,
        ),
        isNull,
      );
      expect(requests, 1);
    },
  );

  test(
    'Revoking consent during an upstream error prevents automatic retries',
    () async {
      var requests = 0;
      final service = AiTranslationService(
        proxyUrl: 'https://public-fixture.invalid/proxy',
        appSecret: 'fixture-only',
        clientFactory: () => MockClient((_) async {
          requests++;
          await AiConsentStore.setAllowed(false);
          return http.Response('Unavailable', 503);
        }),
      );
      await AiConsentStore.setAllowed(true);
      expect(
        await service.fetchVocabJson(
          raw: 'We maintain a garden.',
          level: VocabularyLevel.cet4,
          mode: TranslationMode.enToZh,
        ),
        isNull,
      );
      expect(requests, 1);
    },
  );
}

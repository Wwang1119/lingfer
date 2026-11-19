import 'package:lingfer/services/ai_consent_store.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lingfer/features/companion/annotations/ocr_document.dart';
import 'package:lingfer/features/companion/companion_controller.dart';
import 'package:lingfer/features/companion/live_reading_history.dart';
import 'package:lingfer/features/companion/reading_assistant.dart';
import 'package:lingfer/features/companion/screen_reader_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryBridge extends ScreenReaderBridge {
  HistoryBridge(this.snapshot);
  Map<String, dynamic> snapshot;
  @override
  bool get hasNativeCompanion => true;
  @override
  bool get supportsLiveCapture => false;
  @override
  Future<Map<String, dynamic>> status() async => snapshot;
  @override
  Future<void> stop() async {
    snapshot = {...snapshot, 'running': false};
  }

  @override
  Future<void> configure({
    required String level,
    required List<String> known,
    required String proxyUrl,
    required String appSecret,
    required String saved,
    Map<String, Object?> readingPreferences = const {},
  }) async {}
}

Map<String, Object?> word(String name) => {
  'word': name,
  'surface': name,
  'translation': '测试释义',
  'context': 'An $name method.',
  'tags': ['cet4'],
  'sourceLanguage': 'en',
  'targetLanguage': 'zh',
};

Map<String, Object?> history({bool translation = false}) => {
  'version': 1,
  'sessionId': 'public-session',
  'text': 'An essential method.\n\nA reliable context.',
  'hits': translation ? [] : [word('essential'), word('reliable')],
  'translationSegments': translation
      ? [
          {
            'id': 'page1:p0',
            'source': 'An essential method.',
            'translation': '一种重要的方法。',
          },
          {
            'id': 'page2:p0',
            'source': 'A reliable context.',
            'translation': null,
          },
        ]
      : [],
  'optionsSignature':
      'auto|zh|cet4|intermediate${translation ? '|translation' : ''}',
  'pageCount': 2,
  'retainedPageCount': 2,
  'updatedAt': 20.0,
};

Map<String, dynamic> status({bool running = false, bool translation = false}) =>
    {
      'running': running,
      'sourceLanguage': 'auto',
      'targetLanguage': 'zh',
      'readingMode': translation ? 'translation' : 'learning',
      'level': 'cet4',
      'generalDifficulty': 'intermediate',
      'lastText': 'A reliable context.',
      'lastHits': jsonEncode([word('reliable')]),
      'lastOptionsSignature': 'auto|zh|cet4|intermediate',
      'lastDocumentUpdatedAt': 19.0,
      'liveReadingHistory': history(translation: translation),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      AiConsentStore.versionKey: AiConsentStore.currentVersion,
      AiConsentStore.allowedKey: true,
    }),
  );

  test(
    'Snapshot language metadata survives storage and malformed optional values are ignored',
    () {
      final snapshot = LocalReadingSnapshot.fromJson({
        ...history(),
        'resolvedSource': 'ja',
        'resolvedTarget': 'zh',
      })!;
      final restored = LocalReadingSnapshot.decode(
        jsonEncode(snapshot.toJson()),
      )!;
      expect(restored.resolvedSource, 'ja');
      expect(restored.resolvedTarget, 'zh');
      expect(
        LocalReadingSnapshot.fromJson({...history(), 'resolvedSource': 42}),
        isNull,
      );
    },
  );

  test(
    'Stopped reading restores both pages and words without automatic saving or a request',
    () async {
      var requests = 0;
      final controller = CompanionController(
        bridge: HistoryBridge(status()),
        assistant: ReadingAssistant(
          proxyUrl: 'https://example.test',
          appSecret: 'fixture',
          client: MockClient((_) async {
            requests++;
            throw StateError('Must reuse local result');
          }),
        ),
      );
      await controller.initialize();
      expect(controller.localSessionPageCount, 2);
      expect(controller.lastText, contains('essential'));
      expect(controller.lastText, contains('reliable'));
      expect(controller.lastHits.map((hit) => hit.entry.word), [
        'essential',
        'reliable',
      ]);
      expect(controller.saved, isEmpty);
      controller.analyze(controller.lastText);
      expect(controller.lastHits.length, 2);
      expect(requests, 0);
      final stored = (await SharedPreferences.getInstance()).getString(
        'companion_last_live_reading_v1',
      );
      expect(LocalReadingSnapshot.decode(stored)?.pageCount, 2);
      controller.dispose();
    },
  );

  test(
    'App restart keeps the bounded session in standard local storage while offline',
    () async {
      SharedPreferences.setMockInitialValues({
        AiConsentStore.versionKey: AiConsentStore.currentVersion,
        AiConsentStore.allowedKey: true,
        'companion_last_live_reading_v1': jsonEncode(history()),
      });
      var requests = 0;
      final controller = CompanionController(
        assistant: ReadingAssistant(
          proxyUrl: 'https://example.test',
          appSecret: 'fixture',
          client: MockClient((_) async {
            requests++;
            throw StateError('Offline');
          }),
        ),
      );
      await controller.initialize();
      final text = controller.lastText;
      await controller.analyzeDocument(OcrDocument.fromText(text));
      expect(controller.lastHits.length, 2);
      expect(controller.localSessionPageCount, 2);
      expect(requests, 0);
      controller.dispose();
    },
  );

  test(
    'An active screen keeps its current single word; stop restores the cumulative session',
    () async {
      final bridge = HistoryBridge(status(running: true));
      final controller = CompanionController(bridge: bridge);
      await controller.initialize();
      expect(controller.running, isTrue);
      expect(controller.lastHits.single.entry.word, 'reliable');
      expect(controller.lastText, 'A reliable context.');
      await controller.stop();
      expect(controller.running, isFalse);
      expect(controller.lastHits.length, 2);
      expect(controller.localSessionPageCount, 2);
      controller.dispose();
    },
  );

  test(
    'Newer shared content is not overwritten by an older screen-reading session',
    () async {
      final controller = CompanionController(
        bridge: HistoryBridge({
          ...status(),
          'lastText': 'A different original document.',
          'lastHits': jsonEncode([word('different')]),
          'lastDocumentUpdatedAt': 30.0,
        }),
      );
      await controller.initialize();
      expect(controller.lastText, 'A different original document.');
      expect(controller.lastHits.single.entry.word, 'different');
      expect(controller.localSessionPageCount, 2);
      controller.dispose();
    },
  );

  test(
    'Malformed optional cache and legacy native payload do not block current reading',
    () async {
      SharedPreferences.setMockInitialValues({
        AiConsentStore.versionKey: AiConsentStore.currentVersion,
        AiConsentStore.allowedKey: true,
        'companion_last_live_reading_v1': '{broken',
      });
      final legacy = status()..remove('liveReadingHistory');
      final controller = CompanionController(bridge: HistoryBridge(legacy));
      await controller.initialize();
      expect(controller.localSessionPageCount, 0);
      expect(controller.lastHits.single.entry.word, 'reliable');
      expect(controller.error, isNull);
      controller.dispose();
      expect(LocalReadingSnapshot.decode('{"version":2}'), isNull);
    },
  );

  test(
    'Partial bilingual history opens offline; explicit retry only requests the unfinished pair',
    () async {
      var requests = 0;
      final controller = CompanionController(
        bridge: HistoryBridge(status(translation: true)),
        assistant: ReadingAssistant(
          proxyUrl: 'https://example.test',
          appSecret: 'fixture',
          client: MockClient((request) async {
            requests++;
            final raw = jsonDecode(request.body) as Map;
            final messages = raw['messages'] as List;
            final input =
                jsonDecode((messages.last as Map)['content'] as String) as Map;
            final sent = input['segments'] as List;
            expect(sent.length, 1);
            expect((sent.single as Map)['text'], 'A reliable context.');
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'choices': [
                    {
                      'message': {
                        'content': jsonEncode({
                          'items': [
                            {
                              'segmentId': (sent.single as Map)['id'],
                              'translation': '可靠的语境。',
                            },
                          ],
                        }),
                      },
                    },
                  ],
                }),
              ),
              200,
            );
          }),
        ),
      );
      await controller.initialize();
      final text = controller.lastText;
      controller.analyze(text);
      expect(requests, 0);
      expect(controller.pageTranslations.length, 2);
      expect(controller.pageTranslations.first.translation, '一种重要的方法。');
      expect(controller.error, contains('尚未完成'));
      await controller.analyzeDocument(
        OcrDocument.fromText(text),
        reuseLocalSnapshot: false,
      );
      expect(requests, 1);
      expect(controller.pageTranslations.last.translation, '可靠的语境。');
      expect(controller.error, isNull);
      await controller.refreshScreenStatus();
      expect(controller.pageTranslations.last.translation, '可靠的语境。');
      controller.dispose();
    },
  );
}

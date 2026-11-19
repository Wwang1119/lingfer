import 'package:lingfer/services/ai_consent_store.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lingfer/features/companion/page_translation.dart';
import 'package:lingfer/features/companion/page_translation_view.dart';
import 'package:lingfer/features/companion/reading_assistant.dart';
import 'package:lingfer/features/companion/reading_preferences.dart';
import 'package:lingfer/features/companion/multilingual_reader.dart';
import 'package:lingfer/features/companion/annotations/ocr_document.dart';
import 'package:lingfer/features/companion/companion_controller.dart';
import 'package:lingfer/features/companion/screen_reader_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SnapshotBridge extends ScreenReaderBridge {
  SnapshotBridge(this.snapshot);
  final Map<String, dynamic> snapshot;
  @override
  bool get hasNativeCompanion => true;
  @override
  Future<Map<String, dynamic>> status() async => snapshot;
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

http.Response response(List<Map<String, String>> items) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'choices': [
        {
          'message': {
            'content': jsonEncode({'items': items}),
          },
        },
      ],
    }),
  ),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Consent is limited to public mocked fixtures; no device preference is changed.
  setUp(
    () => SharedPreferences.setMockInitialValues({
      AiConsentStore.versionKey: AiConsentStore.currentVersion,
      AiConsentStore.allowedKey: true,
    }),
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'A response from the previous language cannot be reused as the new translation',
    () async {
      SharedPreferences.setMockInitialValues({
        AiConsentStore.versionKey: AiConsentStore.currentVersion,
        AiConsentStore.allowedKey: true,
      });
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      var calls = 0;
      final assistant = ReadingAssistant(
        proxyUrl: 'https://example.test',
        appSecret: 'test',
        client: MockClient((_) async {
          calls++;
          if (calls == 1) {
            started.complete();
            return pending.future;
          }
          return response([
            {'segmentId': 'p0', 'translation': 'Voici le contexte.'},
          ]);
        }),
      );
      final controller = CompanionController(assistant: assistant);
      await controller.initialize();
      controller.preferences = const ReadingPreferences(
        source: ReadingLanguage.en,
        mode: ReadingMode.translation,
      );
      final original = controller.analyzeDocument(
        OcrDocument.fromText('This is the context.'),
      );
      await started.future;
      final changed = controller.setReadingPreferences(
        controller.preferences.copyWith(target: ReadingLanguage.fr),
      );
      pending.complete(
        response([
          {'segmentId': 'p0', 'translation': '这是语境。'},
        ]),
      );
      await Future.wait([original, changed]);
      expect(calls, 2);
      expect(
        controller.pageTranslations.single.translation,
        'Voici le contexte.',
      );
      controller.dispose();
    },
  );
  test(
    'Opening a restored native page reuses its translations without a new request',
    () async {
      SharedPreferences.setMockInitialValues({
        AiConsentStore.versionKey: AiConsentStore.currentVersion,
        AiConsentStore.allowedKey: true,
      });
      var calls = 0;
      const source = 'This is a book with a familiar context.';
      final assistant = ReadingAssistant(
        proxyUrl: 'https://example.test',
        appSecret: 'test',
        client: MockClient((_) async {
          calls++;
          throw StateError('Must use the native result');
        }),
      );
      final controller = CompanionController(
        assistant: assistant,
        bridge: SnapshotBridge({
          'sourceLanguage': 'auto',
          'targetLanguage': 'zh',
          'readingMode': 'translation',
          'lastText': source,
          'translationSegments': [
            {'id': 'p0', 'source': source, 'translation': '这是一本有熟悉语境的书。'},
          ],
        }),
      );
      await controller.initialize();
      await controller.analyzeDocument(OcrDocument.fromText(source));
      expect(controller.pageTranslations.single.translation, contains('熟悉语境'));
      expect(calls, 0);
      expect(controller.lastHits, isEmpty);
      expect(controller.saved, isEmpty);
      controller.dispose();
    },
  );
  test(
    'Old settings stay in learning mode; Chinese translation does not silently switch target',
    () {
      expect(ReadingPreferences.fromJson({}).mode, ReadingMode.learning);
      final prefs = const ReadingPreferences(mode: ReadingMode.translation);
      final decoded = ReadingPreferences.fromJson(prefs.toJson());
      expect(decoded.mode, ReadingMode.translation);
      expect(
        MultilingualReader.resolvePreferences(
          OcrDocument.fromText('这是一本书。'),
          decoded,
        ).target,
        ReadingLanguage.zh,
      );
    },
  );
  test(
    'Whole-page translation includes basic words, caches paragraphs and remaps IDs',
    () async {
      var calls = 0;
      final assistant = ReadingAssistant(
        proxyUrl: 'https://example.test',
        appSecret: 'test',
        client: MockClient((r) async {
          calls++;
          final body = jsonDecode(r.body) as Map;
          final segments =
              (jsonDecode(body['messages'][1]['content']) as Map)['segments']
                  as List;
          expect(body['messages'][0]['content'], contains('不按考试难度筛选'));
          return response(
            segments
                .map(
                  (p) => <String, String>{
                    'segmentId': p['id'],
                    'translation': '译：${p['text']}',
                  },
                )
                .toList(),
          );
        }),
      );
      final translator = PageTranslator(assistant);
      final first = await translator.translate(
        'This is a book.\nWe maintain a habit.',
        ReadingLanguage.en,
        ReadingLanguage.zh,
      );
      expect(first.length, 2);
      expect(first.first.translation, contains('book'));
      await translator.translate(
        'This is a book.\nWe maintain a habit.',
        ReadingLanguage.en,
        ReadingLanguage.zh,
      );
      final moved = await translator.translate(
        'We maintain a habit.\nThis is a book.',
        ReadingLanguage.en,
        ReadingLanguage.zh,
      );
      expect(calls, 1);
      expect(moved.first.id, 'p0');
      expect(moved.first.translation, contains('habit'));
      assistant.dispose();
    },
  );
  test(
    'An omitted paragraph stays pending; retry preserves successful paragraphs',
    () async {
      var calls = 0;
      final received = <List<dynamic>>[];
      final assistant = ReadingAssistant(
        proxyUrl: 'https://example.test',
        appSecret: 'test',
        client: MockClient((r) async {
          calls++;
          final b = jsonDecode(r.body) as Map;
          final segments =
              (jsonDecode(b['messages'][1]['content']) as Map)['segments']
                  as List;
          received.add(segments);
          return response([
            {
              'segmentId': segments.first['id'],
              'translation': calls == 1 ? '第一段译文' : '第二段译文',
            },
            {'segmentId': 'invented', 'translation': '应被忽略'},
          ]);
        }),
      );
      final translator = PageTranslator(assistant);
      List<TranslatedParagraph> shown = [];
      await expectLater(
        translator.translate(
          'Hello.\nGoodbye.',
          ReadingLanguage.en,
          ReadingLanguage.zh,
          onUpdate: (v) => shown = v,
        ),
        throwsA(isA<AssistantUnavailable>()),
      );
      expect(shown[0].translation, '第一段译文');
      expect(shown[1].translation, isNull);
      final retried = await translator.translate(
        'Hello.\nGoodbye.',
        ReadingLanguage.en,
        ReadingLanguage.zh,
      );
      expect(received.last.length, 1);
      expect(received.last.single['text'], 'Goodbye.');
      expect(retried[0].translation, '第一段译文');
      expect(retried[1].translation, '第二段译文');
      assistant.dispose();
    },
  );
  test(
    'Offline, same-language and oversized input never silently produce a partial success',
    () async {
      final assistant = ReadingAssistant(proxyUrl: '', appSecret: '');
      final translator = PageTranslator(assistant);
      await expectLater(
        translator.translate('Hello.', ReadingLanguage.en, ReadingLanguage.zh),
        throwsA(isA<AssistantUnavailable>()),
      );
      await expectLater(
        translator.translate('你好', ReadingLanguage.zh, ReadingLanguage.zh),
        throwsA(isA<AssistantUnavailable>()),
      );
      await expectLater(
        translator.translate(
          'a' * 12001,
          ReadingLanguage.en,
          ReadingLanguage.zh,
        ),
        throwsA(isA<AssistantUnavailable>()),
      );
      final unicode = '读😀' * 1600;
      expect(
        TranslatedParagraph.split(unicode).map((p) => p.source).join(),
        unicode,
      );
      assistant.dispose();
    },
  );
  testWidgets(
    'Narrow large-text error state retains original and translated paragraphs',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: PageTranslationView(
                parts: const [
                  TranslatedParagraph('p0', 'The original sentence.', '已完成的译文'),
                  TranslatedParagraph('p1', 'Still available.'),
                ],
                loading: false,
                error: '网络连接中断，译文已保留。',
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('The original sentence.'), findsOneWidget);
      expect(find.text('已完成的译文'), findsOneWidget);
      expect(find.text('重试未完成段落'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

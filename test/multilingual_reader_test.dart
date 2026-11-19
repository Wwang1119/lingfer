import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingfer/services/ai_consent_store.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lingfer/features/companion/annotations/ocr_document.dart';
import 'package:lingfer/features/companion/multilingual_reader.dart';
import 'package:lingfer/features/companion/reading_assistant.dart';
import 'package:lingfer/features/companion/reading_preferences.dart';
import 'package:lingfer/features/companion/vocabulary_engine.dart';
import 'package:lingfer/models/vocabulary_level.dart';

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
    'A Chinese browser tooltip does not reverse an English article direction',
    () {
      final doc = OcrDocument.fromText(
        '打开多个标签页即可同时访问不同网页\nThe evidence reveals a subtle distinction. Consider the essential argument before reaching a conclusion. A reliable method can improve your understanding and preserve the original context.',
      );
      final resolved = MultilingualReader.resolvePreferences(
        doc,
        const ReadingPreferences(mode: ReadingMode.translation),
      );
      expect(resolved.source, ReadingLanguage.en);
      expect(resolved.target, ReadingLanguage.zh);
    },
  );
  test('Predominantly Chinese prose keeps its Chinese detection', () {
    final doc = OcrDocument.fromText(
      '他打开手机开始阅读这个故事，故事中的人物正在讨论下一步的计划。他们需要认真地考虑现有的证据，再作出合理的判断。App Store',
    );
    expect(
      MultilingualReader.resolvePreferences(
        doc,
        const ReadingPreferences(),
      ).source,
      ReadingLanguage.zh,
    );
  });
  test(
    'Unknown Latin prose with a Chinese toolbar stays auto for language-aware translation',
    () {
      final doc = OcrDocument.fromText(
        '菜单\nUne méthode fiable améliore notre compréhension. Cette recherche révèle une distinction subtile et conserve le contexte original.',
      );
      expect(
        MultilingualReader.resolvePreferences(
          doc,
          const ReadingPreferences(mode: ReadingMode.translation),
        ).source,
        ReadingLanguage.auto,
      );
    },
  );
  final engine = VocabularyEngine.fromJson({
    'entries': {
      'researcher': {
        'translation': '研究人员',
        'tags': ['cet4', 'cet6'],
      },
      'maintain': {
        'translation': '坚持认为',
        'tags': ['cet4'],
      },
      'innovation': {
        'translation': '创新',
        'tags': ['cet6'],
      },
      'book': {
        'translation': '书',
        'tags': ['zk', 'gk', 'cet4'],
      },
    },
  });
  final chinese = OcrDocument.fromMap({
    'imageWidth': 1000,
    'imageHeight': 600,
    'detectedLanguage': 'zh',
    'lines': [
      {
        'id': 's0',
        'text': '研究人员坚持认为，持续练习更有效。',
        'left': 10,
        'top': 50,
        'width': 500,
        'height': 30,
        'words': [
          {
            'text': '研究人员',
            'left': 10,
            'top': 50,
            'width': 80,
            'height': 30,
            'start': 0,
          },
          {
            'text': '坚持认为',
            'left': 90,
            'top': 50,
            'width': 80,
            'height': 30,
            'start': 4,
          },
        ],
      },
    ],
  });

  test(
    'Automatic Chinese reading keeps the chosen English vocabulary scope',
    () {
      final resolved = MultilingualReader.resolvePreferences(
        chinese,
        const ReadingPreferences(),
      );
      expect(resolved.source, ReadingLanguage.zh);
      expect(resolved.target, ReadingLanguage.en);
    },
  );

  test(
    'Chinese to English verifies exam scope, source substring and real OCR bounds',
    () {
      final reader = MultilingualReader(engine, ReadingAssistant());
      final found = reader.decode(
        [
          {
            'segmentId': 's0',
            'source': '研究人员',
            'word': 'researcher',
            'translation': 'researcher',
          },
          {
            'segmentId': 's0',
            'source': '坚持认为',
            'word': 'maintain',
            'translation': '坚持认为',
          },
          {
            'segmentId': 's0',
            'source': '持续练习',
            'word': 'innovation',
            'translation': 'innovation',
          },
          {
            'segmentId': 's0',
            'source': '不存在',
            'word': 'maintain',
            'translation': 'maintain',
          },
          {
            'segmentId': 's999',
            'source': '研究人员',
            'word': 'researcher',
            'translation': 'researcher',
          },
          {
            'segmentId': 's0',
            'source': '研究人员',
            'word': 'book',
            'translation': 'book',
          },
        ],
        chinese,
        const ReadingPreferences(
          source: ReadingLanguage.zh,
          target: ReadingLanguage.en,
        ),
        VocabularyLevel.cet4,
      );
      expect(found.map((h) => h.entry.word), ['researcher', 'maintain']);
      expect(found[1].annotation, 'maintain');
      expect(found.first.sourceStart, 0);
      expect(chinese.anchors(found[1]), [const Rect.fromLTWH(90, 50, 80, 30)]);
      expect(
        VocabularyHit.fromJson(found.first.toJson())!.targetLanguage,
        'en',
      );
    },
  );

  test(
    'Non-English source vocabulary keeps language identity and estimated grading',
    () {
      final document = OcrDocument.fromText(
        'La persévérance améliore la compréhension.',
      );
      final found = MultilingualReader(engine, ReadingAssistant()).decode(
        [
          {
            'segmentId': 's0',
            'source': 'persévérance',
            'word': 'persévérance',
            'translation': '坚持不懈',
          },
        ],
        document,
        const ReadingPreferences(source: ReadingLanguage.fr),
        VocabularyLevel.cet4,
      );
      expect(found.single.entry.tags, {'estimated-intermediate'});
      expect(found.single.studyKey, 'fr:zh:persévérance');
    },
  );

  test(
    'Repeated translation shares an in-flight request and then uses its cache',
    () async {
      var calls = 0;
      final assistant = ReadingAssistant(
        proxyUrl: 'https://example.test',
        appSecret: 'test',
        client: MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body) as Map;
          expect(jsonEncode(body), contains('中文'));
          expect(jsonEncode(body), contains('英语'));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'sourceLanguage': 'zh',
                      'items': [
                        {
                          'segmentId': 's0',
                          'source': '研究人员',
                          'word': 'researcher',
                          'translation': 'researcher',
                        },
                      ],
                    }),
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final reader = MultilingualReader(engine, assistant);
      const preferences = ReadingPreferences(
        source: ReadingLanguage.zh,
        target: ReadingLanguage.en,
      );
      final both = await Future.wait([
        reader.analyze(chinese, preferences, VocabularyLevel.cet4),
        reader.analyze(chinese, preferences, VocabularyLevel.cet4),
      ]);
      expect(calls, 1);
      expect(both.first.single.shortTranslation, 'researcher');
      expect(
        await reader.analyze(
          chinese,
          preferences,
          VocabularyLevel.cet4,
          known: {'researcher'},
        ),
        isEmpty,
      );
      expect(calls, 1);
      assistant.dispose();
    },
  );

  test(
    'English to Chinese remains offline and automatic Chinese uses the correct source',
    () async {
      final assistant = ReadingAssistant(
        client: MockClient((_) async {
          fail('Offline reading must not call a provider');
        }),
      );
      final reader = MultilingualReader(engine, assistant);
      final english = OcrDocument.fromText(
        'The researcher and the team maintain this position.',
      );
      final result = await reader.analyze(
        english,
        const ReadingPreferences(),
        VocabularyLevel.cet4,
      );
      expect(result.map((v) => v.entry.word), ['researcher', 'maintain']);
      expect(
        MultilingualReader.resolvePreferences(
          chinese,
          const ReadingPreferences(target: ReadingLanguage.en),
        ).source,
        ReadingLanguage.zh,
      );
      assistant.dispose();
    },
  );

  test(
    'Labels never cover neighbouring words; a dense page uses the original-word marker',
    () {
      const anchor = Rect.fromLTWH(50, 50, 60, 20);
      final placement = AnnotationPlacer.place(
        anchor: anchor,
        labelSize: const Size(65, 25),
        viewport: const Rect.fromLTWH(0, 0, 250, 200),
        textBoxes: const [
          anchor,
          Rect.fromLTWH(45, 20, 90, 25),
          Rect.fromLTWH(40, 75, 90, 25),
        ],
        occupied: const [],
      );
      expect(placement.label, isNotNull);
      for (final word in const [
        anchor,
        Rect.fromLTWH(45, 20, 90, 25),
        Rect.fromLTWH(40, 75, 90, 25),
      ]) {
        expect(placement.label!.overlaps(word), isFalse);
      }
      final crowded = AnnotationPlacer.place(
        anchor: anchor,
        labelSize: const Size(80, 25),
        viewport: const Rect.fromLTWH(0, 0, 100, 100),
        textBoxes: const [Rect.fromLTWH(0, 0, 100, 100)],
        occupied: const [],
      );
      expect(crowded.label, isNull);
      expect(crowded.anchor, anchor);
    },
  );

  test('Existing saved words and damaged language settings stay readable', () {
    final old = VocabularyHit.fromJson({
      'word': 'maintain',
      'surface': 'maintain',
      'translation': '坚持',
      'context': 'We maintain this.',
    });
    expect(old!.sourceLanguage, 'en');
    expect(old.studyKey, 'maintain');
    final preferences = ReadingPreferences.fromJson({
      'sourceLanguage': 'unknown',
      'targetLanguage': 'auto',
    });
    expect(preferences.source, ReadingLanguage.auto);
    expect(preferences.target, ReadingLanguage.zh);
  });
}

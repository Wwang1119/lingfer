import 'package:flutter_test/flutter_test.dart';
import 'package:lingfer/features/companion/vocabulary_engine.dart';
import 'package:lingfer/models/vocabulary_level.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = VocabularyEngine.fromJson({
    'entries': {
      'maintain': {
        'translation': '维持；保持',
        'tags': ['cet4', 'cet6'],
      },
      'innovative': {
        'translation': '创新的',
        'tags': ['toefl'],
      },
      'study': {
        'translation': '学习',
        'tags': ['zk', 'gk'],
      },
      'the': {
        'translation': '定冠词',
        'tags': ['zk', 'gk'],
      },
    },
  });

  test(
    'Different targets, word forms and known words change the selected vocabulary',
    () {
      const text =
          'The team maintained an innovative system. They maintained it every day.';
      final cet4 = engine.extract(text, VocabularyLevel.cet4);
      expect(cet4.map((hit) => hit.entry.word), ['maintain']);
      expect(cet4.single.surface, 'maintained');
      expect(cet4.single.context, 'The team maintained an innovative system.');
      expect(
        engine
            .extract(text, VocabularyLevel.toefl)
            .map((hit) => hit.entry.word),
        ['innovative'],
      );
      expect(
        engine.extract(text, VocabularyLevel.cet4, known: {'maintain'}),
        isEmpty,
      );
      expect(engine.lookup('studied')?.word, 'study');
      expect(engine.lookup('unrecognizedword'), isNull);
    },
  );

  test(
    'Saved word payloads round-trip without losing their original context',
    () {
      final word = engine
          .extract('We maintain this system.', VocabularyLevel.cet4)
          .single;
      final copy = VocabularyHit.fromJson(word.toJson());
      expect(copy?.context, word.context);
      expect(copy?.entry.translation, word.entry.translation);
      expect(VocabularyHit.fromJson({'word': 12}), isNull);
    },
  );

  test(
    'OCR wrapping keeps a full sentence but excludes headings and paragraph gaps',
    () {
      const wrapped =
          'READING SAMPLE\nResearchers maintain that consistent practice is more\neffective than occasional effort.\n\nAnother paragraph.';
      final hit = engine.extract(wrapped, VocabularyLevel.cet4).single;
      expect(
        hit.context,
        'Researchers maintain that consistent practice is more effective than occasional effort.',
      );
      const separate =
          'Researchers maintain that consistent practice is more\n\neffective than occasional effort.';
      expect(
        engine.extract(separate, VocabularyLevel.cet4).single.context,
        'Researchers maintain that consistent practice is more',
      );
    },
  );

  test(
    'The shipped offline dictionary is available without a server',
    () async {
      final bundled = await VocabularyEngine.load();
      expect(bundled.entries.length, greaterThan(10000));
      expect(bundled.lookup('maintained')?.translation, contains('维持'));
      expect(
        bundled.extract(
          'An innovative method helps us maintain the system.',
          VocabularyLevel.cet4,
        ),
        isNotEmpty,
      );
    },
  );
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:lingfer/models/translation_mode.dart';
import 'package:lingfer/services/ai_translation_service.dart';

void main() {
  const enToZh = TranslationMode.enToZh;
  const zhToEn = TranslationMode.zhToEn;

  test(
    'English-to-Chinese glosses reject English definitions and reverse maps',
    () {
      const original = 'The occasional visitor observes the unfamiliar garden.';
      const vocabulary = {
        'occasional': '偶尔的',
        'visitor': 'a person who visits',
        'observes': 'observes',
        'unfamiliar': 'not familiar',
        '花园': 'garden',
        'absent': '缺席的',
      };
      expect(
        AiTranslationService.applyVocabReplacements(
          original,
          vocabulary,
          mode: enToZh,
        ),
        'The occasional(偶尔的) visitor observes the unfamiliar garden.',
      );
      expect(vocabulary['visitor'], 'a person who visits');
    },
  );

  test(
    'Invalid responses are failures while a real empty object is cacheable',
    () {
      expect(
        AiTranslationService.validateVocabResponse(
          '{"visitor":"a person who visits"}',
          mode: enToZh,
          source: 'A visitor arrives.',
        ),
        isNull,
      );
      expect(
        AiTranslationService.validateVocabResponse(
          '{}',
          mode: enToZh,
          source: 'A visitor arrives.',
        ),
        '{}',
      );
      expect(
        jsonDecode(
          AiTranslationService.validateVocabResponse(
            '{"visitor":"访客","arrives":"comes to a place","absent":"缺席的"}',
            mode: enToZh,
            source: 'A visitor arrives.',
          )!,
        ),
        {'visitor': '访客'},
      );
      expect(
        AiTranslationService.validateVocabResponse(
          '{"visitor":42}',
          mode: enToZh,
          source: 'A visitor arrives.',
        ),
        isNull,
      );
    },
  );

  test(
    'Historical vocabulary must match both the current direction and source',
    () {
      const source = 'The occasional visitor arrives.';
      const good = {'occasional': '偶尔的'};
      const wrongLanguage = {'occasional': 'happening sometimes'};
      expect(
        AiTranslationService.matchesVocabularyMode(
          good,
          mode: enToZh,
          source: source,
        ),
        isTrue,
      );
      expect(
        AiTranslationService.matchesVocabularyMode(
          good,
          mode: zhToEn,
          source: source,
        ),
        isFalse,
      );
      expect(
        AiTranslationService.matchesVocabularyMode(
          wrongLanguage,
          mode: enToZh,
          source: source,
        ),
        isFalse,
      );
      expect(
        AiTranslationService.matchesVocabularyMode(
          good,
          mode: enToZh,
          source: 'A completely different paragraph.',
        ),
        isFalse,
      );
      expect(
        AiTranslationService.matchesVocabularyMode(
          const {},
          mode: enToZh,
          source: source,
        ),
        isTrue,
      );
      expect(wrongLanguage, {'occasional': 'happening sometimes'});
    },
  );

  test(
    'Replacement never revisits words that were inserted inside a gloss',
    () {
      expect(
        AiTranslationService.applyVocabReplacements('Context gives meaning.', {
          'context': '语境 meaning',
          'meaning': '含义',
        }, mode: enToZh),
        'Context(语境 meaning) gives meaning(含义).',
      );
    },
  );

  test('Longest source phrases win without altering original parentheses', () {
    expect(
      AiTranslationService.applyVocabReplacements(
        'Make up your mind about art (the author’s aside), not a heart.',
        {'make': '制作', 'make up': '决定', 'art': '艺术'},
        mode: enToZh,
      ),
      'Make up(决定) your mind about art(艺术) (the author’s aside), not a heart.',
    );
  });

  test(
    'Chinese-to-English remains available with target-language validation',
    () {
      expect(
        AiTranslationService.applyVocabReplacements('软件开发与软件（原著中的注释）。', {
          '软件开发': 'software development',
          '软件': 'software',
          '注释': '注解',
          '错误': 'mistake',
        }, mode: zhToEn),
        '软件开发(software development)与软件(software)（原著中的注释）。',
      );
    },
  );

  test(
    'Parsing can enforce direction without changing the legacy map format',
    () {
      const response = '{" visitor ": " 访客 ", "arrives":"comes here"}';
      expect(AiTranslationService.parseVocabJson(response), {
        'visitor': '访客',
        'arrives': 'comes here',
      });
      expect(
        AiTranslationService.parseVocabJson(
          response,
          mode: enToZh,
          source: 'A visitor arrives.',
        ),
        {'visitor': '访客'},
      );
    },
  );

  test(
    'Annotation offsets exclude original parentheses and follow longest phrases',
    () {
      const source = 'Make up (an original aside) and observe art.';
      final annotations = <({int source, int start, int end})>[];
      final rendered = AiTranslationService.applyVocabReplacements(
        source,
        {'make': '制作', 'make up': '决定', 'observe': '观察', 'art': '艺术'},
        mode: enToZh,
        onAnnotation: (sourceOffset, renderedStart, renderedEnd) {
          annotations.add((
            source: sourceOffset,
            start: renderedStart,
            end: renderedEnd,
          ));
        },
      );
      expect(
        rendered,
        'Make up(决定) (an original aside) and observe(观察) art(艺术).',
      );
      expect(annotations, hasLength(3));
      for (final (index, word) in ['Make up', 'observe', 'art'].indexed) {
        final annotation = annotations[index];
        expect(annotation.source, source.indexOf(word) + word.length);
        expect(
          rendered.substring(annotation.start, annotation.end),
          ['(决定)', '(观察)', '(艺术)'][index],
        );
        expect(annotation.start, annotation.source + index * '(决定)'.length);
      }
    },
  );

  test(
    'Annotation offsets retain UTF-16 positions across emoji and unequal insertions',
    () {
      const source = 'A 😀 café (原文括号) and DNA.';
      final annotations = <({int source, int start, int end})>[];
      final rendered = AiTranslationService.applyVocabReplacements(
        source,
        {'café': '咖啡馆', 'DNA': '脱氧核糖核酸🧬'},
        mode: enToZh,
        onAnnotation: (sourceOffset, renderedStart, renderedEnd) {
          annotations.add((
            source: sourceOffset,
            start: renderedStart,
            end: renderedEnd,
          ));
        },
      );
      expect(rendered, 'A 😀 café(咖啡馆) (原文括号) and DNA(脱氧核糖核酸🧬).');
      expect(annotations, hasLength(2));
      expect(annotations[0].source, source.indexOf('café') + 'café'.length);
      expect(annotations[0].start, annotations[0].source);
      expect(annotations[1].source, source.indexOf('DNA') + 'DNA'.length);
      expect(annotations[1].start, annotations[1].source + '(咖啡馆)'.length);
      expect(
        annotations.map((range) => rendered.substring(range.start, range.end)),
        ['(咖啡馆)', '(脱氧核糖核酸🧬)'],
      );
    },
  );
}

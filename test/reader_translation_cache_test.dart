import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lingfer/models/translation_mode.dart';
import 'package:lingfer/services/reader_translation_cache.dart';

void main() {
  const level = '四级考点';
  const enToZh = TranslationMode.enToZh;
  const zhToEn = TranslationMode.zhToEn;
  const source = 'An occasional visitor enjoys 阅读。';
  late Directory directory;
  late ReaderTranslationCache cache;

  String? read({
    String raw = source,
    TranslationMode mode = enToZh,
    String levelLabel = level,
  }) => cache.read(index: 0, levelLabel: levelLabel, mode: mode, raw: raw);

  Future<bool> write(String vocabJson, {TranslationMode mode = enToZh}) =>
      cache.write(
        index: 0,
        levelLabel: level,
        mode: mode,
        raw: source,
        vocabJson: vocabJson,
      );

  File legacyFile() => File('${directory.path}/chunk_0_$level.json');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lingfer-reader-cache-');
    cache = ReaderTranslationCache(directory: directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'Same chunk and level retain independent caches for both directions',
    () async {
      expect(
        await Future.wait([
          write('{"occasional":"偶尔的"}'),
          write('{"阅读":"reading"}', mode: zhToEn),
        ]),
        [true, true],
      );
      expect((jsonDecode(read()!) as Map)['data'], {'occasional': '偶尔的'});
      expect((jsonDecode(read(mode: zhToEn)!) as Map)['data'], {
        '阅读': 'reading',
      });
      final files = directory.listSync().whereType<File>().toList();
      expect(files, hasLength(2));
      expect(files.any((file) => file.path.contains('_en_zh_v2.json')), isTrue);
      expect(files.any((file) => file.path.contains('_zh_en_v2.json')), isTrue);
      for (final file in files) {
        final wrapper = jsonDecode(await file.readAsString()) as Map;
        expect(wrapper['schemaVersion'], ReaderTranslationCache.schemaVersion);
        expect(wrapper['rawSource'], source);
        expect(wrapper['level'], level);
      }
    },
  );

  test(
    'A changed paragraph cannot reuse a cache even when its word still occurs',
    () async {
      expect(await write('{"occasional":"偶尔的"}'), isTrue);
      expect(read(raw: 'An occasional visitor leaves.'), isNull);
      expect(read(mode: zhToEn), isNull);
      expect(read(levelLabel: '六级考点'), isNull);
      expect(read(), isNotNull);
    },
  );

  test(
    'Compatible legacy cache migrates without deleting or rewriting its file',
    () async {
      final original = jsonEncode({
        'level': level,
        'mode': 'en_zh',
        'data': {'occasional': '偶尔的'},
      });
      await legacyFile().writeAsString(original);
      final restored = jsonDecode(read()!) as Map;
      expect(restored['mode'], ReaderTranslationCache.modeID(enToZh));
      expect(restored['rawSource'], source);
      expect(restored['schemaVersion'], ReaderTranslationCache.schemaVersion);
      expect(await legacyFile().readAsString(), original);
      expect(directory.listSync().whereType<File>(), hasLength(2));
      // The preserved legacy file must not bypass the new exact-source check.
      expect(read(raw: 'An occasional visitor leaves.'), isNull);
      final migrated = directory.listSync().whereType<File>().singleWhere(
        (file) => file.path != legacyFile().path,
      );
      final migratedPayload = await migrated.readAsString();
      expect((jsonDecode(migratedPayload) as Map)['rawSource'], source);
    },
  );

  test(
    'Legacy wrong direction, wrong language, absent source words and unproven empty maps are misses',
    () async {
      final rejected = [
        {
          'level': level,
          'mode': 'zh_en',
          'data': {'阅读': 'reading'},
        },
        {
          'level': level,
          'data': {'occasional': '偶尔的'},
        },
        {
          'level': level,
          'mode': 'en_zh',
          'data': {'visitor': 'someone visiting'},
        },
        {
          'level': level,
          'mode': 'en_zh',
          'data': {'absent': '缺席的'},
        },
        {'level': level, 'mode': 'en_zh', 'data': <String, String>{}},
        {
          'level': level,
          'mode': 'en_zh',
          'data': {'visitor': 3},
        },
        {
          'level': level,
          'mode': 'en_zh',
          'rawSource': 'Other text',
          'data': {'visitor': '访客'},
        },
      ];
      for (final wrapper in rejected) {
        final original = jsonEncode(wrapper);
        await legacyFile().writeAsString(original);
        expect(read(), isNull, reason: original);
        expect(await legacyFile().readAsString(), original);
        expect(directory.listSync().whereType<File>(), hasLength(1));
      }
    },
  );

  test(
    'New wrappers reject damaged metadata and any invalid data entry',
    () async {
      expect(await write('{"occasional":"偶尔的"}'), isTrue);
      final file = directory.listSync().whereType<File>().single;
      final valid =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final rejected = [
        {...valid, 'schemaVersion': 99},
        {...valid}..remove('schemaVersion'),
        {...valid, 'rawSource': 'An occasional visitor leaves.'},
        {...valid}..remove('rawSource'),
        {...valid, 'mode': 'zh_en'},
        {...valid, 'level': '六级考点'},
        {
          ...valid,
          'data': {'occasional': 'sometimes happening'},
        },
        {
          ...valid,
          'data': {'occasional': '偶尔的', 'visitor': 42},
        },
        {
          ...valid,
          'data': {'occasional': '偶尔的', 'visitor': ''},
        },
        {
          ...valid,
          'data': ['偶尔的'],
        },
      ];
      for (final wrapper in rejected) {
        final payload = jsonEncode(wrapper);
        await file.writeAsString(payload);
        expect(read(), isNull, reason: payload);
        expect(await file.readAsString(), payload);
      }
      await file.writeAsString('{broken JSON');
      expect(read(), isNull);
    },
  );

  test('Invalid writes cannot replace an existing valid cache', () async {
    expect(await write('{"occasional":"偶尔的"}'), isTrue);
    final original = read();
    for (final invalid in [
      '{"occasional":"sometimes happening"}',
      '{"occasional":"偶尔的","visitor":42}',
      '{"absent":"缺席的"}',
      '[]',
      '{malformed',
    ]) {
      expect(await write(invalid), isFalse, reason: invalid);
      expect(read(), original);
      expect(directory.listSync().whereType<File>(), hasLength(1));
    }
  });

  test(
    'A genuine empty result is reusable only with an exact source',
    () async {
      expect(await write('{}'), isTrue);
      expect((jsonDecode(read()!) as Map)['data'], isEmpty);
      expect(read(raw: '$source A new line.'), isNull);
      expect(read(mode: zhToEn), isNull);
      expect(
        await cache.write(
          index: -1,
          levelLabel: level,
          mode: enToZh,
          raw: source,
          vocabJson: '{}',
        ),
        isFalse,
      );
      expect(
        cache.read(index: 0, levelLabel: level, mode: enToZh, raw: '  '),
        isNull,
      );
    },
  );
}

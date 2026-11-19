import 'dart:convert';
import 'dart:io';

import '../models/translation_mode.dart';
import 'ai_translation_service.dart';

/// Per-book chunk cache. The caller supplies its existing book/chunks folder;
/// no application paths, reading progress or vocabulary records are managed here.
class ReaderTranslationCache {
  ReaderTranslationCache({required this.directory});

  final Directory directory;
  static const int schemaVersion = 2;
  static int _writeSequence = 0;

  static String modeID(TranslationMode mode) => switch (mode) {
    TranslationMode.enToZh => 'en_zh',
    TranslationMode.zhToEn => 'zh_en',
  };

  String? read({
    required int index,
    required String levelLabel,
    required TranslationMode mode,
    required String raw,
  }) {
    if (index < 0 || levelLabel.trim().isEmpty || raw.trim().isEmpty) {
      return null;
    }
    final file = _file(index, levelLabel, mode);
    try {
      if (file.existsSync()) {
        // Once this direction has a versioned record, its source check is
        // authoritative. Falling back again to an unversioned legacy file
        // would bypass it when a changed paragraph contains the same word.
        return _readValidated(
          file,
          levelLabel: levelLabel,
          mode: mode,
          raw: raw,
          legacy: false,
        );
      }
    } catch (_) {
      return null;
    }

    final legacy = _readValidated(
      _legacyFile(index, levelLabel),
      levelLabel: levelLabel,
      mode: mode,
      raw: raw,
      legacy: true,
    );
    if (legacy == null) return null;
    // Migration is best-effort. A read-only/full cache directory must not make
    // an otherwise valid legacy entry unavailable, and the old file stays intact.
    try {
      _persistSync(file, legacy);
    } catch (_) {}
    return legacy;
  }

  Future<bool> write({
    required int index,
    required String levelLabel,
    required TranslationMode mode,
    required String raw,
    required String vocabJson,
  }) async {
    if (index < 0 || levelLabel.trim().isEmpty || raw.trim().isEmpty) {
      return false;
    }
    File? temporary;
    try {
      final data = _validatedData(
        jsonDecode(vocabJson),
        mode: mode,
        source: raw,
      );
      if (data == null) return false;
      final payload = _wrap(levelLabel, mode, raw, data);
      final file = _file(index, levelLabel, mode);
      await directory.create(recursive: true);
      temporary = _temporaryFor(file);
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename(file.path);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (temporary != null) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {}
      }
    }
  }

  File _file(int index, String levelLabel, TranslationMode mode) => File(
    '${directory.path}${Platform.pathSeparator}'
    'chunk_${index}_${_levelSegment(levelLabel)}_${modeID(mode)}_v$schemaVersion.json',
  );

  File _legacyFile(int index, String levelLabel) => File(
    '${directory.path}${Platform.pathSeparator}'
    'chunk_${index}_${_levelSegment(levelLabel)}.json',
  );

  static String _levelSegment(String label) => label
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  String? _readValidated(
    File file, {
    required String levelLabel,
    required TranslationMode mode,
    required String raw,
    required bool legacy,
  }) {
    try {
      if (!file.existsSync()) return null;
      final wrapper = jsonDecode(file.readAsStringSync());
      if (wrapper is! Map ||
          wrapper['level'] != levelLabel ||
          wrapper['mode'] != modeID(mode)) {
        return null;
      }
      final storedSource = wrapper['rawSource'];
      if (!legacy) {
        if (wrapper['schemaVersion'] != schemaVersion || storedSource != raw) {
          return null;
        }
      } else {
        if (wrapper.containsKey('schemaVersion') &&
            wrapper['schemaVersion'] != schemaVersion) {
          return null;
        }
        if (wrapper.containsKey('rawSource') && storedSource != raw) {
          return null;
        }
      }
      final data = _validatedData(wrapper['data'], mode: mode, source: raw);
      if (data == null) return null;
      // Original wrappers had no source fingerprint. Nonempty entries can be
      // checked against the current prose; an empty map cannot establish that
      // it belongs to this chunk, so let that chunk be translated again.
      if (legacy && storedSource == null && data.isEmpty) return null;
      return _wrap(levelLabel, mode, raw, data);
    } catch (_) {
      return null;
    }
  }

  static Map<String, String>? _validatedData(
    Object? decoded, {
    required TranslationMode mode,
    required String source,
  }) {
    if (decoded is! Map) return null;
    final data = <String, String>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String || entry.value is! String) return null;
      data[entry.key as String] = entry.value as String;
    }
    if (!AiTranslationService.matchesVocabularyMode(
      data,
      mode: mode,
      source: source,
    )) {
      return null;
    }
    return AiTranslationService.filterVocabularyForMode(
      data,
      mode: mode,
      source: source,
    );
  }

  static String _wrap(
    String levelLabel,
    TranslationMode mode,
    String raw,
    Map<String, String> data,
  ) => jsonEncode({
    'schemaVersion': schemaVersion,
    'level': levelLabel,
    'mode': modeID(mode),
    'rawSource': raw,
    'data': data,
  });

  static File _temporaryFor(File file) => File(
    '${file.path}.${DateTime.now().microsecondsSinceEpoch}_${_writeSequence++}.tmp',
  );

  static void _persistSync(File file, String payload) {
    final temporary = _temporaryFor(file);
    try {
      file.parent.createSync(recursive: true);
      temporary.writeAsStringSync(payload, flush: true);
      temporary.renameSync(file.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
}

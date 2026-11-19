import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/vocabulary_level.dart';
import 'reading_assistant.dart';
import 'screen_reader_bridge.dart';
import 'vocabulary_engine.dart';
import 'reading_preferences.dart';
import 'multilingual_reader.dart';
import 'annotations/ocr_document.dart';
import 'review_schedule.dart';
import 'page_translation.dart';
import 'live_reading_history.dart';

class CompanionController extends ChangeNotifier {
  CompanionController({ScreenReaderBridge? bridge, ReadingAssistant? assistant})
    : bridge = bridge ?? ScreenReaderBridge(),
      assistant = assistant ?? ReadingAssistant();

  final ScreenReaderBridge bridge;
  final ReadingAssistant assistant;
  SharedPreferences? _prefs;
  VocabularyEngine? engine;
  Future<void>? _initialization;
  StreamSubscription<Object?>? _events;
  bool _disposed = false;
  VocabularyLevel level = VocabularyLevel.cet4;
  final Set<String> known = {};
  final Map<String, VocabularyHit> saved = {};
  final Map<String, ReviewProgress> reviews = {};
  String connection = '离线阅读可用';
  String? error;
  bool loading = true;
  bool running = false;
  bool overlayAllowed = false;
  ReadingPreferences preferences = const ReadingPreferences();
  MultilingualReader? _reader;
  PageTranslator? _pageTranslator;
  List<TranslatedParagraph> pageTranslations = const [];
  String _translatedText = '';
  String _translatedDirection = '';
  String get _pageDirection =>
      '${preferences.source.code}|${preferences.target.code}';
  OcrDocument? lastDocument;
  bool translating = false;
  String detectedLanguage = 'en';
  bool get usesEnglishScope =>
      preferences.target == ReadingLanguage.en ||
      (preferences.source == ReadingLanguage.auto
          ? detectedLanguage == 'en' ||
                (detectedLanguage == 'zh' &&
                    preferences.target == ReadingLanguage.zh)
          : preferences.source == ReadingLanguage.en);
  int _analysisRevision = 0;
  String lastText = '';
  List<VocabularyHit> lastHits = const [];
  int? recognitionMs;
  LocalReadingSnapshot? _lastLiveReading;
  int get localSessionPageCount => _lastLiveReading?.pageCount ?? 0;
  int get localSessionWordCount => _lastLiveReading?.hits.length ?? 0;
  int get localSessionCharacterCount => _lastLiveReading?.text.length ?? 0;
  String get _readingResultSignature =>
      '${preferences.source.code}|${preferences.target.code}|${level.name}|${preferences.difficulty.name}${preferences.mode == ReadingMode.translation ? '|translation' : ''}';

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final name = _prefs!.getString('companion_level_v1');
      level =
          VocabularyLevel.values.where((e) => e.name == name).firstOrNull ??
          VocabularyLevel.cet4;
      known.addAll(_prefs!.getStringList('companion_known_v1') ?? []);
      _mergeSaved(_prefs!.getString('companion_saved_v1'));
      try {
        final progress =
            jsonDecode(_prefs!.getString('companion_reviews_v1') ?? '{}')
                as Map;
        for (final item in progress.entries) {
          final value = ReviewProgress.fromJson(item.value);
          if (value != null) reviews[item.key.toString()] = value;
        }
      } catch (_) {
        /* Saved words remain usable if optional progress is damaged. */
      }
      final reading = _prefs!.getString('companion_reading_preferences_v1');
      if (reading != null) {
        preferences = ReadingPreferences.fromJson(jsonDecode(reading) as Map);
      }
      _lastLiveReading = LocalReadingSnapshot.decode(
        _prefs!.getString('companion_last_live_reading_v1'),
      );
      if (_lastLiveReading?.optionsSignature == _readingResultSignature) {
        _restoreLocalSnapshot(_lastLiveReading!);
      }
      engine = await VocabularyEngine.load();
      _reader = MultilingualReader(engine!, assistant);
      if (_disposed) return;
      connection = assistant.isConfigured ? 'AI 讲解待连接检测' : 'AI 尚未连接 · 离线阅读可用';
      if (bridge.supportsLiveCapture) {
        _events = ScreenReaderBridge.events.receiveBroadcastStream().listen(
          _onNativeEvent,
          onError: (_) {
            error = '随屏阅读连接暂时中断，请重新开启。';
            _notify();
          },
        );
      }
      await refreshScreenStatus();
      await _configureNative();
    } catch (_) {
      error = '阅读资源暂未加载完成，请重新打开语渡。';
    } finally {
      loading = false;
      _notify();
    }
  }

  void _mergeSaved(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      for (final value in jsonDecode(raw) as List) {
        final hit = VocabularyHit.fromJson(value);
        if (hit != null) saved[hit.studyKey] = hit;
      }
    } catch (_) {
      /* A damaged optional history must not block reading. */
    }
  }

  Future<void> refreshScreenStatus() async {
    if (!bridge.hasNativeCompanion) return;
    try {
      final status = await bridge.status();
      running = status['running'] == true;
      overlayAllowed = status['overlayAllowed'] == true;
      final nativeLevel = VocabularyLevel.values
          .where((value) => value.name == status['level'])
          .firstOrNull;
      if (nativeLevel != null) level = nativeLevel;
      if (status['sourceLanguage'] != null) {
        preferences = ReadingPreferences.fromJson({
          ...preferences.toJson(),
          ...status,
        });
      }
      known.addAll((status['known'] as List? ?? []).whereType<String>());
      _mergeSaved(status['saved'] as String?);
      detectedLanguage =
          status['detectedLanguage'] as String? ?? detectedLanguage;
      final text = status['lastText'] as String?;
      final signature = _readingResultSignature;
      final history = LocalReadingSnapshot.fromJson(
        status['liveReadingHistory'],
      );
      if (history != null &&
          history.updatedAt >= (_lastLiveReading?.updatedAt ?? 0)) {
        _lastLiveReading = history;
      }
      final latestHistory = _lastLiveReading;
      final restoreHistory =
          !running &&
          history != null &&
          latestHistory != null &&
          latestHistory.optionsSignature == signature &&
          latestHistory.updatedAt >=
              ((status['lastDocumentUpdatedAt'] as num?)?.toDouble() ?? 0);
      if (restoreHistory) _restoreLocalSnapshot(latestHistory);
      final hasPageTranslation =
          !restoreHistory &&
          preferences.mode == ReadingMode.translation &&
          status['translationSegments'] is List;
      if (hasPageTranslation) {
        _acceptTranslation(status);
      }
      if (!restoreHistory &&
          !hasPageTranslation &&
          status['lastOptionsSignature'] == signature &&
          status['lastHits'] is String) {
        lastText = text ?? '';
        lastHits = (jsonDecode(status['lastHits'] as String) as List)
            .map(VocabularyHit.fromJson)
            .whereType<VocabularyHit>()
            .toList();
      } else if (!restoreHistory &&
          !hasPageTranslation &&
          text != null &&
          text.isNotEmpty &&
          text != lastText) {
        if (running) {
          lastText = text;
          lastHits = const [];
        } else {
          analyze(text);
        }
      }
      await _persist();
      _notify();
    } catch (_) {
      error = '这台设备尚未连接随屏阅读模块。';
      _notify();
    }
  }

  Future<void> _configureNative() => bridge.configure(
    level: level.name,
    known: known.toList(),
    proxyUrl: assistant.proxyUrl,
    appSecret: assistant.appSecret,
    saved: jsonEncode(saved.values.map((e) => e.toJson()).toList()),
    readingPreferences: preferences.toJson(),
  );

  void _onNativeEvent(Object? event) {
    if (event is! Map) return;
    switch (event['kind']) {
      case 'translation':
        _acceptTranslation(event);
        break;
      case 'status':
        running = event['running'] == true;
        if (!running) {
          recognitionMs = null;
          unawaited(refreshScreenStatus());
        }
        break;
      case 'capture':
        recognitionMs = (event['durationMs'] as num?)?.toInt();
        detectedLanguage =
            event['detectedLanguage'] as String? ?? detectedLanguage;
        if (event['hits'] is List) {
          lastText = event['text'] as String? ?? '';
          lastHits = (event['hits'] as List)
              .map(VocabularyHit.fromJson)
              .whereType<VocabularyHit>()
              .toList();
        } else {
          analyze(event['text'] as String? ?? '');
        }
        error = null;
        break;
      case 'changed':
        unawaited(refreshScreenStatus());
        break;
      case 'error':
        error = event['message'] as String? ?? '这次识别未完成，请再试一次。';
        break;
    }
    _notify();
  }

  List<VocabularyHit> analyze(String text, {bool reuseLocalSnapshot = true}) {
    if (reuseLocalSnapshot && _reuseLocalSnapshot(text)) return lastHits;
    if (preferences.mode == ReadingMode.translation) {
      unawaited(
        analyzeDocument(
          OcrDocument.fromText(text),
          reuseLocalSnapshot: reuseLocalSnapshot,
        ),
      );
      return const [];
    }
    _analysisRevision++;
    translating = false;
    error = null;
    pageTranslations = const [];
    lastText = text;
    final document = OcrDocument.fromText(text);
    lastDocument = document;
    final resolved = MultilingualReader.resolvePreferences(
      document,
      preferences,
    );
    if (resolved.source == ReadingLanguage.en &&
        resolved.target == ReadingLanguage.zh) {
      lastHits = engine?.extract(text, level, known: known) ?? const [];
    } else {
      lastHits = const [];
      unawaited(
        analyzeDocument(document, reuseLocalSnapshot: reuseLocalSnapshot),
      );
    }
    _notify();
    return lastHits;
  }

  Future<List<VocabularyHit>> analyzeDocument(
    OcrDocument document, {
    bool reuseLocalSnapshot = true,
  }) async {
    if (reuseLocalSnapshot && _reuseLocalSnapshot(document.text)) {
      return lastHits;
    }
    final revision = ++_analysisRevision;
    final direction = _pageDirection;
    lastDocument = document;
    if (preferences.mode == ReadingMode.translation &&
        _translatedText == document.text &&
        _translatedDirection == _pageDirection &&
        pageTranslations.isNotEmpty &&
        pageTranslations.every((p) => p.translation != null)) {
      lastText = document.text;
      lastHits = const [];
      translating = false;
      error = null;
      _notify();
      return const [];
    }
    detectedLanguage = MultilingualReader.resolvePreferences(
      document,
      preferences,
    ).source.code;
    lastText = document.text;
    translating = true;
    lastHits = const [];
    error = null;
    _notify();
    try {
      if (preferences.mode == ReadingMode.translation) {
        final remembered = _lastLiveReading;
        final retryingHistory =
            !reuseLocalSnapshot &&
            remembered != null &&
            remembered.text == document.text &&
            remembered.optionsSignature == _readingResultSignature;
        final resolved = MultilingualReader.resolvePreferences(
          document,
          retryingHistory ? _snapshotPreferences(remembered) : preferences,
        );
        pageTranslations = retryingHistory
            ? remembered.parts
            : TranslatedParagraph.split(document.text);
        _notify();
        final translator = _pageTranslator ??= PageTranslator(assistant);
        void onUpdate(List<TranslatedParagraph> parts) {
          if (!_disposed && revision == _analysisRevision) {
            pageTranslations = parts;
            _translatedText = document.text;
            _translatedDirection = direction;
            if (retryingHistory) {
              _lastLiveReading = remembered.withResults(parts: parts);
              unawaited(_persist());
            }
            _notify();
          }
        }

        if (retryingHistory) {
          await translator.translateRememberedParts(
            remembered.parts,
            resolved.source,
            resolved.target,
            isCurrent: () => !_disposed && revision == _analysisRevision,
            onUpdate: onUpdate,
          );
        } else {
          await translator.translate(
            document.text,
            resolved.source,
            resolved.target,
            isCurrent: () => !_disposed && revision == _analysisRevision,
            onUpdate: onUpdate,
          );
        }
        return const [];
      }
      final hits =
          await _reader?.analyze(document, preferences, level, known: known) ??
          const <VocabularyHit>[];
      if (!_disposed && revision == _analysisRevision) {
        lastHits = hits;
      }
      return hits;
    } catch (failure) {
      if (!_disposed && revision == _analysisRevision) {
        error = failure is AssistantUnavailable
            ? failure.message
            : '翻译暂时没有完成，请重试。';
      }
      return const [];
    } finally {
      if (revision == _analysisRevision) {
        translating = false;
        _notify();
      }
    }
  }

  void _restoreLocalSnapshot(LocalReadingSnapshot snapshot) {
    _analysisRevision++;
    lastText = snapshot.text;
    lastDocument = OcrDocument.fromText(lastText);
    lastHits = snapshot.hits
        .where((hit) => !known.contains(hit.studyKey))
        .toList();
    pageTranslations = snapshot.parts;
    translating = false;
    error =
        preferences.mode == ReadingMode.translation &&
            pageTranslations.any((part) => part.translation == null)
        ? '部分段落尚未完成，已识别原文和已有译文已保存在本机。'
        : null;
    _translatedText = snapshot.text;
    _translatedDirection = _pageDirection;
    detectedLanguage = snapshot.resolvedSource ?? detectedLanguage;
    if (snapshot.parts.isNotEmpty) {
      final resolved = MultilingualReader.resolvePreferences(
        OcrDocument.fromText(snapshot.text),
        _snapshotPreferences(snapshot).copyWith(mode: ReadingMode.translation),
      );
      (_pageTranslator ??= PageTranslator(
        assistant,
      )).remember(snapshot.parts, resolved.source, resolved.target);
    }
  }

  ReadingPreferences _snapshotPreferences(LocalReadingSnapshot snapshot) =>
      preferences.copyWith(
        source: ReadingLanguage.values
            .where((language) => language.code == snapshot.resolvedSource)
            .firstOrNull,
        target: ReadingLanguage.values
            .where((language) => language.code == snapshot.resolvedTarget)
            .firstOrNull,
      );

  bool _reuseLocalSnapshot(String text) {
    final snapshot = _lastLiveReading;
    if (snapshot == null ||
        snapshot.text != text ||
        snapshot.optionsSignature != _readingResultSignature) {
      return false;
    }
    _restoreLocalSnapshot(snapshot);
    _notify();
    return true;
  }

  Future<void> setReadingPreferences(ReadingPreferences value) async {
    // Invalidate before awaiting persistence/configuration. Otherwise an old
    // response could be labelled with the newly selected direction and reused.
    _analysisRevision++;
    preferences = value;
    await _persist();
    await _configureNative();
    if (lastDocument != null) {
      await analyzeDocument(lastDocument!);
    } else if (lastText.isNotEmpty) {
      analyze(lastText);
    }
    _notify();
  }

  void _acceptTranslation(Map event) {
    _analysisRevision++;
    lastText =
        event['text'] as String? ?? event['lastText'] as String? ?? lastText;
    lastHits = const [];
    translating = event['translationLoading'] == true;
    error = event['translationError'] as String?;
    final items = event['translationSegments'];
    if (items is List) {
      pageTranslations = items
          .whereType<Map>()
          .where((p) => p['source'] is String)
          .map(
            (p) => TranslatedParagraph(
              p['id']?.toString() ?? '',
              p['source'] as String,
              p['translation'] as String?,
            ),
          )
          .toList();
      _translatedText = lastText;
      _translatedDirection = _pageDirection;
      final resolved = MultilingualReader.resolvePreferences(
        OcrDocument.fromText(lastText),
        preferences.copyWith(mode: ReadingMode.translation),
      );
      (_pageTranslator ??= PageTranslator(
        assistant,
      )).remember(pageTranslations, resolved.source, resolved.target);
    }
  }

  Future<void> setLevel(VocabularyLevel next) async {
    level = next;
    await _prefs?.setString('companion_level_v1', next.name);
    if (lastDocument != null) {
      unawaited(analyzeDocument(lastDocument!));
    } else if (lastText.isNotEmpty) {
      analyze(lastText);
    }
    await _configureNative();
    _notify();
  }

  Future<void> save(VocabularyHit hit) async {
    saved.remove(hit.studyKey);
    saved[hit.studyKey] = hit;
    await _persist();
    await _configureNative();
    _notify();
  }

  Future<void> removeSaved(String word) async {
    if (saved.containsKey(word)) {
      saved.remove(word);
    } else {
      saved.removeWhere((key, hit) => hit.entry.word == word);
    }
    await _persist();
    await _configureNative();
    _notify();
  }

  List<VocabularyHit> dueWords({DateTime? at}) {
    final now = at ?? DateTime.now();
    final result = saved.values
        .where(
          (hit) =>
              !known.contains(hit.studyKey) &&
              !(reviews[hit.studyKey]?.due.isAfter(now) ?? false),
        )
        .toList();
    result.sort(
      (a, b) => (reviews[a.studyKey]?.due ?? DateTime(1970)).compareTo(
        reviews[b.studyKey]?.due ?? DateTime(1970),
      ),
    );
    return result;
  }

  int get reviewedToday {
    final today = DateTime.now();
    return reviews.values.where((value) {
      final at = value.lastReviewed?.toLocal();
      return at != null &&
          at.year == today.year &&
          at.month == today.month &&
          at.day == today.day;
    }).length;
  }

  Future<void> gradeReview(
    String key,
    RecallRating rating, {
    DateTime? at,
  }) async {
    if (!saved.containsKey(key)) return;
    final now = at ?? DateTime.now();
    reviews[key] = (reviews[key] ?? ReviewProgress(due: now)).grade(
      rating,
      now,
    );
    await _prefs?.setString(
      'companion_reviews_v1',
      jsonEncode(reviews.map((key, value) => MapEntry(key, value.toJson()))),
    );
    _notify();
  }

  String exportLearningBackup() => jsonEncode({
    'format': 'lingfer-learning',
    'version': 1,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'saved': saved.values.map((hit) => hit.toJson()).toList(),
    'known': known.toList(),
    'reviews': Map.fromEntries(
      reviews.entries
          .where((item) => saved.containsKey(item.key))
          .map((item) => MapEntry(item.key, item.value.toJson())),
    ),
  });

  /// Import adds to the existing book. Credentials and service settings never
  /// enter a backup, and a file cannot replace the current reading preferences.
  Future<int> importLearningBackup(String payload) async {
    if (utf8.encode(payload).length > 5 * 1024 * 1024)
      throw const FormatException('备份文件不能超过 5 MB');
    final raw = jsonDecode(payload);
    if (raw is! Map ||
        raw['format'] != 'lingfer-learning' ||
        raw['version'] != 1 ||
        raw['saved'] is! List) {
      throw const FormatException('这不是受支持的语渡学习备份');
    }
    final imported = (raw['saved'] as List)
        .map(VocabularyHit.fromJson)
        .whereType<VocabularyHit>()
        .toList();
    if (imported.length > 20000) throw const FormatException('备份中的词条过多');
    if ((raw['known'] != null && raw['known'] is! List) ||
        (raw['reviews'] != null && raw['reviews'] is! Map))
      throw const FormatException('备份数据格式不正确');
    final importedKnown = (raw['known'] as List? ?? [])
        .whereType<String>()
        .toList();
    if (importedKnown.length > 20000 ||
        (raw['reviews'] as Map? ?? {}).length > 20000)
      throw const FormatException('备份中的词条过多');
    final progressToMerge = <String, ReviewProgress>{};
    for (final item in (raw['reviews'] as Map? ?? {}).entries) {
      try {
        final value = ReviewProgress.fromJson(item.value);
        if (value != null) progressToMerge[item.key.toString()] = value;
      } catch (_) {
        /* A damaged optional progress entry doesn't discard words. */
      }
    }
    var added = 0;
    for (final hit in imported) {
      if (!saved.containsKey(hit.studyKey)) {
        saved[hit.studyKey] = hit;
        added++;
      }
    }
    known.addAll(importedKnown);
    for (final item in progressToMerge.entries) {
      final progress = item.value;
      final key = item.key;
      if (!saved.containsKey(key)) continue;
      final current = reviews[key];
      if (current == null ||
          (progress.lastReviewed ?? DateTime(1970)).isAfter(
            current.lastReviewed ?? DateTime(1970),
          ))
        reviews[key] = progress;
    }
    await _persist();
    await _prefs?.setString(
      'companion_reviews_v1',
      jsonEncode(reviews.map((key, value) => MapEntry(key, value.toJson()))),
    );
    await _configureNative();
    _notify();
    return added;
  }

  Future<void> markKnown(String word, {bool value = true}) async {
    value ? known.add(word) : known.remove(word);
    if (lastDocument != null) {
      unawaited(analyzeDocument(lastDocument!));
    } else if (lastText.isNotEmpty) {
      analyze(lastText);
    }
    await _persist();
    await _configureNative();
    _notify();
  }

  Future<void> _persist() async {
    await _prefs?.setString('companion_level_v1', level.name);
    await _prefs?.setString(
      'companion_reading_preferences_v1',
      jsonEncode(preferences.toJson()),
    );
    await _prefs?.setStringList('companion_known_v1', known.toList());
    await _prefs?.setString(
      'companion_saved_v1',
      jsonEncode(saved.values.map((e) => e.toJson()).toList()),
    );
    if (_lastLiveReading != null) {
      final encoded = jsonEncode(_lastLiveReading!.toJson());
      if (utf8.encode(encoded).length <= LocalReadingSnapshot.maximumBytes) {
        await _prefs?.setString('companion_last_live_reading_v1', encoded);
      }
    }
  }

  Future<bool> start() async {
    error = null;
    try {
      await _configureNative();
      return await bridge.start();
    } catch (_) {
      error = bridge.supported
          ? '未能开启随屏阅读，请检查悬浮窗权限后重试。'
          : '未能开启随屏阅读，请在系统面板允许屏幕共享后重试。';
      _notify();
      return false;
    }
  }

  Future<void> stop() async {
    await bridge.stop();
    running = false;
    await refreshScreenStatus();
    _notify();
  }

  Future<void> checkConnection() async {
    connection = '正在检查连接…';
    _notify();
    connection = await assistant.checkConnection();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    assistant.dispose();
    super.dispose();
  }
}

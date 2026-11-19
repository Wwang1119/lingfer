import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_state.dart';
import '../../models/book.dart';
import '../../models/reader_theme.dart';
import '../../models/translation_mode.dart';
import '../../models/vocabulary_level.dart';
import '../../services/ai_translation_service.dart';
import '../../services/book_text_service.dart';
import '../../services/reader_translation_cache.dart';
import '../../services/reader_text_anchor.dart';
import '../../widgets/apple_glass_sheet.dart';
import '../../widgets/liquid_selection_controls.dart';
import '../../widgets/reading_text.dart';
import '../../widgets/book_display_title.dart';
import '../../widgets/book_reader_presentation.dart';
import '../../features/companion/lingfer_theme.dart';
import '../../utils/level_color.dart';

const String _deepSeekProxyUrl = String.fromEnvironment(
  'DEEPSEEK_PROXY_URL',
  defaultValue: '',
);
const String _appSecret = String.fromEnvironment(
  'APP_SECRET',
  defaultValue: '',
);

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, required this.book, this.translationService});

  final Book book;
  final AiTranslationService? translationService;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  static const int _chunkSizeChars = 1000;
  static const int _pagesPerChapter = 20;
  static const String _layoutPrefsKey = 'reader_layout_direction';
  static const double _persistentHudTop = 44;
  static const double _persistentHudBottom = 44;

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  final BookTextService _bookTextService = BookTextService();
  final PageController _pageController = PageController();

  // Apple Glass panel state (kept in-route so selection handles can coexist).
  final ValueNotifier<String> _glassSelectedText = ValueNotifier<String>('');
  final ValueNotifier<int> _unitIndex = ValueNotifier<int>(0);
  bool _glassVisible = false;
  AppleGlassDock _glassDock = AppleGlassDock.bottom;
  Timer? _glassDebounce;
  String? _pendingGlassText;
  int _anchorIndex = 0;
  Offset? _lastPointerDownGlobal;
  late final AiTranslationService _aiGlass = AiTranslationService(
    proxyUrl: _deepSeekProxyUrl,
    appSecret: _appSecret,
  );

  SharedPreferences? _prefs;
  Directory? _tmpDir;
  late final String _bookCacheKey;

  late Book _book;
  late String _bookId;

  VocabularyLevel _currentLevel = VocabularyLevel.cet4;
  TranslationMode _mode = TranslationMode.zhToEn;
  ReaderTheme _theme = ReaderTheme.original;
  double _fontSize = 18;
  bool _chromeVisible = false;
  bool _settingsVisible = false;
  bool _rotationLocked = false;
  String _lastSelectionText = '';
  final Map<int, int> _bookmarks = <int, int>{}; // unitIndex -> createdAtMs
  final List<_HighlightMark> _highlights = <_HighlightMark>[];
  _ReaderLayoutDirection _layoutDirection = _ReaderLayoutDirection.horizontal;
  String _bookText = '';
  List<String> _allChunks = const [];
  String _displayText = '';
  List<int> _chunkDisplayStarts = const [];
  List<_PageSlice> _pages = const [];
  String _paginationKey = '';
  double _horizontalTextHeight = 0;
  bool _repaginateScheduled = false;

  final Map<int, _ChunkRender> _rendered = <int, _ChunkRender>{};
  final Set<int> _inFlight = <int>{};
  final Set<int> _failedChunks = <int>{};
  int _translatingCount = 0;
  int _translationGeneration = 0;
  final Set<int> _pendingChunkLoads = <int>{};
  final Map<int, bool> _pendingAllowNetwork = <int, bool>{};
  bool _postFrameLoadScheduled = false;
  Timer? _progressDebounce;

  bool _initializing = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _bookId = widget.book.stableKey;
    _currentLevel = widget.book.defaultLevel;
    // V2.0 default: horizontal paging every time a book is opened.
    _layoutDirection = _ReaderLayoutDirection.horizontal;
    _bookCacheKey = _fnvCacheKey(widget.book.source.name, widget.book.locator);
    _positionsListener.itemPositions.addListener(_onPositionsChanged);
    _initBook();
  }

  @override
  void dispose() {
    _progressDebounce?.cancel();
    _glassDebounce?.cancel();
    _glassSelectedText.dispose();
    _unitIndex.dispose();
    _positionsListener.itemPositions.removeListener(_onPositionsChanged);
    // Don't leak orientation locks to other pages.
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    super.dispose();
  }

  void _onSelectionChanged(SelectedContent? content) {
    final text = (content?.plainText ?? '').trim();
    if (text.isEmpty) return;
    _lastSelectionText = text;

    final y = _lastPointerDownGlobal?.dy;
    final h = MediaQuery.sizeOf(context).height;
    final nextDock = (y != null && y > h * 0.5)
        ? AppleGlassDock.top
        : AppleGlassDock.bottom;
    if (_chromeVisible || _settingsVisible || nextDock != _glassDock) {
      setState(() {
        _chromeVisible = false;
        _settingsVisible = false;
        _glassDock = nextDock;
      });
      _scheduleHorizontalRepagination();
    }

    _pendingGlassText = text;
    _glassDebounce?.cancel();
    _glassDebounce = Timer(const Duration(milliseconds: 240), () {
      final stable = _pendingGlassText;
      if (!mounted || stable == null) return;
      final t = stable.trim();
      if (t.isEmpty) return;

      final next = !_glassVisible ? _smartExpandInitialSelection(t) : t;

      if (!_glassVisible) {
        setState(() => _glassVisible = true);
      }
      if (_glassSelectedText.value != next) {
        _glassSelectedText.value = next;
      }
    });
  }

  String _smartExpandInitialSelection(String selectedText) {
    final t = selectedText.trim();
    if (t.isEmpty) return t;
    // Avoid aggressive expansion when the user already selected a paragraph.
    if (t.length > 80) return t;

    final candidates = <int>[_anchorIndex, _anchorIndex - 1, _anchorIndex + 1];
    for (final idx in candidates) {
      final unit = _unitTextForSelection(idx);
      if (unit == null) continue;
      final expanded = _expandToSentence(unit, t);
      if (expanded != null) return expanded;
    }
    return t;
  }

  String? _unitTextForSelection(int unitIndex) {
    if (_layoutDirection == _ReaderLayoutDirection.vertical) {
      if (unitIndex < 0 || unitIndex >= _allChunks.length) return null;
      return _rendered[unitIndex]?.text ?? _allChunks[unitIndex];
    }
    if (unitIndex < 0 || unitIndex >= _pages.length) return null;
    if (_displayText.isEmpty) return null;
    final slice = _pages[unitIndex];
    final start = slice.start.clamp(0, _displayText.length);
    final end = slice.end.clamp(start, _displayText.length);
    return _displayText.substring(start, end);
  }

  String? _expandToSentence(String full, String needle) {
    if (full.isEmpty || needle.isEmpty) return null;

    int pos = full.indexOf(needle);
    if (pos < 0) {
      // Case-insensitive fallback for English selections.
      final lowerFull = full.toLowerCase();
      final lowerNeedle = needle.toLowerCase();
      pos = lowerFull.indexOf(lowerNeedle);
      if (pos < 0) return null;
    }

    int start = pos;
    for (var i = pos - 1; i >= 0; i -= 1) {
      final ch = full.codeUnitAt(i);
      if (_isSentenceBoundary(ch)) {
        start = i + 1;
        break;
      }
      if (i == 0) start = 0;
    }

    int end = pos + needle.length;
    for (var i = end; i < full.length; i += 1) {
      final ch = full.codeUnitAt(i);
      if (_isSentenceBoundary(ch)) {
        end = i + 1;
        break;
      }
      if (i == full.length - 1) end = full.length;
    }

    final s = full.substring(start, end).trim();
    if (s.isEmpty) return null;
    // Don't expand into something unrelated.
    if (!s.toLowerCase().contains(needle.toLowerCase())) return null;
    return s;
  }

  bool _isSentenceBoundary(int codeUnit) {
    switch (codeUnit) {
      case 0x0A: // \n
      case 0x0D: // \r
      case 0x2E: // .
      case 0x3F: // ?
      case 0x21: // !
      case 0x3002: // 。
      case 0xFF1F: // ？
      case 0xFF01: // ！
        return true;
      default:
        return false;
    }
  }

  Future<void> _initBook() async {
    _translationGeneration += 1;
    setState(() {
      _initializing = true;
      _loadError = null;
      _bookText = '';
      _allChunks = const [];
      _displayText = '';
      _chunkDisplayStarts = const [];
      _pages = const [];
      _paginationKey = '';
      _horizontalTextHeight = 0;
      _repaginateScheduled = false;
      _rendered.clear();
      _inFlight.clear();
      _failedChunks.clear();
      _translatingCount = 0;
      _pendingChunkLoads.clear();
      _pendingAllowNetwork.clear();
      _postFrameLoadScheduled = false;
    });

    try {
      _prefs ??= await SharedPreferences.getInstance();
      _tmpDir ??= await getTemporaryDirectory();
      _fontSize = (_prefs?.getDouble('reader_font_size') ?? 18)
          .clamp(14, 26)
          .toDouble();
      _theme = ReaderTheme.fromPrefs(_prefs?.getString('reader_theme'));
      _rotationLocked = _prefs?.getBool('reader_rotation_locked') ?? false;
      _loadMarksFromPrefs();

      final text = await _bookTextService.readBookText(_book);
      if (!mounted) return;
      if (text.trim().isEmpty) {
        throw const FormatException('这份资料没有可阅读的正文，请返回后重新导入。');
      }
      final languageSample = text.substring(0, math.min(text.length, 2400));
      final latinCount = RegExp(r'[A-Za-z]').allMatches(languageSample).length;
      final chineseCount = RegExp(
        r'[\u3400-\u9FFF]',
      ).allMatches(languageSample).length;
      setState(() {
        _bookText = text;
        if (latinCount >= 40 && latinCount > chineseCount * 2) {
          _mode = TranslationMode.enToZh;
        }
        _initializing = false;
      });

      // Apply rotation lock after we have a valid BuildContext.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyRotationLock(_rotationLocked);
      });

      // Build chunks/pages after first layout so we can paginate for PageView.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _rebuildUnitsAndRestoreProgress();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error is FileSystemException
            ? '原文件暂时无法读取，请返回后重新导入这份资料。'
            : '$error'.replaceFirst(
                RegExp(r'^(?:FormatException|BookReadException|Exception):\s*'),
                '',
              );
        _initializing = false;
      });
    }
  }

  List<String> _splitIntoChunks(String text, int targetChars) {
    final chunks = <String>[];
    if (text.isEmpty) return chunks;

    var start = 0;
    while (start < text.length) {
      var end = start + targetChars;
      if (end >= text.length) {
        chunks.add(text.substring(start));
        break;
      }

      final windowStart = start + (targetChars * 0.65).floor();
      final splitAt = text.lastIndexOf('\n', end);
      if (splitAt >= windowStart) {
        end = splitAt + 1;
      }

      chunks.add(text.substring(start, end));
      start = end;
    }
    return chunks;
  }

  ({String displayText, List<int> chunkStarts}) _composeDisplayText({
    List<String>? chunksOverride,
  }) {
    final chunks = chunksOverride ?? _allChunks;
    if (chunks.isEmpty) return (displayText: '', chunkStarts: const []);

    final sb = StringBuffer();
    final starts = <int>[];
    var offset = 0;
    for (var i = 0; i < chunks.length; i += 1) {
      starts.add(offset);
      final t = _rendered[i]?.text ?? chunks[i];
      sb.write(t);
      offset += t.length;
    }
    return (displayText: sb.toString(), chunkStarts: starts);
  }

  int _chunkIndexForDisplayOffset(int offset) {
    if (_chunkDisplayStarts.isEmpty) return 0;
    final target = math.max(0, offset).toInt();
    var lo = 0;
    var hi = _chunkDisplayStarts.length - 1;
    var ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final start = _chunkDisplayStarts[mid];
      if (start <= target) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans.clamp(0, _chunkDisplayStarts.length - 1);
  }

  void _requestChunksForPage(int pageIndex, {required bool allowNetwork}) {
    if (_layoutDirection != _ReaderLayoutDirection.horizontal) {
      _requestChunkLoad(pageIndex, allowNetwork: allowNetwork);
      return;
    }
    if (pageIndex < 0 || pageIndex >= _pages.length) return;
    if (_displayText.isEmpty || _chunkDisplayStarts.isEmpty) return;

    final slice = _pages[pageIndex];
    final start = slice.start.clamp(0, _displayText.length);
    final end = slice.end.clamp(start, _displayText.length);
    if (end <= start) return;

    final startChunk = _chunkIndexForDisplayOffset(start);
    final endChunk = _chunkIndexForDisplayOffset(math.max(start, end - 1));
    for (var i = startChunk; i <= endChunk && i < _allChunks.length; i += 1) {
      _requestChunkLoad(i, allowNetwork: allowNetwork);
    }
  }

  Widget _buildHorizontalPageText(_PageSlice slice, Color baseColor) {
    if (_displayText.isEmpty || _pages.isEmpty) {
      return const SizedBox.shrink();
    }
    final start = slice.start.clamp(0, _displayText.length);
    final end = slice.end.clamp(start, _displayText.length);
    if (end <= start) return const SizedBox.shrink();

    // Fallback (shouldn't happen): render as a single-color chunk.
    if (_chunkDisplayStarts.isEmpty || _allChunks.isEmpty) {
      return ReadingText(
        chunkText: _displayText.substring(start, end),
        annotations: const [],
        accentColor: const Color(0xFF999999),
        fontSize: _fontSize,
        baseColor: baseColor,
      );
    }

    const textHeightBehavior = TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    );
    final baseStyle = BookReaderTypography.body(
      size: _fontSize,
      ink: baseColor,
    );
    final strut = StrutStyle(
      fontSize: _fontSize,
      height: 1.6,
      forceStrutHeight: true,
    );

    final spans = <TextSpan>[];
    final startChunk = _chunkIndexForDisplayOffset(start);
    final endChunk = _chunkIndexForDisplayOffset(math.max(start, end - 1));

    for (
      var chunkIndex = startChunk;
      chunkIndex <= endChunk && chunkIndex < _allChunks.length;
      chunkIndex += 1
    ) {
      final chunkStart = _chunkDisplayStarts[chunkIndex];
      final chunkEnd = (chunkIndex + 1 < _chunkDisplayStarts.length)
          ? _chunkDisplayStarts[chunkIndex + 1]
          : _displayText.length;
      final segStart = math.max(start, chunkStart);
      final segEnd = math.min(end, chunkEnd);
      if (segEnd <= segStart) continue;

      final chunkText = _rendered[chunkIndex]?.text ?? _allChunks[chunkIndex];
      final localStart = (segStart - chunkStart)
          .clamp(0, chunkText.length)
          .toInt();
      final localEnd = (segEnd - chunkStart)
          .clamp(localStart, chunkText.length)
          .toInt();
      if (localEnd <= localStart) continue;

      final accentStyle = BookReaderTypography.annotation(
        size: _fontSize,
        ink: baseColor,
      );

      spans.addAll(
        ReadingText.spansForAnnotations(
          chunkText,
          start: localStart,
          end: localEnd,
          annotations: _rendered[chunkIndex]?.annotations ?? const [],
          accentStyle: accentStyle,
        ),
      );
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      textScaler: MediaQuery.textScalerOf(context),
      textAlign: TextAlign.start,
      overflow: TextOverflow.clip,
      strutStyle: strut,
      textHeightBehavior: textHeightBehavior,
    );
  }

  _ReaderAnchor? _readingSourceAnchor() {
    if (_pages.isEmpty || _chunkDisplayStarts.isEmpty) return null;
    final page = _anchorIndex.clamp(0, _pages.length - 1);
    final position = _pages[page].start;
    final chunk = _chunkIndexForDisplayOffset(position);
    final local = position - _chunkDisplayStarts[chunk];
    return (
      chunk: chunk,
      sourceOffset: ReaderTextAnchor.sourceOffset(
        local,
        _rendered[chunk]?.annotations ?? const [],
      ),
    );
  }

  void _scheduleHorizontalRepagination({_ReaderAnchor? anchor}) {
    if (_layoutDirection != _ReaderLayoutDirection.horizontal) return;
    if (_repaginateScheduled) return;
    _repaginateScheduled = true;
    final sourceAnchor = anchor ?? _readingSourceAnchor();
    final generation = _translationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repaginateScheduled = false;
      if (!mounted || generation != _translationGeneration) return;
      _recomputeHorizontalPagination(
        keepPageIndex: _anchorIndex,
        sourceAnchor: sourceAnchor,
      );
    });
  }

  void _recomputeHorizontalPagination({
    int? keepPageIndex,
    _ReaderAnchor? sourceAnchor,
  }) {
    if (_layoutDirection != _ReaderLayoutDirection.horizontal) return;
    var keep = keepPageIndex ?? _anchorIndex;
    final composed = _composeDisplayText();
    final paginated = _paginateForHorizontal(context, composed.displayText);
    if (sourceAnchor != null &&
        sourceAnchor.chunk < composed.chunkStarts.length) {
      final chunk = sourceAnchor.chunk;
      final offset =
          composed.chunkStarts[chunk] +
          ReaderTextAnchor.renderedOffset(
            sourceAnchor.sourceOffset,
            _rendered[chunk]?.annotations ?? const [],
          );
      final anchoredPage = paginated.pages.lastIndexWhere(
        (page) => page.start <= offset,
      );
      if (anchoredPage >= 0) keep = anchoredPage;
    }

    setState(() {
      _displayText = composed.displayText;
      _chunkDisplayStarts = composed.chunkStarts;
      _pages = paginated.pages;
      _horizontalTextHeight = paginated.textHeight;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final clamped = _pages.isEmpty ? 0 : keep.clamp(0, _pages.length - 1);
      try {
        _pageController.jumpToPage(clamped);
      } catch (_) {}
      _anchorIndex = clamped;
      if (_unitIndex.value != clamped) {
        _unitIndex.value = clamped;
      }
      _requestChunksForPage(clamped, allowNetwork: true);
      _requestChunksForPage(clamped + 1, allowNetwork: true);
    });
  }

  ({double width, double height}) _horizontalViewport(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final padding = mq.padding;

    const side = 26.0;
    final safeWidth = size.width - padding.left - padding.right;
    final safeHeight = size.height - padding.top - padding.bottom;

    // Keep pagination math consistent with the actual reading viewport:
    // we reserve space for the persistent title + page indicator (HUD).
    final topReserved = (_topPadding(context) - padding.top).clamp(
      0.0,
      safeHeight,
    );
    final bottomReserved = (_bottomPadding(context) - padding.bottom).clamp(
      0.0,
      safeHeight,
    );

    final width = (safeWidth - side * 2).clamp(240.0, 2400.0);
    final height = (safeHeight - topReserved - bottomReserved).clamp(
      240.0,
      8000.0,
    );
    return (width: width, height: height);
  }

  ({List<_PageSlice> pages, double textHeight}) _paginateForHorizontal(
    BuildContext context,
    String text,
  ) {
    final viewport = _horizontalViewport(context);
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final scaleFactor = scaler.scale(1.0);

    final baseStyle = const TextStyle(
      height: 1.6,
      letterSpacing: 0.5,
      fontFamilyFallback: ['.SF UI Text', '.SF Pro Text', 'PingFang SC'],
      decoration: TextDecoration.none,
    ).copyWith(fontSize: _fontSize);

    const textHeightBehavior = TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    );
    final strutStyle = StrutStyle(
      fontSize: baseStyle.fontSize,
      height: baseStyle.height,
      forceStrutHeight: true,
    );

    // Physics-based line height: use TextPainter metrics instead of pure math.
    final sample = TextPainter(
      text: TextSpan(text: 'A', style: baseStyle),
      textDirection: dir,
      textScaler: scaler,
      locale: locale,
      textHeightBehavior: textHeightBehavior,
      strutStyle: strutStyle,
    )..layout(maxWidth: viewport.width);

    final realAvailableHeight = viewport.height;
    final exactLineHeight = sample.preferredLineHeight;
    final maxLines = math.max(
      1,
      (realAvailableHeight / exactLineHeight).floor(),
    );
    final textHeight = maxLines * exactLineHeight;

    _paginationKey = _fnvCacheKey(
      'p',
      '${viewport.width.round()}x$maxLines'
          '_lh${exactLineHeight.toStringAsFixed(3)}'
          '_fs${_fontSize.toStringAsFixed(1)}'
          '_ts${scaleFactor.toStringAsFixed(3)}',
    );

    final pages = _paginateTextSlices(
      text,
      style: baseStyle,
      maxWidth: viewport.width,
      maxHeight: textHeight,
      maxLines: maxLines,
      textScaler: scaler,
      textDirection: dir,
      locale: locale,
    );

    return (pages: pages, textHeight: textHeight);
  }

  List<_PageSlice> _paginateTextSlices(
    String text, {
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
    required int maxLines,
    required TextScaler textScaler,
    required TextDirection textDirection,
    Locale? locale,
  }) {
    final pages = <_PageSlice>[];
    if (text.trim().isEmpty) return pages;

    // Sliding window avoids laying out the entire remaining book each time.
    const int minWindowChars = 1200;
    const int maxWindowChars = 12000;
    const int breakLookback = 120;

    const textHeightBehavior = TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    );
    final strutStyle = StrutStyle(
      fontSize: style.fontSize,
      height: style.height,
      forceStrutHeight: true,
    );

    final painter = TextPainter(
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      maxLines: maxLines,
      textHeightBehavior: textHeightBehavior,
      strutStyle: strutStyle,
    );

    var start = 0;
    var lastPageChars = minWindowChars;

    while (start < text.length) {
      // Skip leading whitespace/newlines so we don't produce empty pages.
      while (start < text.length) {
        final ch = text.codeUnitAt(start);
        if (ch == 0x0A || // \n
            ch == 0x0D || // \r
            ch == 0x20 || // space
            ch == 0x09) {
          // tab
          start += 1;
          continue;
        }
        break;
      }
      if (start >= text.length) break;

      final remaining = text.length - start;
      // dart:math min/max return `num`, but pagination indices must be `int`.
      int windowChars = math.max(minWindowChars, lastPageChars * 3).toInt();
      windowChars = windowChars.clamp(minWindowChars, maxWindowChars).toInt();
      int windowEnd = start + math.min(remaining, windowChars).toInt();

      int end;
      while (true) {
        final sub = text.substring(start, windowEnd);
        painter.text = TextSpan(text: sub, style: style);
        painter.layout(maxWidth: maxWidth);

        if (painter.didExceedMaxLines || windowEnd >= text.length) {
          final pos = painter.getPositionForOffset(
            Offset(maxWidth, math.max(0, maxHeight - 0.5)),
          );
          final cut = pos.offset.clamp(1, sub.length).toInt();
          end = start + cut;
          end = _adjustPageBreak(text, start, end, lookback: breakLookback);
          break;
        }

        // Not filled yet: expand window (doubling, capped).
        final doubled = (windowEnd - start) * 2;
        final nextChars = doubled.clamp(minWindowChars, maxWindowChars).toInt();
        final nextEnd = start + math.min(remaining, nextChars).toInt();
        if (nextEnd <= windowEnd) {
          end = windowEnd;
          break;
        }
        windowEnd = nextEnd;
      }

      if (end <= start) {
        end = math.min(text.length, start + 1).toInt();
      }

      pages.add(_PageSlice(start, end));
      lastPageChars = math.max(400, end - start).toInt();
      start = end;
    }

    return pages;
  }

  int _adjustPageBreak(
    String full,
    int start,
    int end, {
    required int lookback,
  }) {
    if (end >= full.length) return full.length;
    final min = math.max(start, end - lookback).toInt();

    // Prefer splitting on newline.
    for (var i = end - 1; i >= min; i -= 1) {
      if (full.codeUnitAt(i) == 0x0A) {
        final candidate = i + 1;
        if (candidate > start) return candidate;
      }
    }

    // Fallback: split on whitespace.
    for (var i = end - 1; i >= min; i -= 1) {
      final ch = full.codeUnitAt(i);
      if (ch == 0x20 || ch == 0x09) {
        final candidate = i + 1;
        if (candidate > start) return candidate;
      }
    }

    return end;
  }

  String _progressKey() {
    if (_layoutDirection == _ReaderLayoutDirection.horizontal) {
      final p = _paginationKey.isEmpty ? 'p0' : _paginationKey;
      return 'progress_page_${_bookId}_$p';
    }
    return 'progress_topChunk_$_bookId';
  }

  String _bookmarkKey() {
    return _layoutDirection == _ReaderLayoutDirection.horizontal
        ? 'bookmark_page_$_bookId'
        : 'bookmark_chunk_$_bookId';
  }

  String _bookmarksKey() {
    return _layoutDirection == _ReaderLayoutDirection.horizontal
        ? 'bookmarks_page_$_bookId'
        : 'bookmarks_chunk_$_bookId';
  }

  String _highlightsKey() {
    return _layoutDirection == _ReaderLayoutDirection.horizontal
        ? 'highlights_page_$_bookId'
        : 'highlights_chunk_$_bookId';
  }

  void _loadMarksFromPrefs() {
    final prefs = _prefs;
    if (prefs == null) return;

    // Bookmarks.
    final nextBookmarks = <int, int>{};
    try {
      final raw = prefs.getString(_bookmarksKey());
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final i = item['i'];
            final t = item['t'];
            if (i is int) {
              nextBookmarks[i] = (t is int)
                  ? t
                  : DateTime.now().millisecondsSinceEpoch;
            }
          }
        }
      }
    } catch (_) {}

    // Legacy single bookmark (migrate into the list).
    try {
      final legacy = prefs.getInt(_bookmarkKey());
      if (legacy != null) {
        nextBookmarks.putIfAbsent(
          legacy,
          () => DateTime.now().millisecondsSinceEpoch,
        );
        unawaited(prefs.remove(_bookmarkKey()));
        unawaited(_persistBookmarks(from: nextBookmarks));
      }
    } catch (_) {}

    _bookmarks
      ..clear()
      ..addAll(nextBookmarks);

    // Highlights.
    final nextHighlights = <_HighlightMark>[];
    try {
      final raw = prefs.getString(_highlightsKey());
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final mark = _HighlightMark.fromJson(item);
            if (mark == null) continue;
            nextHighlights.add(mark);
          }
        }
      }
    } catch (_) {}
    _highlights
      ..clear()
      ..addAll(nextHighlights);
  }

  Future<void> _persistBookmarks({Map<int, int>? from}) async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final source = from ?? _bookmarks;
      final list = source.entries
          .map((e) => <String, Object?>{'i': e.key, 't': e.value})
          .toList(growable: false);
      await prefs.setString(_bookmarksKey(), jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _persistHighlights() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final list = _highlights.map((m) => m.toJson()).toList(growable: false);
      await prefs.setString(_highlightsKey(), jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _addHighlightFromSelection() async {
    final t = _lastSelectionText.trim();
    if (t.isEmpty) return;
    final unitCount = _layoutDirection == _ReaderLayoutDirection.vertical
        ? _allChunks.length
        : _pages.length;
    if (unitCount <= 0) return;

    final here = _anchorIndex.clamp(0, unitCount - 1);
    final now = DateTime.now().millisecondsSinceEpoch;
    final excerpt = t.length > 120 ? '${t.substring(0, 120)}…' : t;

    // De-dup: same excerpt in same unit.
    for (final m in _highlights) {
      if (m.unitIndex == here && m.excerpt == excerpt) {
        _toast('已存在该高亮');
        return;
      }
    }

    setState(() {
      _highlights.insert(
        0,
        _HighlightMark(unitIndex: here, createdAtMs: now, excerpt: excerpt),
      );
    });
    await _persistHighlights();
    _toast('已添加高亮标记');
  }

  void _rebuildUnitsAndRestoreProgress() {
    if (_bookText.isEmpty) {
      setState(() => _allChunks = const []);
      return;
    }

    final chunks = _splitIntoChunks(_bookText, _chunkSizeChars);

    if (_layoutDirection == _ReaderLayoutDirection.vertical) {
      _paginationKey = '';
      setState(() {
        _allChunks = chunks;
        _displayText = '';
        _chunkDisplayStarts = const [];
        _pages = const [];
        _horizontalTextHeight = 0;
        _pendingChunkLoads.clear();
        _pendingAllowNetwork.clear();
        _postFrameLoadScheduled = false;
      });

      // Critical: ensure chunk 0 gets a cache-check + translation attempt.
      _requestChunkLoad(0, allowNetwork: true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final saved = (_prefs?.getInt(_progressKey()) ?? 0);
        final clamped = _allChunks.isEmpty
            ? 0
            : saved.clamp(0, _allChunks.length - 1);
        _anchorIndex = clamped;
        if (_unitIndex.value != clamped) {
          _unitIndex.value = clamped;
        }
        if (clamped <= 0) return;
        if (_itemScrollController.isAttached) {
          _itemScrollController.jumpTo(index: clamped);
          _requestChunkLoad(clamped, allowNetwork: true);
        }
      });
      return;
    }

    final composed = _composeDisplayText(chunksOverride: chunks);
    final paginated = _paginateForHorizontal(context, composed.displayText);

    setState(() {
      _allChunks = chunks;
      _displayText = composed.displayText;
      _chunkDisplayStarts = composed.chunkStarts;
      _pages = paginated.pages;
      _horizontalTextHeight = paginated.textHeight;
      _pendingChunkLoads.clear();
      _pendingAllowNetwork.clear();
      _postFrameLoadScheduled = false;
    });

    // Critical: ensure chunk 0 gets a cache-check + translation attempt.
    _requestChunkLoad(0, allowNetwork: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final saved = (_prefs?.getInt(_progressKey()) ?? 0);
      final clamped = _pages.isEmpty ? 0 : saved.clamp(0, _pages.length - 1);
      if (clamped <= 0) return;
      try {
        _pageController.jumpToPage(clamped);
      } catch (_) {}
      _anchorIndex = clamped;
      if (_unitIndex.value != clamped) {
        _unitIndex.value = clamped;
      }
      _requestChunksForPage(clamped, allowNetwork: true);
      _requestChunksForPage(clamped + 1, allowNetwork: true);
    });
  }

  String _fnvCacheKey(String prefix, String input) {
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '${prefix}_$hash';
  }

  Directory _cacheDirForBook() {
    final base = _tmpDir ?? Directory.systemTemp;
    return Directory(
      // Cache is content-based (chunk + level), not layout-based. Keep it stable
      // across pagination/chrome toggles to avoid re-downloading translations.
      '${base.path}${Platform.pathSeparator}lens_cache${Platform.pathSeparator}$_bookCacheKey${Platform.pathSeparator}chunks',
    );
  }

  String? _readCacheSyncFor(int index, String levelLabel) {
    if (index < 0 || index >= _allChunks.length) return null;
    return ReaderTranslationCache(directory: _cacheDirForBook()).read(
      index: index,
      levelLabel: levelLabel,
      mode: _mode,
      raw: _allChunks[index],
    );
  }

  String _chunkFrozenLevelKey(int index, {TranslationMode? mode}) {
    return 'chunk_level_${_bookId}_${ReaderTranslationCache.modeID(mode ?? _mode)}_$index';
  }

  ({String cacheText, String levelLabel})? _readBestCacheSync(int index) {
    final prefs = _prefs;
    final tried = <String>{};

    final frozen = prefs?.getString(_chunkFrozenLevelKey(index));
    if (frozen != null && frozen.isNotEmpty) {
      tried.add(frozen);
      final c = _readCacheSyncFor(index, frozen);
      if (c != null) return (cacheText: c, levelLabel: frozen);
    }

    final current = _currentLevel.label;
    if (!tried.contains(current)) {
      tried.add(current);
      final c = _readCacheSyncFor(index, current);
      if (c != null) return (cacheText: c, levelLabel: current);
    }

    for (final level in VocabularyLevel.values) {
      final label = level.label;
      if (tried.contains(label)) continue;
      tried.add(label);
      final c = _readCacheSyncFor(index, label);
      if (c != null) return (cacheText: c, levelLabel: label);
    }

    return null;
  }

  void _requestChunkLoad(int index, {required bool allowNetwork}) {
    if (index < 0 || index >= _allChunks.length) return;
    _pendingChunkLoads.add(index);
    final prev = _pendingAllowNetwork[index] ?? false;
    _pendingAllowNetwork[index] = prev || allowNetwork;

    if (_postFrameLoadScheduled) return;
    _postFrameLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameLoadScheduled = false;
      if (!mounted) return;
      _processPendingChunkLoads();
    });
  }

  void _processPendingChunkLoads() {
    if (_pendingChunkLoads.isEmpty) return;
    final indices = _pendingChunkLoads.toList()..sort();
    _pendingChunkLoads.clear();
    for (final i in indices) {
      final allowNetwork = _pendingAllowNetwork.remove(i) ?? false;
      _ensureChunkLoaded(i, preferCache: true, allowNetwork: allowNetwork);
    }
  }

  void _ensureChunkLoaded(
    int index, {
    required bool preferCache,
    required bool allowNetwork,
  }) {
    if (index < 0 || index >= _allChunks.length) return;
    if (_rendered.containsKey(index)) return;
    if (_inFlight.contains(index)) return;
    if (_failedChunks.contains(index)) return;

    final raw = _allChunks[index];

    // Critical: cache must be checked first, synchronously.
    if (preferCache) {
      final cached = _readBestCacheSync(index);
      if (cached != null) {
        final render = _renderFromCacheOrRaw(raw, cached.cacheText);
        final prevEffective = _rendered[index]?.text ?? raw;
        final sourceAnchor = _readingSourceAnchor();
        // Freeze this chunk to the cached level so later level switches won't
        // trigger re-translation.
        final prefs = _prefs;
        if (prefs != null) {
          unawaited(
            prefs.setString(_chunkFrozenLevelKey(index), cached.levelLabel),
          );
        }
        setState(() {
          _rendered[index] = render;
        });
        if (_layoutDirection == _ReaderLayoutDirection.horizontal &&
            prevEffective != render.text) {
          _scheduleHorizontalRepagination(anchor: sourceAnchor);
        }
        return;
      }
    }

    // If no cache and network disallowed, do nothing. The UI will show raw
    // text as a fallback, and a later prefetch can still translate it.
    if (!allowNetwork) {
      return;
    }

    final level = _currentLevel;
    final mode = _mode;
    setState(() {
      _inFlight.add(index);
      _translatingCount += 1;
    });
    unawaited(
      _translateAndCache(
        index,
        raw,
        level: level,
        mode: mode,
        generation: _translationGeneration,
      ),
    );
  }

  _ChunkRender _renderFromCacheOrRaw(String raw, String cacheText) {
    try {
      final decoded = jsonDecode(cacheText);
      if (decoded is! Map) {
        return _ChunkRender(text: raw, accentColor: const Color(0xFF999999));
      }
      final levelLabel = decoded['level'];
      final mode = decoded['mode'];
      if (mode != ReaderTranslationCache.modeID(_mode)) {
        return _ChunkRender(text: raw, accentColor: LingferColors.accent);
      }
      final data = decoded['data'];
      if (data is! Map) {
        return _ChunkRender(
          text: raw,
          accentColor: getLevelColor((levelLabel is String) ? levelLabel : ''),
        );
      }
      final vocab = <String, String>{};
      data.forEach((k, v) {
        if (k is String && v is String) vocab[k] = v;
      });
      final annotations = <ReaderAnnotationSpan>[];
      final replaced = vocab.isEmpty
          ? raw
          : AiTranslationService.applyVocabReplacements(
              raw,
              vocab,
              mode: _mode,
              onAnnotation: (sourceOffset, renderedStart, renderedEnd) {
                annotations.add(
                  ReaderAnnotationSpan(
                    sourceOffset: sourceOffset,
                    renderedStart: renderedStart,
                    renderedEnd: renderedEnd,
                  ),
                );
              },
            );
      return _ChunkRender(
        text: replaced,
        annotations: annotations,
        accentColor: getLevelColor((levelLabel is String) ? levelLabel : ''),
      );
    } catch (_) {
      return _ChunkRender(text: raw, accentColor: const Color(0xFF999999));
    }
  }

  Future<void> _translateAndCache(
    int index,
    String raw, {
    required VocabularyLevel level,
    required TranslationMode mode,
    required int generation,
  }) async {
    var render = _ChunkRender(text: raw, accentColor: const Color(0xFF999999));
    var succeeded = false;
    try {
      final service =
          widget.translationService ??
          AiTranslationService(
            proxyUrl: _deepSeekProxyUrl,
            appSecret: _appSecret,
          );
      final vocabJson = await service.fetchVocabJson(
        raw: raw,
        level: level,
        mode: mode,
      );
      if (vocabJson == null) return;

      final cache = ReaderTranslationCache(directory: _cacheDirForBook());
      final written = await cache.write(
        index: index,
        levelLabel: level.label,
        mode: mode,
        raw: raw,
        vocabJson: vocabJson,
      );
      if (!written) return;
      final prefs = _prefs;
      if (prefs != null) {
        unawaited(
          prefs.setString(_chunkFrozenLevelKey(index, mode: mode), level.label),
        );
      }

      // Must render from cache content, not from network response, to guarantee
      // consistency with the persisted format.
      if (generation != _translationGeneration || mode != _mode) return;
      final cached = cache.read(
        index: index,
        levelLabel: level.label,
        mode: mode,
        raw: raw,
      );
      if (cached != null) {
        render = _renderFromCacheOrRaw(raw, cached);
        succeeded = true;
      }
    } catch (error, stackTrace) {
      debugPrint('[ai] translate error=$error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted && generation == _translationGeneration && mode == _mode) {
        final prevEffective = _rendered[index]?.text ?? raw;
        final sourceAnchor = _readingSourceAnchor();
        setState(() {
          _inFlight.remove(index);
          if (_translatingCount > 0) _translatingCount -= 1;
          if (succeeded) {
            _rendered[index] = render;
            _failedChunks.remove(index);
          } else {
            _failedChunks.add(index);
          }
        });
        if (_layoutDirection == _ReaderLayoutDirection.horizontal &&
            prevEffective != render.text) {
          _scheduleHorizontalRepagination(anchor: sourceAnchor);
        }
      }
    }
  }

  void _onPositionsChanged() {
    if (_layoutDirection != _ReaderLayoutDirection.vertical) return;
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final visible = positions.where((p) => p.itemTrailingEdge > 0).toList();
    if (visible.isEmpty) return;
    visible.sort((a, b) => a.index.compareTo(b.index));
    final topIndex = visible.first.index;
    final bottomIndex = visible.last.index;
    _anchorIndex = topIndex;
    if (_unitIndex.value != topIndex) {
      _unitIndex.value = topIndex;
    }

    // Save progress by topChunkIndex.
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        await _prefs?.setInt(_progressKey(), topIndex);
      } catch (_) {}
    });

    // Prefetch: keep one chunk ahead translated (cache-first).
    // Also ensure the newest visible chunk gets a translation attempt.
    if (bottomIndex >= 0 && bottomIndex < _allChunks.length) {
      _requestChunkLoad(bottomIndex, allowNetwork: true);
    }
    final next = bottomIndex + 1;
    if (next >= 0 && next < _allChunks.length) {
      _requestChunkLoad(next, allowNetwork: true);
    }
  }

  Future<void> _showLevelPicker() async {
    final selected = await showBookReaderChoices<VocabularyLevel>(
      context,
      title: '学习范围',
      selected: _currentLevel,
      isDark: _theme.background.computeLuminance() < 0.5,
      choices: [
        for (final level in VocabularyLevel.values)
          BookReaderChoice(value: level, label: level.label),
      ],
    );
    if (selected != null && mounted) _setLevel(selected);
  }

  Future<void> _showModePicker() async {
    final selected = await showBookReaderChoices<TranslationMode>(
      context,
      title: '翻译方向',
      selected: _mode,
      isDark: _theme.background.computeLuminance() < 0.5,
      choices: [
        for (final mode in TranslationMode.values)
          BookReaderChoice(value: mode, label: mode.label),
      ],
    );
    if (selected != null && mounted) _setMode(selected);
  }

  void _setMode(TranslationMode next) {
    if (next == _mode) return;
    final sourceAnchor = _readingSourceAnchor();
    setState(() {
      _mode = next;
      _translationGeneration += 1;
      _rendered.clear();
      _inFlight.clear();
      _failedChunks.clear();
      _translatingCount = 0;
      _pendingChunkLoads.clear();
      _pendingAllowNetwork.clear();
    });
    if (_layoutDirection == _ReaderLayoutDirection.horizontal) {
      _recomputeHorizontalPagination(
        keepPageIndex: _anchorIndex,
        sourceAnchor: sourceAnchor,
      );
    } else {
      _requestChunkLoad(_anchorIndex, allowNetwork: true);
      _requestChunkLoad(_anchorIndex + 1, allowNetwork: true);
    }
  }

  void _retryFailedTranslations() {
    final retry = _failedChunks.toList();
    setState(_failedChunks.clear);
    for (final index in retry) {
      _requestChunkLoad(index, allowNetwork: true);
    }
  }

  Widget _buildSelectionContextMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final items = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        label: '复制',
        onPressed: () {
          final t = _lastSelectionText.trim();
          if (t.isNotEmpty) {
            unawaited(Clipboard.setData(ClipboardData(text: t)));
            _toast('已复制');
          }
          // Keep selection handles so the user can adjust boundaries.
          selectableRegionState.hideToolbar(false);
        },
      ),
      ContextMenuButtonItem(
        label: '高亮',
        onPressed: () {
          selectableRegionState.hideToolbar(false);
          unawaited(_addHighlightFromSelection());
        },
      ),
    ];

    return material.AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  void _jumpToUnit(int unitIndex) {
    final unitCount = _layoutDirection == _ReaderLayoutDirection.vertical
        ? _allChunks.length
        : _pages.length;
    if (unitCount <= 0) return;
    final target = unitIndex.clamp(0, unitCount - 1);

    _anchorIndex = target;
    if (_unitIndex.value != target) {
      _unitIndex.value = target;
    }

    if (_layoutDirection == _ReaderLayoutDirection.vertical) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_itemScrollController.isAttached) {
          _itemScrollController.jumpTo(index: target);
          _requestChunkLoad(target, allowNetwork: true);
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _pageController.jumpToPage(target);
        } catch (_) {}
        _requestChunksForPage(target, allowNetwork: true);
        _requestChunksForPage(target + 1, allowNetwork: true);
      });
    }

    // Save progress with debounce.
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        await _prefs?.setInt(_progressKey(), target);
      } catch (_) {}
    });
  }

  Future<void> _showDirectorySheet({required int unitCount}) async {
    if (!mounted || unitCount <= 0) return;
    setState(() => _chromeVisible = false);

    final title = _book.displayTitle.trim().isEmpty
        ? '目录'
        : _book.displayTitle.trim();
    final here = _anchorIndex.clamp(0, math.max(0, unitCount - 1));
    final currentChapter = (here / _pagesPerChapter).floor();
    final chapterCount = (unitCount / _pagesPerChapter).ceil();

    await showCupertinoModalPopup<void>(
      context: context,
      barrierColor: CupertinoColors.black.withValues(alpha: 0.30),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final sheetH = (mq.size.height * 0.82).clamp(420.0, mq.size.height);
        return material.Material(
          type: material.MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: Container(
                      height: sheetH,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: CupertinoColors.white.withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0x14000000)),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          _SheetTopBar(
                            title: title,
                            onClose: () => Navigator.of(ctx).pop(),
                            onDone: () => Navigator.of(ctx).pop(),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              itemCount: chapterCount,
                              itemBuilder: (context, i) {
                                final start = i * _pagesPerChapter;
                                final end = math.min(
                                  unitCount,
                                  start + _pagesPerChapter,
                                );
                                final selected = i == currentChapter;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            _jumpToUnit(start);
                                          });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        14,
                                        16,
                                        14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? CupertinoColors.white.withValues(
                                                alpha: 0.92,
                                              )
                                            : LingferColors.background,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: selected
                                              ? const Color(0x22000000)
                                              : const Color(0x11000000),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '第${i + 1}章',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: LingferColors.ink,
                                                    decoration:
                                                        TextDecoration.none,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '第${start + 1}-$end页',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: LingferColors.muted,
                                                    decoration:
                                                        TextDecoration.none,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '${start + 1}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: LingferColors.muted,
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMarksSheet({required int unitCount}) async {
    if (!mounted || unitCount <= 0) return;
    setState(() => _chromeVisible = false);
    final title = _book.displayTitle.trim().isEmpty
        ? '书签与高亮标记'
        : _book.displayTitle.trim();

    await showCupertinoModalPopup<void>(
      context: context,
      barrierColor: CupertinoColors.black.withValues(alpha: 0.30),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final sheetH = (mq.size.height * 0.82).clamp(420.0, mq.size.height);
        return material.Material(
          type: material.MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: Container(
                      height: sheetH,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: CupertinoColors.white.withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0x14000000)),
                      ),
                      child: _MarksSheet(
                        title: title,
                        bookmarks: Map<int, int>.from(_bookmarks),
                        highlights: List<_HighlightMark>.from(_highlights),
                        pagesPerChapter: _pagesPerChapter,
                        onClose: () => Navigator.of(ctx).pop(),
                        onJump: (index) {
                          Navigator.of(ctx).pop();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _jumpToUnit(index);
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _setLevel(VocabularyLevel level) async {
    if (level == _currentLevel) return;
    final oldId = _bookId;
    final nextBook = _book.withDefaultLevel(level);

    setState(() {
      _currentLevel = level;
      _book = nextBook;
      _bookId = nextBook.stableKey;
    });

    try {
      final appState = AppScope.of(context);
      await appState.replaceBook(oldId: oldId, newBook: nextBook);
    } catch (_) {}
  }

  Future<void> _setLayoutDirection(_ReaderLayoutDirection next) async {
    if (next == _layoutDirection) return;
    setState(() {
      _layoutDirection = next;
      _loadMarksFromPrefs();
    });
    try {
      await _prefs?.setString(_layoutPrefsKey, next.toPrefs());
    } catch (_) {}
    // Rebuild units so the rendering model matches the layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rebuildUnitsAndRestoreProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = _theme.background;
    final ink = _theme.textColor;

    Widget shell({required Widget content, String? overlayMessage}) {
      return material.Scaffold(
        backgroundColor: bg,
        body: material.Material(
          color: bg,
          child: CupertinoPageScaffold(
            backgroundColor: bg,
            child: Stack(
              children: [
                content,
                if (overlayMessage != null) ...[
                  const Positioned.fill(
                    child: IgnorePointer(child: _FrostedOverlay()),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: _CenterLoading(message: overlayMessage, ink: ink),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (_loadError != null) {
      return shell(
        content: BookReadFailureView(
          title: _book.displayTitle,
          message: _loadError!,
          isDark: bg.computeLuminance() < 0.5,
          onBack: () => Navigator.of(context).maybePop(),
          onRetry: _initBook,
        ),
      );
    }

    final hasUnits = _layoutDirection == _ReaderLayoutDirection.vertical
        ? _allChunks.isNotEmpty
        : _pages.isNotEmpty;
    if (_initializing || !hasUnits) {
      final message = _initializing
          ? '正在载入书籍...'
          : (_bookText.trim().isEmpty ? '空文件' : '正在排版...');
      return shell(
        overlayMessage: message,
        content: DecoratedBox(
          decoration: BoxDecoration(color: bg),
          child: const SizedBox.expand(),
        ),
      );
    }

    final unitCount = _layoutDirection == _ReaderLayoutDirection.vertical
        ? _allChunks.length
        : _pages.length;
    final clampedUnitIndex = unitCount <= 0
        ? 0
        : _anchorIndex.clamp(0, unitCount - 1);
    final pageLabel = unitCount <= 0
        ? ''
        : '${clampedUnitIndex + 1}/$unitCount 页';
    final progressPercent = unitCount <= 0
        ? 0
        : (((clampedUnitIndex + 1) / unitCount) * 100).round().clamp(0, 100);
    final isDark =
        material.ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;

    return shell(
      content: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: bg),
            child: material.SelectionArea(
              selectionControls: liquidCupertinoTextSelectionControls,
              contextMenuBuilder: _buildSelectionContextMenu,
              onSelectionChanged: _onSelectionChanged,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) => _lastPointerDownGlobal = e.position,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (d) => _toggleChromeIfCenterTap(d.globalPosition),
                  child: _layoutDirection == _ReaderLayoutDirection.vertical
                      ? ScrollablePositionedList.builder(
                          itemScrollController: _itemScrollController,
                          itemPositionsListener: _positionsListener,
                          padding: EdgeInsets.fromLTRB(
                            26,
                            _topPadding(context),
                            26,
                            _bottomPadding(context),
                          ),
                          itemCount: _allChunks.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _allChunks.length) {
                              final translating = _inFlight.isNotEmpty;
                              return translating
                                  ? _FooterLoading(ink: ink)
                                  : const SizedBox(height: 60);
                            }

                            // Never trigger any setState while list items are building.
                            // Cache checks / load attempts are deferred post-frame.
                            _requestChunkLoad(index, allowNetwork: false);

                            final raw = _allChunks[index];
                            final render = _rendered[index];
                            final text = render?.text ?? raw;
                            final accentColor =
                                render?.accentColor ?? const Color(0xFF999999);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: ReadingText(
                                chunkText: text,
                                annotations: render?.annotations ?? const [],
                                accentColor: accentColor,
                                fontSize: _fontSize,
                                baseColor: ink,
                              ),
                            );
                          },
                        )
                      : Padding(
                          padding: EdgeInsets.fromLTRB(
                            26,
                            _topPadding(context),
                            26,
                            _bottomPadding(context),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final pageHeight = constraints.maxHeight;
                              // Pixel-level: textHeight is computed by pagination as an
                              // integer multiple of the exact line height. Do not clamp
                              // it to avoid reintroducing "half line" clipping.
                              final textHeight = (_horizontalTextHeight > 0)
                                  ? _horizontalTextHeight
                                  : pageHeight;

                              return PageView.builder(
                                controller: _pageController,
                                onPageChanged: (index) async {
                                  _anchorIndex = index;
                                  if (_unitIndex.value != index) {
                                    _unitIndex.value = index;
                                  }
                                  try {
                                    await _prefs?.setInt(_progressKey(), index);
                                  } catch (_) {}
                                  _requestChunksForPage(
                                    index,
                                    allowNetwork: true,
                                  );
                                  _requestChunksForPage(
                                    index + 1,
                                    allowNetwork: true,
                                  );
                                },
                                itemCount: _pages.length,
                                itemBuilder: (context, index) {
                                  _requestChunksForPage(
                                    index,
                                    allowNetwork: false,
                                  );
                                  final pageText = _buildHorizontalPageText(
                                    _pages[index],
                                    ink,
                                  );
                                  return SizedBox(
                                    height: pageHeight,
                                    child: Stack(
                                      clipBehavior: Clip.hardEdge,
                                      children: [
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          right: 0,
                                          height: textHeight,
                                          child: ClipRect(child: pageText),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                ),
              ),
            ),
          ),
          if (!_chromeVisible)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: _persistentHudTop,
                    child: Center(
                      child: Text(
                        _book.displayTitle.trim().isEmpty
                            ? '阅读'
                            : _book.displayTitle.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                          color: isDark
                              ? const Color(0xB3FFFFFF)
                              : LingferColors.muted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!_chromeVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: _persistentHudBottom,
                    child: Center(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _unitIndex,
                        builder: (context, idx, _) {
                          if (unitCount <= 0) return const SizedBox.shrink();
                          final clamped = idx.clamp(
                            0,
                            math.max(0, unitCount - 1),
                          );
                          return Text(
                            '${clamped + 1}/$unitCount 页',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xB3FFFFFF)
                                  : LingferColors.muted,
                              decoration: TextDecoration.none,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_chromeVisible && !_glassVisible && !_settingsVisible)
            Positioned.fill(
              child: _AppleBooksChromeOverlay(
                title: _book.displayTitle,
                pageLabel: pageLabel,
                isDark: isDark,
                currentLevel: _currentLevel,
                mode: _mode,
                directoryLabel: '目录 · $progressPercent%',
                marksCount: _bookmarks.length + _highlights.length,
                hasBookmark:
                    unitCount > 0 &&
                    _bookmarks.containsKey(
                      clampedUnitIndex.clamp(0, math.max(0, unitCount - 1)),
                    ),
                onBack: () => Navigator.of(context).maybePop(),
                onDismiss: () => setState(() => _chromeVisible = false),
                onOpenDirectory: () =>
                    _showDirectorySheet(unitCount: unitCount),
                onOpenMarks: () => _showMarksSheet(unitCount: unitCount),
                onPickLevel: _showLevelPicker,
                onPickMode: _showModePicker,
                onToggleBookmark: _toggleBookmark,
                onOpenSettings: () => setState(() {
                  _chromeVisible = false;
                  _settingsVisible = true;
                }),
              ),
            ),
          _ReaderSettingsSheet(
            visible: _settingsVisible,
            isDark: isDark,
            theme: _theme,
            fontSize: _fontSize,
            layoutDirection: _layoutDirection,
            onClose: () => setState(() => _settingsVisible = false),
            onThemeChanged: (t) => _setTheme(t),
            onFontSizeChanged: (v) => _setFontSize(v),
            onLayoutDirectionChanged: _setLayoutDirection,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              left: false,
              child: Padding(
                padding: const EdgeInsets.only(right: 20, bottom: 40),
                child: IgnorePointer(
                  ignoring:
                      _failedChunks.isEmpty ||
                      _chromeVisible ||
                      _settingsVisible ||
                      _glassVisible,
                  child: GestureDetector(
                    onTap: _retryFailedTranslations,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity:
                          (_translatingCount > 0 || _failedChunks.isNotEmpty) &&
                              !_chromeVisible &&
                              !_settingsVisible &&
                              !_glassVisible
                          ? 1.0
                          : 0.0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: CupertinoColors.white.withValues(
                                alpha: 0.72,
                              ),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: const Color(0x11000000),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_translatingCount > 0)
                                  const CupertinoActivityIndicator(radius: 8)
                                else
                                  const Icon(
                                    CupertinoIcons.refresh,
                                    size: 15,
                                    color: LingferColors.accent,
                                  ),
                                const SizedBox(width: 8),
                                Text(
                                  _translatingCount > 0
                                      ? '正在生成注释…'
                                      : '注释暂未生成 · 点此重试',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: LingferColors.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_glassVisible)
            Positioned.fill(
              child: AppleGlassPanel(
                selectedTextListenable: _glassSelectedText,
                dock: _glassDock,
                initialLevel: _currentLevel,
                ai: _aiGlass,
                onDismiss: () => setState(() => _glassVisible = false),
              ),
            ),
        ],
      ),
    );
  }

  double _topPadding(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return topInset + _persistentHudTop;
  }

  double _bottomPadding(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return _persistentHudBottom + bottomInset;
  }

  void _toggleChromeIfCenterTap(Offset global) {
    if (_glassVisible) return;
    final size = MediaQuery.sizeOf(context);
    final localY = global.dy;
    final localX = global.dx;
    if (localX < size.width * 0.2 ||
        localX > size.width * 0.8 ||
        localY < size.height * 0.25 ||
        localY > size.height * 0.75) {
      return;
    }
    if (_settingsVisible) {
      setState(() => _settingsVisible = false);
      return;
    }
    setState(() => _chromeVisible = !_chromeVisible);
  }

  void _toast(String message) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final mq = MediaQuery.of(context);
        return Positioned(
          left: 0,
          right: 0,
          bottom: 86 + mq.padding.bottom,
          child: IgnorePointer(
            child: Center(
              child: material.Material(
                type: material.MaterialType.transparency,
                child: DefaultTextStyle(
                  style: const TextStyle(
                    decoration: TextDecoration.none,
                    fontFamily: '.SF UI Text',
                    color: LingferColors.ink,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey6.withValues(
                            alpha: 0.86,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x1A000000)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 24,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Text(
                          message,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                            color: LingferColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      try {
        entry.remove();
      } catch (_) {}
    });
  }

  String _currentUnitTextForShare() {
    if (_layoutDirection == _ReaderLayoutDirection.horizontal) {
      if (_pages.isEmpty || _displayText.isEmpty) return '';
      final idx = _anchorIndex.clamp(0, _pages.length - 1);
      final slice = _pages[idx];
      final start = slice.start.clamp(0, _displayText.length);
      final end = slice.end.clamp(start, _displayText.length);
      return _displayText.substring(start, end).trim();
    }

    if (_allChunks.isEmpty) return '';
    final idx = _anchorIndex.clamp(0, _allChunks.length - 1);
    return (_rendered[idx]?.text ?? _allChunks[idx]).trim();
  }

  Future<void> _shareCurrentUnit() async {
    final text = _currentUnitTextForShare();
    if (text.trim().isEmpty) {
      _toast('暂无可分享内容');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: text));
      _toast('已复制到剪贴板，可粘贴分享');
    } catch (_) {
      _toast('复制失败');
    }
  }

  Future<void> _applyRotationLock(bool locked) async {
    try {
      if (!locked) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        return;
      }
      final orientation = MediaQuery.orientationOf(context);
      if (orientation == Orientation.landscape) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      }
    } catch (_) {}
  }

  Future<void> _toggleRotationLock() async {
    final next = !_rotationLocked;
    setState(() => _rotationLocked = next);
    try {
      await _prefs?.setBool('reader_rotation_locked', next);
    } catch (_) {}
    await _applyRotationLock(next);
    _toast(next ? '已锁定旋转' : '已解锁旋转');
  }

  Future<void> _toggleBookmark() async {
    final unitCount = _layoutDirection == _ReaderLayoutDirection.vertical
        ? _allChunks.length
        : _pages.length;
    if (unitCount <= 0) return;
    final here = _anchorIndex.clamp(0, unitCount - 1);
    final removing = _bookmarks.containsKey(here);
    setState(() {
      if (removing) {
        _bookmarks.remove(here);
      } else {
        _bookmarks[here] = DateTime.now().millisecondsSinceEpoch;
      }
    });
    await _persistBookmarks();
    _toast(removing ? '已移除书签' : '已添加书签');
  }

  Future<void> _setFontSize(double v) async {
    final next = v.clamp(14, 26).toDouble();
    setState(() => _fontSize = next);
    try {
      await _prefs?.setDouble('reader_font_size', next);
    } catch (_) {}

    // Horizontal pagination depends on font size.
    if (_layoutDirection == _ReaderLayoutDirection.horizontal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _rebuildUnitsAndRestoreProgress();
      });
    }
  }

  Future<void> _setTheme(ReaderTheme t) async {
    setState(() => _theme = t);
    try {
      await _prefs?.setString('reader_theme', t.toPrefs());
    } catch (_) {}
  }
}

class _AppleBooksChromeOverlay extends StatelessWidget {
  const _AppleBooksChromeOverlay({
    required this.title,
    required this.pageLabel,
    required this.isDark,
    required this.currentLevel,
    required this.mode,
    required this.directoryLabel,
    required this.marksCount,
    required this.hasBookmark,
    required this.onBack,
    required this.onDismiss,
    required this.onOpenDirectory,
    required this.onOpenMarks,
    required this.onPickLevel,
    required this.onPickMode,
    required this.onToggleBookmark,
    required this.onOpenSettings,
  });

  final String title;
  final String pageLabel;
  final bool isDark;
  final VocabularyLevel currentLevel;
  final TranslationMode mode;
  final String directoryLabel;
  final int marksCount;
  final bool hasBookmark;
  final VoidCallback onBack;
  final VoidCallback onDismiss;
  final VoidCallback onOpenDirectory;
  final VoidCallback onOpenMarks;
  final VoidCallback onPickLevel;
  final VoidCallback onPickMode;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final fg = isDark ? const Color(0xFFF4F4F0) : LingferColors.ink;
    final sub = isDark ? const Color(0xFFB2BCBD) : LingferColors.muted;
    final panelBg = isDark
        ? const Color(0xED252D2F)
        : CupertinoColors.white.withValues(alpha: 0.86);
    final panelBorder = isDark ? const Color(0xFF465254) : LingferColors.line;
    final iconBg = isDark ? const Color(0xFF344347) : LingferColors.tint;
    final scale = mq.textScaler.scale(14) / 14;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                _GlassCircleButton(
                  icon: CupertinoIcons.chevron_left,
                  foreground: fg,
                  background: panelBg,
                  border: panelBorder,
                  onPressed: onBack,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      title.trim().isEmpty ? '阅读' : title.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: sub,
                      ),
                    ),
                  ),
                ),
                _GlassCircleButton(
                  icon: CupertinoIcons.xmark,
                  foreground: fg,
                  background: panelBg,
                  border: panelBorder,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 54 + mq.padding.bottom,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 580,
                maxHeight: mq.size.height * 0.64,
              ),
              child: BookReaderControlSurface(
                isDark: isDark,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '阅读工具',
                        style: LingferType.interfaceHeading.copyWith(
                          fontSize: 18,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              constraints.maxWidth < 390 || scale > 1.3 ? 1 : 2;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 10) /
                              columns;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: width,
                                child: _ChromePillButton(
                                  icon: CupertinoIcons.list_bullet,
                                  label: directoryLabel,
                                  foreground: fg,
                                  iconBackground: iconBg,
                                  iconBorder: panelBorder,
                                  onPressed: onOpenDirectory,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _ChromePillButton(
                                  icon: CupertinoIcons.bookmark,
                                  label: '书签与高亮',
                                  trailing: marksCount > 0
                                      ? '$marksCount'
                                      : null,
                                  foreground: fg,
                                  iconBackground: iconBg,
                                  iconBorder: panelBorder,
                                  onPressed: onOpenMarks,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(height: 1, color: panelBorder),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              constraints.maxWidth < 320 || scale > 1.3 ? 1 : 2;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 8) /
                              columns;
                          final actions = [
                            BookReaderActionChip(
                              icon: CupertinoIcons.slider_horizontal_3,
                              label: currentLevel.label,
                              isDark: isDark,
                              onPressed: onPickLevel,
                            ),
                            BookReaderActionChip(
                              icon: CupertinoIcons.arrow_right_arrow_left,
                              label: mode.label,
                              isDark: isDark,
                              onPressed: onPickMode,
                            ),
                            BookReaderActionChip(
                              icon: hasBookmark
                                  ? CupertinoIcons.bookmark_fill
                                  : CupertinoIcons.bookmark,
                              label: hasBookmark ? '已加书签' : '添加书签',
                              isDark: isDark,
                              active: hasBookmark,
                              onPressed: onToggleBookmark,
                            ),
                            BookReaderActionChip(
                              icon: CupertinoIcons.textformat_size,
                              label: '字号与外观',
                              isDark: isDark,
                              onPressed: onOpenSettings,
                            ),
                          ];
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final action in actions)
                                SizedBox(width: width, child: action),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (pageLabel.trim().isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16 + mq.padding.bottom,
            child: IgnorePointer(
              child: Center(
                child: Text(
                  pageLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: sub,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChromePillButton extends StatelessWidget {
  const _ChromePillButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.iconBackground,
    required this.iconBorder,
    required this.onPressed,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final Color foreground;
  final Color iconBackground;
  final Color iconBorder;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final sub = foreground.withValues(alpha: 0.82);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: iconBackground.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: iconBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconBackground,
                border: Border.all(color: iconBorder),
              ),
              child: Icon(icon, size: 16, color: sub),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                  color: foreground,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            if ((trailing ?? '').trim().isNotEmpty) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x12000000),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: sub,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.foreground,
    required this.background,
    required this.border,
    required this.onPressed,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  final Color border;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Icon(icon, size: 18, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _HighlightMark {
  const _HighlightMark({
    required this.unitIndex,
    required this.createdAtMs,
    required this.excerpt,
  });

  final int unitIndex;
  final int createdAtMs;
  final String excerpt;

  Map<String, Object?> toJson() => <String, Object?>{
    'i': unitIndex,
    't': createdAtMs,
    'x': excerpt,
  };

  static _HighlightMark? fromJson(Map raw) {
    final i = raw['i'];
    final t = raw['t'];
    final x = raw['x'];
    if (i is! int || x is! String) return null;
    return _HighlightMark(
      unitIndex: i,
      createdAtMs: (t is int) ? t : DateTime.now().millisecondsSinceEpoch,
      excerpt: x,
    );
  }
}

class _SheetTopBar extends StatelessWidget {
  const _SheetTopBar({
    required this.title,
    required this.onClose,
    required this.onDone,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback onDone;

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0x14000000),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x11000000)),
        ),
        child: Icon(icon, size: 18, color: LingferColors.ink),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Row(
        children: [
          _circleButton(icon: CupertinoIcons.xmark, onPressed: onClose),
          Expanded(
            child: Center(
              child: Text(
                title.trim().isEmpty ? '语渡' : title.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: LingferColors.ink,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          _circleButton(icon: CupertinoIcons.check_mark, onPressed: onDone),
        ],
      ),
    );
  }
}

class _MarksSheet extends StatefulWidget {
  const _MarksSheet({
    required this.title,
    required this.bookmarks,
    required this.highlights,
    required this.pagesPerChapter,
    required this.onClose,
    required this.onJump,
  });

  final String title;
  final Map<int, int> bookmarks; // unitIndex -> createdAtMs
  final List<_HighlightMark> highlights;
  final int pagesPerChapter;
  final VoidCallback onClose;
  final ValueChanged<int> onJump;

  @override
  State<_MarksSheet> createState() => _MarksSheetState();
}

class _MarksSheetState extends State<_MarksSheet> {
  static const int _segmentBookmarks = 0;
  static const int _segmentHighlights = 1;

  int _segment = _segmentBookmarks;

  String _dayLabel(int createdAtMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    if (sameDay) return '今天';
    return '${d.month}/${d.day}';
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: LingferColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x11000000)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = widget.bookmarks.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final highlights = widget.highlights.toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));

    return Column(
      children: [
        const SizedBox(height: 10),
        _SheetTopBar(
          title: widget.title,
          onClose: widget.onClose,
          onDone: widget.onClose,
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: CupertinoSlidingSegmentedControl<int>(
            groupValue: _segment,
            thumbColor: CupertinoColors.white.withValues(alpha: 0.92),
            backgroundColor: const Color(0x14000000),
            children: const {
              _segmentBookmarks: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  '书签',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: LingferColors.ink,
                    decoration: TextDecoration.none,
                    fontFamily: '.SF UI Text',
                  ),
                ),
              ),
              _segmentHighlights: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  '高亮标记',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: LingferColors.ink,
                    decoration: TextDecoration.none,
                    fontFamily: '.SF UI Text',
                  ),
                ),
              ),
            },
            onValueChanged: (v) {
              if (v == null) return;
              setState(() => _segment = v);
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Builder(
              builder: (context) {
                if (_segment == _segmentBookmarks) {
                  if (bookmarks.isEmpty) {
                    return const Center(
                      child: Text(
                        '暂无书签',
                        style: TextStyle(
                          fontSize: 14,
                          color: LingferColors.muted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: bookmarks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final unit = bookmarks[idx].key;
                      final createdAt = bookmarks[idx].value;
                      final chapter =
                          (unit / widget.pagesPerChapter).floor() + 1;
                      final day = _dayLabel(createdAt);
                      return CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => widget.onJump(unit),
                        child: _card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '第$chapter章',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: LingferColors.ink,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        day,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: LingferColors.muted,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${unit + 1}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: LingferColors.muted,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }

                if (highlights.isEmpty) {
                  return const Center(
                    child: Text(
                      '暂无高亮标记',
                      style: TextStyle(
                        fontSize: 14,
                        color: LingferColors.muted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: highlights.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final m = highlights[idx];
                    final chapter =
                        (m.unitIndex / widget.pagesPerChapter).floor() + 1;
                    final day = _dayLabel(m.createdAtMs);
                    return CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => widget.onJump(m.unitIndex),
                      child: _card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.excerpt,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        height: 1.25,
                                        color: LingferColors.ink,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '第$chapter章 · $day',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: LingferColors.muted,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${m.unitIndex + 1}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: LingferColors.muted,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ChunkRender {
  const _ChunkRender({
    required this.text,
    required this.accentColor,
    this.annotations = const [],
  });

  final String text;
  final Color accentColor;
  final List<ReaderAnnotationSpan> annotations;
}

typedef _ReaderAnchor = ({int chunk, int sourceOffset});

class _PageSlice {
  const _PageSlice(this.start, this.end);

  final int start;
  final int end;
}

class _FooterLoading extends StatelessWidget {
  const _FooterLoading({required this.ink});
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(),
            SizedBox(height: 10),
            Text(
              '正在补充下一段译文…',
              style: TextStyle(color: ink, fontSize: 14, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _LensScaffold extends StatelessWidget {
  const _LensScaffold({
    required this.title,
    required this.currentLevel,
    required this.mode,
    required this.onLevelPressed,
    required this.onModePressed,
    required this.chromeVisible,
    required this.child,
    this.overrideMessage,
  });

  final String title;
  final VocabularyLevel currentLevel;
  final TranslationMode mode;
  final VoidCallback onLevelPressed;
  final VoidCallback onModePressed;
  final bool chromeVisible;
  final Widget child;
  final String? overrideMessage;

  @override
  Widget build(BuildContext context) {
    const paper = Color(0xFFF4ECD8);

    // Critical: keep a Scaffold + Material context around reading text. This
    // avoids "yellow underline / red debug text" issues when widgets are built
    // without a Material ancestor on some platforms.
    return material.Scaffold(
      backgroundColor: material.Colors.white,
      body: material.Material(
        color: material.Colors.white,
        child: CupertinoPageScaffold(
          navigationBar: chromeVisible
              ? CupertinoNavigationBar(
                  backgroundColor: paper.withValues(alpha: 0.82),
                  border: null,
                  middle: Text(title),
                  leading: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('返回'),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: onModePressed,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: CupertinoColors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0x11000000)),
                          ),
                          child: Text(
                            mode.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: onLevelPressed,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: CupertinoColors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0x11000000)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(CupertinoIcons.sparkles, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                currentLevel.label,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 6),
                              const Icon(CupertinoIcons.chevron_down, size: 14),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          child: Stack(
            children: [
              child,
              if (overrideMessage != null) ...[
                const Positioned.fill(
                  child: IgnorePointer(child: _FrostedOverlay()),
                ),
                Positioned.fill(
                  child: Center(
                    child: _CenterLoading(message: overrideMessage!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _ReaderLayoutDirection {
  vertical,
  horizontal;

  String toPrefs() =>
      this == _ReaderLayoutDirection.horizontal ? 'horizontal' : 'vertical';
}

class _FrostedOverlay extends StatelessWidget {
  const _FrostedOverlay();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(color: const Color(0x33FFFFFF)),
      ),
    );
  }
}

class _CenterLoading extends StatelessWidget {
  const _CenterLoading({required this.message, this.ink = LingferColors.ink});
  final String message;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CupertinoActivityIndicator(),
        const SizedBox(height: 12),
        Text(message, style: TextStyle(color: ink, fontSize: 16, height: 1.4)),
      ],
    );
  }
}

class _ReaderSettingsSheet extends StatelessWidget {
  const _ReaderSettingsSheet({
    required this.visible,
    required this.isDark,
    required this.theme,
    required this.fontSize,
    required this.layoutDirection,
    required this.onClose,
    required this.onThemeChanged,
    required this.onFontSizeChanged,
    required this.onLayoutDirectionChanged,
  });

  final bool visible;
  final bool isDark;
  final ReaderTheme theme;
  final double fontSize;
  final _ReaderLayoutDirection layoutDirection;
  final VoidCallback onClose;
  final ValueChanged<ReaderTheme> onThemeChanged;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<_ReaderLayoutDirection> onLayoutDirectionChanged;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? const Color(0xFFF4F4F0) : LingferColors.ink;
    final sub = isDark ? const Color(0xFFB2BCBD) : LingferColors.muted;
    final accent = isDark ? const Color(0xFFB1CED2) : LingferColors.accent;
    final field = isDark ? const Color(0xFF344347) : LingferColors.tint;
    final mq = MediaQuery.of(context);
    final scale = mq.textScaler.scale(14) / 14;
    final duration = mq.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 180);

    Future<void> openLayoutPicker() async {
      final selected = await showBookReaderChoices<_ReaderLayoutDirection>(
        context,
        title: '排版方向',
        selected: layoutDirection,
        isDark: isDark,
        choices: const [
          BookReaderChoice(
            value: _ReaderLayoutDirection.horizontal,
            label: '横向翻页',
          ),
          BookReaderChoice(
            value: _ReaderLayoutDirection.vertical,
            label: '竖向滑动',
          ),
        ],
      );
      if (selected != null) onLayoutDirectionChanged(selected);
    }

    final sheet = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 620,
        maxHeight: mq.size.height * 0.88,
      ),
      child: BookReaderControlSurface(
        isDark: isDark,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '字号与外观',
                        style: LingferType.interfaceHeading.copyWith(
                          fontSize: 18,
                          color: fg,
                        ),
                      ),
                    ),
                    Semantics(
                      label: '关闭阅读设置',
                      button: true,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 48),
                        onPressed: onClose,
                        child: Icon(CupertinoIcons.xmark, color: sub, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _FontSizePill(
                        fontSize: fontSize,
                        foreground: fg,
                        background: field,
                        onSmaller: () => onFontSizeChanged(fontSize - 1),
                        onLarger: () => onFontSizeChanged(fontSize + 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _QuickPill(
                      icon: CupertinoIcons.book,
                      label:
                          layoutDirection == _ReaderLayoutDirection.horizontal
                          ? '翻页'
                          : '滑动',
                      foreground: fg,
                      background: field,
                      onPressed: openLayoutPicker,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(CupertinoIcons.textformat_size, size: 16, color: sub),
                    Expanded(
                      child: CupertinoSlider(
                        value: fontSize.clamp(14, 26),
                        min: 14,
                        max: 26,
                        activeColor: accent,
                        onChanged: onFontSizeChanged,
                      ),
                    ),
                    Icon(CupertinoIcons.textformat_size, size: 22, color: sub),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '纸面',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: sub,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = scale > 2.3
                        ? 1
                        : (constraints.maxWidth < 360 || scale > 1.3 ? 2 : 3);
                    final width =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final t in ReaderTheme.all)
                          SizedBox(
                            width: width,
                            height: 102 + math.max(0, scale - 1) * 34,
                            child: _ThemeTile(
                              theme: t,
                              selected: t.kind == theme.kind,
                              isDark: isDark,
                              onPressed: () => onThemeChanged(t),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: duration,
        opacity: visible ? 1 : 0,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onClose,
                child: Container(color: const Color(0x33000000)),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: AnimatedSlide(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  offset: visible ? Offset.zero : const Offset(0, 0.12),
                  child: sheet,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontSizePill extends StatelessWidget {
  const _FontSizePill({
    required this.fontSize,
    required this.foreground,
    required this.background,
    required this.onSmaller,
    required this.onLarger,
  });

  final double fontSize;
  final Color foreground;
  final Color background;
  final VoidCallback onSmaller;
  final VoidCallback onLarger;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: math.max(
        48,
        MediaQuery.textScalerOf(context).scale(13) * 1.4 + 16,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x11000000)),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onSmaller,
              child: Text(
                '小',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          Container(width: 1, color: const Color(0x22000000)),
          Expanded(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onLarger,
              child: Text(
                '大',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickPill extends StatelessWidget {
  const _QuickPill({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        height: math.max(
          48,
          MediaQuery.textScalerOf(context).scale(13) * 1.4 + 16,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x11000000)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: foreground,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              CupertinoIcons.chevron_down,
              size: 14,
              color: foreground.withValues(alpha: 0.70),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.theme,
    required this.selected,
    required this.isDark,
    required this.onPressed,
  });

  final ReaderTheme theme;
  final bool selected;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final labelColor = theme.textColor;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? (isDark ? const Color(0xFFB1CED2) : LingferColors.accent)
                : (isDark ? const Color(0x22FFFFFF) : const Color(0x22000000)),
            width: selected ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 20,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '阅读',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: theme.textColor,
                  decoration: TextDecoration.none,
                ),
              ),
              const Spacer(),
              Text(
                theme.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.value,
    required this.foreground,
    required this.background,
    required this.onPressed,
  });

  final String title;
  final String value;
  final Color foreground;
  final Color background;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x11000000)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: foreground.withValues(alpha: 0.75),
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: foreground.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillToggle extends StatelessWidget {
  const _PillToggle({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? LingferColors.accent : LingferColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0x330A84FF) : const Color(0x11000000),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? CupertinoColors.white : LingferColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

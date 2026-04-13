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
import '../../widgets/apple_glass_sheet.dart';
import '../../widgets/liquid_selection_controls.dart';
import '../../widgets/reading_text.dart';
import '../../utils/level_color.dart';

const String _deepSeekProxyUrl =
    String.fromEnvironment('DEEPSEEK_PROXY_URL', defaultValue: '');
const String _appSecret = String.fromEnvironment('APP_SECRET', defaultValue: '');

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, required this.book});

  final Book book;

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
  int _translatingCount = 0;
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
    final nextDock =
        (y != null && y > h * 0.5) ? AppleGlassDock.top : AppleGlassDock.bottom;
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

    final candidates = <int>[
      _anchorIndex,
      _anchorIndex - 1,
      _anchorIndex + 1,
    ];
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
      setState(() {
        _bookText = text;
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
        _loadError = '$error';
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
        accentColor: const Color(0xFF999999),
        fontSize: _fontSize,
        baseColor: baseColor,
      );
    }

    const textHeightBehavior = TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    );
    final baseStyle = TextStyle(
      color: baseColor,
      fontSize: _fontSize,
      height: 1.6,
      letterSpacing: 0.5,
      decoration: TextDecoration.none,
      fontFamilyFallback: const ['.SF UI Text', '.SF Pro Text', 'PingFang SC'],
    );
    final strut = StrutStyle(
      fontSize: _fontSize,
      height: 1.6,
      forceStrutHeight: true,
    );

    final spans = <TextSpan>[];
    final startChunk = _chunkIndexForDisplayOffset(start);
    final endChunk = _chunkIndexForDisplayOffset(math.max(start, end - 1));

    for (var chunkIndex = startChunk;
        chunkIndex <= endChunk && chunkIndex < _allChunks.length;
        chunkIndex += 1) {
      final chunkStart = _chunkDisplayStarts[chunkIndex];
      final chunkEnd = (chunkIndex + 1 < _chunkDisplayStarts.length)
          ? _chunkDisplayStarts[chunkIndex + 1]
          : _displayText.length;
      final segStart = math.max(start, chunkStart);
      final segEnd = math.min(end, chunkEnd);
      if (segEnd <= segStart) continue;

      final chunkText = _rendered[chunkIndex]?.text ?? _allChunks[chunkIndex];
      final localStart =
          (segStart - chunkStart).clamp(0, chunkText.length).toInt();
      final localEnd =
          (segEnd - chunkStart).clamp(localStart, chunkText.length).toInt();
      if (localEnd <= localStart) continue;

      final accentColor = _rendered[chunkIndex]?.accentColor ??
          const Color(0xFF999999);
      final accentStyle = TextStyle(
        color: accentColor,
        fontSize: (_fontSize - 2).clamp(12, 30).toDouble(),
        height: 1.6,
        letterSpacing: 0.5,
        decoration: TextDecoration.none,
        fontFamilyFallback: const ['.SF UI Text', '.SF Pro Text', 'PingFang SC'],
      );

      // If the page boundary slices through "(...)" we still want to keep the
      // inside text colored correctly.
      final prefix = chunkText.substring(0, localStart);
      final inParenAtStart =
          prefix.lastIndexOf('(') > prefix.lastIndexOf(')');
      final segment = chunkText.substring(localStart, localEnd);
      _appendParenAwareSpans(
        spans,
        segment,
        accentStyle: accentStyle,
        inParenAtStart: inParenAtStart,
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

  void _appendParenAwareSpans(
    List<TextSpan> out,
    String segment, {
    required TextStyle accentStyle,
    required bool inParenAtStart,
  }) {
    if (segment.isEmpty) return;
    var inParen = inParenAtStart;
    final buf = StringBuffer();

    void flush() {
      if (buf.isEmpty) return;
      out.add(TextSpan(text: buf.toString(), style: inParen ? accentStyle : null));
      buf.clear();
    }

    for (var i = 0; i < segment.length; i += 1) {
      final cu = segment.codeUnitAt(i);
      if (cu == 0x28) {
        // (
        flush();
        out.add(const TextSpan(text: '('));
        inParen = true;
        continue;
      }
      if (cu == 0x29) {
        // )
        flush();
        out.add(const TextSpan(text: ')'));
        inParen = false;
        continue;
      }
      buf.writeCharCode(cu);
    }
    flush();
  }

  void _scheduleHorizontalRepagination() {
    if (_layoutDirection != _ReaderLayoutDirection.horizontal) return;
    if (_repaginateScheduled) return;
    _repaginateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repaginateScheduled = false;
      if (!mounted) return;
      _recomputeHorizontalPagination(keepPageIndex: _anchorIndex);
    });
  }

  void _recomputeHorizontalPagination({int? keepPageIndex}) {
    if (_layoutDirection != _ReaderLayoutDirection.horizontal) return;
    final keep = keepPageIndex ?? _anchorIndex;
    final composed = _composeDisplayText();
    final paginated = _paginateForHorizontal(context, composed.displayText);

    setState(() {
      _displayText = composed.displayText;
      _chunkDisplayStarts = composed.chunkStarts;
      _pages = paginated.pages;
      _horizontalTextHeight = paginated.textHeight;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final clamped =
          _pages.isEmpty ? 0 : keep.clamp(0, _pages.length - 1);
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
    final topReserved = (_topPadding(context) - padding.top).clamp(0.0, safeHeight);
    final bottomReserved =
        (_bottomPadding(context) - padding.bottom).clamp(0.0, safeHeight);

    final width = (safeWidth - side * 2).clamp(240.0, 2400.0);
    final height =
        (safeHeight - topReserved - bottomReserved).clamp(240.0, 8000.0);
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
    final maxLines =
        math.max(1, (realAvailableHeight / exactLineHeight).floor());
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
          end = _adjustPageBreak(
            text,
            start,
            end,
            lookback: breakLookback,
          );
          break;
        }

        // Not filled yet: expand window (doubling, capped).
        final doubled = (windowEnd - start) * 2;
        final nextChars =
            doubled.clamp(minWindowChars, maxWindowChars).toInt();
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
      final list =
          _highlights.map((m) => m.toJson()).toList(growable: false);
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
        _inFlight.clear();
        _translatingCount = 0;
        _pendingChunkLoads.clear();
        _pendingAllowNetwork.clear();
        _postFrameLoadScheduled = false;
      });

      // Critical: ensure chunk 0 gets a cache-check + translation attempt.
      _requestChunkLoad(0, allowNetwork: true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final saved = (_prefs?.getInt(_progressKey()) ?? 0);
        final clamped =
            _allChunks.isEmpty ? 0 : saved.clamp(0, _allChunks.length - 1);
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
      _inFlight.clear();
      _translatingCount = 0;
      _pendingChunkLoads.clear();
      _pendingAllowNetwork.clear();
      _postFrameLoadScheduled = false;
    });

    // Critical: ensure chunk 0 gets a cache-check + translation attempt.
    _requestChunkLoad(0, allowNetwork: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final saved = (_prefs?.getInt(_progressKey()) ?? 0);
      final clamped =
          _pages.isEmpty ? 0 : saved.clamp(0, _pages.length - 1);
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

  String _sanitizeForPathSegment(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return 'x';
    // Keep Unicode (Chinese) intact; only replace illegal filename characters.
    return t.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
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

  File _cacheFileForChunk(int index, String levelLabel) {
    final dir = _cacheDirForBook();
    final levelSeg = _sanitizeForPathSegment(levelLabel);
    return File(
      '${dir.path}${Platform.pathSeparator}chunk_${index}_$levelSeg.json',
    );
  }

  String? _readCacheSyncFor(int index, String levelLabel) {
    try {
      final file = _cacheFileForChunk(index, levelLabel);
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  String _chunkFrozenLevelKey(int index) {
    return 'chunk_level_${_bookId}_$index';
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

  Future<void> _writeCache(int index, String levelLabel, String jsonText) async {
    try {
      final file = _cacheFileForChunk(index, levelLabel);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonText, flush: true);
    } catch (error, stackTrace) {
      debugPrint('[cache] write error=$error');
      debugPrintStack(stackTrace: stackTrace);
    }
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

    final raw = _allChunks[index];

    // Critical: cache must be checked first, synchronously.
    if (preferCache) {
      final cached = _readBestCacheSync(index);
      if (cached != null) {
        final render = _renderFromCacheOrRaw(raw, cached.cacheText);
        final prevEffective = _rendered[index]?.text ?? raw;
        // Freeze this chunk to the cached level so later level switches won't
        // trigger re-translation.
        final prefs = _prefs;
        if (prefs != null) {
          unawaited(prefs.setString(_chunkFrozenLevelKey(index), cached.levelLabel));
        }
        setState(() {
          _rendered[index] = render;
        });
        if (_layoutDirection == _ReaderLayoutDirection.horizontal &&
            prevEffective != render.text) {
          _scheduleHorizontalRepagination();
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
    unawaited(_translateAndCache(index, raw, level: level, mode: mode));
  }

  _ChunkRender _renderFromCacheOrRaw(String raw, String cacheText) {
    try {
      final decoded = jsonDecode(cacheText);
      if (decoded is! Map) {
        return _ChunkRender(
          text: raw,
          accentColor: const Color(0xFF999999),
        );
      }
      final levelLabel = decoded['level'];
      final mode = decoded['mode'];
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
      final replaced = vocab.isEmpty
          ? raw
          : AiTranslationService.applyVocabReplacements(
              raw,
              vocab,
              mode: _modeFromCache(mode),
            );
      return _ChunkRender(
        text: replaced,
        accentColor: getLevelColor((levelLabel is String) ? levelLabel : ''),
      );
    } catch (_) {
      return _ChunkRender(text: raw, accentColor: const Color(0xFF999999));
    }
  }

  TranslationMode _modeFromCache(Object? mode) {
    final m = (mode is String) ? mode : '';
    if (m == 'en_zh') return TranslationMode.enToZh;
    return TranslationMode.zhToEn;
  }

  Future<void> _translateAndCache(
    int index,
    String raw, {
    required VocabularyLevel level,
    required TranslationMode mode,
  }) async {
    var render =
        _ChunkRender(text: raw, accentColor: const Color(0xFF999999));
    try {
      final service = AiTranslationService(
        proxyUrl: _deepSeekProxyUrl,
        appSecret: _appSecret,
      );
      final vocabJson = await service.fetchVocabJson(
        raw: raw,
        level: level,
        mode: mode,
      );
      if (vocabJson == null) return;

      final wrapper = jsonEncode({
        'level': level.label,
        'mode': mode == TranslationMode.enToZh ? 'en_zh' : 'zh_en',
        'data': jsonDecode(vocabJson),
      });
      await _writeCache(index, level.label, wrapper);
      final prefs = _prefs;
      if (prefs != null) {
        unawaited(prefs.setString(_chunkFrozenLevelKey(index), level.label));
      }

      // Must render from cache content, not from network response, to guarantee
      // consistency with the persisted format.
      final cached = _readCacheSyncFor(index, level.label);
      if (cached != null) render = _renderFromCacheOrRaw(raw, cached);
    } catch (error, stackTrace) {
      debugPrint('[ai] translate error=$error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) {
        final prevEffective = _rendered[index]?.text ?? raw;
        setState(() {
          _inFlight.remove(index);
          if (_translatingCount > 0) _translatingCount -= 1;
          _rendered[index] = render;
        });
        if (_layoutDirection == _ReaderLayoutDirection.horizontal &&
            prevEffective != render.text) {
          _scheduleHorizontalRepagination();
        }
      } else {
        _inFlight.remove(index);
        if (_translatingCount > 0) _translatingCount -= 1;
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
    final selected = _currentLevel;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: const Text('难度'),
          message: const Text('边读边切换，不同段落会按当时难度着色混排并缓存'),
          actions: [
            for (final level in VocabularyLevel.values)
              CupertinoActionSheetAction(
                onPressed: () {
                  _setLevel(level);
                  Navigator.of(context).pop();
                },
                isDefaultAction: level == selected,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: getLevelColor(level.label),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(level.label),
                  ],
                ),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        );
      },
    );
  }

  Future<void> _showModePicker() async {
    final selected = _mode;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: const Text('翻译模式'),
          actions: [
            for (final m in TranslationMode.values)
              CupertinoActionSheetAction(
                onPressed: () {
                  setState(() => _mode = m);
                  Navigator.of(context).pop();
                },
                isDefaultAction: m == selected,
                child: Text(m.label),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        );
      },
    );
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

    final title = _book.title.trim().isEmpty ? '目录' : _book.title.trim();
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
                                            ? CupertinoColors.white
                                                .withValues(alpha: 0.92)
                                            : const Color(0xFFF2F2F7),
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
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color: Color(0xFF1C1C1E),
                                                    decoration:
                                                        TextDecoration.none,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '第${start + 1}-$end页',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF8E8E93),
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
                                              color: Color(0xFF8E8E93),
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
    final title =
        _book.title.trim().isEmpty ? '书签与高亮标记' : _book.title.trim();

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
                      child: _CenterLoading(message: overlayMessage),
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
        content: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('返回'),
                ),
                const SizedBox(height: 14),
                Text(
                  '读取失败：$_loadError',
                  style: TextStyle(color: ink, fontSize: 16, height: 1.6),
                ),
              ],
            ),
          ),
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
    final clampedUnitIndex =
        unitCount <= 0 ? 0 : _anchorIndex.clamp(0, unitCount - 1);
    final pageLabel =
        unitCount <= 0 ? '' : '${clampedUnitIndex + 1}/$unitCount 页';
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
                                  ? const _FooterLoading()
                                  : const SizedBox(height: 60);
                            }

                            // Never trigger any setState while list items are building.
                            // Cache checks / load attempts are deferred post-frame.
                            _requestChunkLoad(index, allowNetwork: false);

                            final raw = _allChunks[index];
                            final render = _rendered[index];
                            final text = render?.text ?? raw;
                            final accentColor = render?.accentColor ??
                                const Color(0xFF999999);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: ReadingText(
                                chunkText: text,
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
                                    await _prefs?.setInt(
                                      _progressKey(),
                                      index,
                                    );
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
                        _book.title.trim().isEmpty ? '阅读' : _book.title.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                          color: isDark
                              ? const Color(0xB3FFFFFF)
                              : const Color(0xFF6E6E73),
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
                          final clamped =
                              idx.clamp(0, math.max(0, unitCount - 1));
                          return Text(
                            '${clamped + 1}/$unitCount 页',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xB3FFFFFF)
                                  : const Color(0xFF6E6E73),
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
                title: _book.title,
                pageLabel: pageLabel,
                isDark: isDark,
                currentLevel: _currentLevel,
                mode: _mode,
                directoryLabel: '目录 · $progressPercent%',
                marksCount: _bookmarks.length + _highlights.length,
                hasBookmark: unitCount > 0 &&
                    _bookmarks.containsKey(
                      clampedUnitIndex.clamp(0, math.max(0, unitCount - 1)),
                    ),
                onBack: () => Navigator.of(context).maybePop(),
                onDismiss: () => setState(() => _chromeVisible = false),
                onOpenDirectory: () => _showDirectorySheet(unitCount: unitCount),
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
                  ignoring: true,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _translatingCount > 0 ? 1.0 : 0.0,
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
                            color: CupertinoColors.white.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: const Color(0x11000000)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CupertinoActivityIndicator(radius: 8),
                              SizedBox(width: 8),
                              Text(
                                'AI 解析中...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF1C1C1E),
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
                    color: Color(0xFF1C1C1E),
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
                          color:
                              CupertinoColors.systemGrey6.withValues(alpha: 0.86),
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
                            color: Color(0xFF1C1C1E),
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
    final fg = isDark ? CupertinoColors.white : const Color(0xFF1C1C1E);
    final sub = isDark ? const Color(0xB3FFFFFF) : const Color(0xFF6E6E73);
    final panelBg = isDark
        ? const Color(0xCC2C2C2E)
        : CupertinoColors.white.withValues(alpha: 0.86);
    final panelBorder =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000);
    final iconBg =
        isDark ? const Color(0x22FFFFFF) : const Color(0x12000000);
    final iconBorder =
        isDark ? const Color(0x14FFFFFF) : const Color(0x14000000);

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
            child: SizedBox(
              height: 52,
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
                    child: Center(
                      child: Text(
                        title.trim().isEmpty ? '阅读' : title.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: sub,
                          decoration: TextDecoration.none,
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
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 54 + mq.padding.bottom,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  color: panelBg,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: panelBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 32,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ChromePillButton(
                            icon: CupertinoIcons.list_bullet,
                            label: directoryLabel,
                            foreground: fg,
                            iconBackground: iconBg,
                            iconBorder: iconBorder,
                            onPressed: onOpenDirectory,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ChromePillButton(
                            icon: CupertinoIcons.bookmark,
                            label: '书签与高亮标记',
                            trailing: marksCount > 0 ? '$marksCount' : null,
                            foreground: fg,
                            iconBackground: iconBg,
                            iconBorder: iconBorder,
                            onPressed: onOpenMarks,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ChromeActionButton(
                            icon: CupertinoIcons.slider_horizontal_3,
                            label: currentLevel.label,
                            foreground: fg,
                            iconBackground: iconBg,
                            iconBorder: iconBorder,
                            onPressed: onPickLevel,
                          ),
                        ),
                        Expanded(
                          child: _ChromeActionButton(
                            icon: CupertinoIcons.arrow_right_arrow_left,
                            label: mode.label,
                            foreground: fg,
                            iconBackground: iconBg,
                            iconBorder: iconBorder,
                            onPressed: onPickMode,
                          ),
                        ),
                        Expanded(
                          child: _ChromeActionButton(
                            icon: hasBookmark
                                ? CupertinoIcons.bookmark_fill
                                : CupertinoIcons.bookmark,
                            label: '书签',
                            foreground: fg,
                            iconBackground: iconBg,
                            iconBorder: iconBorder,
                            active: hasBookmark,
                            onPressed: onToggleBookmark,
                          ),
                        ),
                        Expanded(
                          child: _ChromeActionButton(
                            icon: CupertinoIcons.textformat_size,
                            label: '主题与设置',
                            foreground: fg,
                            iconBackground: iconBg,
                            iconBorder: iconBorder,
                            onPressed: onOpenSettings,
                          ),
                        ),
                      ],
                    ),
                  ],
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
                    fontWeight: FontWeight.w600,
                    color: sub,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChromeActionButton extends StatelessWidget {
  const _ChromeActionButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.iconBackground,
    required this.iconBorder,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color iconBackground;
  final Color iconBorder;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final iconColor = active
        ? const Color(0xFF0A84FF)
        : foreground.withValues(alpha: 0.9);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 2),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconBackground,
              border: Border.all(color: iconBorder),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foreground.withValues(alpha: 0.82),
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
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
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: CupertinoColors.white.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x11000000)),
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
                maxLines: 1,
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
        child: Icon(icon, size: 18, color: const Color(0xFF1C1C1E)),
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
                  color: Color(0xFF1C1C1E),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          _circleButton(
            icon: CupertinoIcons.check_mark,
            onPressed: onDone,
          ),
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
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    if (sameDay) return '今天';
    return '${d.month}/${d.day}';
  }

  Widget _card({
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
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
                    color: Color(0xFF1C1C1E),
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
                    color: Color(0xFF1C1C1E),
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
                          color: Color(0xFF8E8E93),
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
                      final chapter = (unit / widget.pagesPerChapter).floor() + 1;
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '第$chapter章',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1C1C1E),
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        day,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF8E8E93),
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
                                    color: Color(0xFF8E8E93),
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
                        color: Color(0xFF8E8E93),
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
                    final chapter = (m.unitIndex / widget.pagesPerChapter).floor() + 1;
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
                                        color: Color(0xFF1C1C1E),
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '第$chapter章 · $day',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF8E8E93),
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
                                  color: Color(0xFF8E8E93),
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
  const _ChunkRender({required this.text, required this.accentColor});

  final String text;
  final Color accentColor;
}

class _PageSlice {
  const _PageSlice(this.start, this.end);

  final int start;
  final int end;
}

class _FooterLoading extends StatelessWidget {
  const _FooterLoading();

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF2B2B2B);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(),
            SizedBox(height: 10),
            Text(
              'AI 正在翻译下一段...',
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

  String toPrefs() => this == _ReaderLayoutDirection.horizontal
      ? 'horizontal'
      : 'vertical';
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
  const _CenterLoading({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF2B2B2B);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CupertinoActivityIndicator(),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(color: ink, fontSize: 16, height: 1.4),
        ),
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
    final fg = isDark ? CupertinoColors.white : const Color(0xFF1C1C1E);
    final sub = isDark ? const Color(0xB3FFFFFF) : const Color(0xFF6E6E73);
    final sheetBg =
        isDark ? const Color(0xCC1C1C1E) : CupertinoColors.white.withValues(alpha: 0.88);
    final border = isDark ? const Color(0x22FFFFFF) : const Color(0x14000000);
    final barrier = isDark ? const Color(0x66000000) : const Color(0x33000000);

    Future<void> openLayoutPicker() async {
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) {
          return CupertinoActionSheet(
            title: const Text('排版方向'),
            actions: [
              CupertinoActionSheetAction(
                isDefaultAction:
                    layoutDirection == _ReaderLayoutDirection.horizontal,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onLayoutDirectionChanged(_ReaderLayoutDirection.horizontal);
                },
                child: const Text('横向翻页'),
              ),
              CupertinoActionSheetAction(
                isDefaultAction:
                    layoutDirection == _ReaderLayoutDirection.vertical,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onLayoutDirectionChanged(_ReaderLayoutDirection.vertical);
                },
                child: const Text('竖向滑动'),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
          );
        },
      );
    }

    final sheet = ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: sheetBg,
            border: Border.all(color: border),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0x33FFFFFF)
                            : const Color(0x33000000),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '主题与设置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: fg,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 40),
                        onPressed: onClose,
                        child: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          size: 28,
                          color: isDark
                              ? const Color(0x66FFFFFF)
                              : const Color(0xFFAEAEB2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _FontSizePill(
                          fontSize: fontSize,
                          foreground: fg,
                          background: isDark
                              ? const Color(0x1FFFFFFF)
                              : const Color(0x12000000),
                          onSmaller: () => onFontSizeChanged(fontSize - 1),
                          onLarger: () => onFontSizeChanged(fontSize + 1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _QuickPill(
                        icon: CupertinoIcons.list_bullet,
                        label: layoutDirection ==
                                _ReaderLayoutDirection.horizontal
                            ? '翻页'
                            : '滑动',
                        foreground: fg,
                        background: isDark
                            ? const Color(0x1FFFFFFF)
                            : const Color(0x12000000),
                        onPressed: openLayoutPicker,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(CupertinoIcons.textformat_size, size: 16, color: sub),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CupertinoSlider(
                          value: fontSize.clamp(14, 26),
                          min: 14,
                          max: 26,
                          onChanged: onFontSizeChanged,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        CupertinoIcons.textformat_size,
                        size: 20,
                        color: sub,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '主题',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fg,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.05,
                    children: [
                      for (final t in ReaderTheme.all)
                        _ThemeTile(
                          theme: t,
                          selected: t.kind == theme.kind,
                          isDark: isDark,
                          onPressed: () => onThemeChanged(t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      showCupertinoDialog<void>(
                        context: context,
                        builder: (ctx) => CupertinoAlertDialog(
                          title: const Text('自定义主题'),
                          content: const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('该功能正在打磨中，即将开放。'),
                          ),
                          actions: [
                            CupertinoDialogAction(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('知道了'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0x1FFFFFFF)
                            : const Color(0x12000000),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0x11000000)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.gear,
                            size: 18,
                            color: fg,
                          ),
                          SizedBox(width: 10),
                          Text(
                            '自定义',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: fg,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1 : 0,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onClose,
                child: Container(color: barrier),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                offset: visible ? Offset.zero : const Offset(0, 0.12),
                child: sheet,
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
      height: 44,
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
                  fontWeight: FontWeight.w700,
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
                  fontWeight: FontWeight.w700,
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
        height: 44,
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
                fontWeight: FontWeight.w700,
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
    final labelColor = isDark ? CupertinoColors.white : const Color(0xFF1C1C1E);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? const Color(0xFF0A84FF)
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
                '大小',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
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
                  color: labelColor.withValues(alpha: 0.78),
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
          color: selected ? const Color(0xFF0A84FF) : const Color(0xFFF2F2F7),
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
              color: selected ? CupertinoColors.white : const Color(0xFF1C1C1E),
            ),
          ),
        ),
      ),
    );
  }
}

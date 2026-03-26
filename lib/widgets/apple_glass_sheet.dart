import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;

import '../models/translation_mode.dart';
import '../models/vocabulary_level.dart';
import '../services/ai_translation_service.dart';

/// "Apple Glass" translation panel.
///
/// This is intentionally NOT a modal route, so it can coexist with native text
/// selection handles and allow users to adjust the selection boundaries while
/// the panel is open.
enum AppleGlassDock { top, bottom }

class AppleGlassPanel extends StatefulWidget {
  const AppleGlassPanel({
    super.key,
    required this.selectedTextListenable,
    required this.dock,
    required this.initialLevel,
    required this.ai,
    required this.onDismiss,
  });

  final ValueListenable<String> selectedTextListenable;
  final AppleGlassDock dock;
  final VocabularyLevel initialLevel;
  final AiTranslationService ai;
  final VoidCallback onDismiss;

  @override
  State<AppleGlassPanel> createState() => _AppleGlassPanelState();
}

class _AppleGlassPanelState extends State<AppleGlassPanel> {
  static const int _segmentTranslate = 0;
  static const int _segmentVocab = 1;

  static const TextStyle _panelBaseTextStyle = TextStyle(
    decoration: TextDecoration.none,
    color: Color(0xFF000000),
    fontFamily: '.SF UI Text',
  );

  static const TextStyle _segmentLabelStyle = TextStyle(
    decoration: TextDecoration.none,
    color: Color(0xFF1C1C1E),
    fontFamily: '.SF UI Text',
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );

  int _segment = _segmentTranslate;

  String _selectedText = '';

  bool _translating = false;
  String? _translation;
  String? _translationError;
  int _translationSerial = 0;

  late VocabularyLevel _level;
  bool _extracting = false;
  List<CoreVocabItem> _vocab = const <CoreVocabItem>[];
  String? _vocabError;
  int _vocabSerial = 0;

  bool _shown = false;
  double _panelHeight = 0;

  // 0ms switching: cache vocab results by (selectedText, level).
  // This prevents cross-book / cross-sentence cache pollution.
  final Map<String, List<CoreVocabItem>> _vocabCache =
      <String, List<CoreVocabItem>>{};

  String _vocabCacheKey(String text, VocabularyLevel level) =>
      '${text.hashCode}_${level.name}';

  @override
  void initState() {
    super.initState();
    _selectedText = widget.selectedTextListenable.value.trim();
    _level = widget.initialLevel;
    widget.selectedTextListenable.addListener(_handleSelectedTextChanged);

    if (_selectedText.isNotEmpty) {
      _runTranslate();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    widget.selectedTextListenable.removeListener(_handleSelectedTextChanged);
    super.dispose();
  }

  void _handleSelectedTextChanged() {
    final next = widget.selectedTextListenable.value.trim();
    if (next.isEmpty) return;
    if (next == _selectedText) return;

    setState(() {
      _selectedText = next;
      _translation = null;
      _translationError = null;
      _vocab = const <CoreVocabItem>[];
      _vocabError = null;
      _vocabCache.clear();
    });

    // Re-run the active segment.
    if (_segment == _segmentTranslate) {
      _runTranslate();
    } else {
      _runExtractVocab();
    }
  }

  Future<void> _runTranslate() async {
    final text = _selectedText.trim();
    if (text.isEmpty) return;
    final serial = ++_translationSerial;
    setState(() {
      _translating = true;
      _translationError = null;
    });

    final result = await widget.ai.translatePlainText(
      raw: text,
      mode: TranslationMode.enToZh,
    );
    if (!mounted || serial != _translationSerial) return;
    setState(() {
      _translating = false;
      if (result == null || result.trim().isEmpty) {
        _translation = null;
        _translationError = '翻译失败，请稍后重试';
      } else {
        _translation = result.trim();
        _translationError = null;
      }
    });
  }

  Future<void> _runExtractVocab() async {
    final text = _selectedText.trim();
    if (text.isEmpty) return;

    final key = _vocabCacheKey(text, _level);
    final cached = _vocabCache[key];
    if (cached != null) {
      setState(() {
        _extracting = false;
        _vocab = cached;
        _vocabError = null;
      });
      return;
    }

    final serial = ++_vocabSerial;
    setState(() {
      _extracting = true;
      _vocabError = null;
    });

    final result = await widget.ai.extractCoreVocabulary(
      raw: text,
      level: _level,
    );
    if (!mounted || serial != _vocabSerial) return;
    _vocabCache[key] = result;
    setState(() {
      _extracting = false;
      _vocab = result;
      _vocabError = null;
    });
  }

  void _setSegment(int next) {
    if (next == _segment) return;
    setState(() => _segment = next);
    if (next == _segmentTranslate) {
      if ((_translation ?? '').trim().isEmpty && !_translating) {
        _runTranslate();
      }
      return;
    }

    if (_vocab.isEmpty && !_extracting) {
      _runExtractVocab();
    }
  }

  void _setLevel(VocabularyLevel next) {
    if (next == _level) return;

    setState(() {
      _level = next;
      _vocabError = null;
    });

    final key = _vocabCacheKey(_selectedText.trim(), next);
    final cached = _vocabCache[key];
    if (cached != null) {
      setState(() {
        _extracting = false;
        _vocab = cached;
      });
      return;
    }

    _runExtractVocab();
  }

  Widget _dragHandle({
    required bool isTop,
    required double minHeight,
    required double maxHeight,
    required double defaultHeight,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        final base = (_panelHeight > 0) ? _panelHeight : defaultHeight;
        final dy = details.delta.dy;
        // Bottom panel: drag down (dy>0) collapses.
        // Top panel: drag up   (dy<0) collapses.
        var next = isTop ? (base + dy) : (base - dy);
        if (next <= minHeight) {
          widget.onDismiss();
          return;
        }
        next = next.clamp(minHeight, maxHeight);
        setState(() => _panelHeight = next);
      },
      onVerticalDragEnd: (_) {
        final base = (_panelHeight > 0) ? _panelHeight : defaultHeight;
        if (base <= minHeight + 2) {
          widget.onDismiss();
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: Center(
          child: Container(
            width: 38,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _segment,
              thumbColor: CupertinoColors.white.withValues(alpha: 0.90),
              backgroundColor: const Color(0x1F000000),
              children: const {
                _segmentTranslate: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Text('整段翻译', style: _segmentLabelStyle),
                ),
                _segmentVocab: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Text('核心生词', style: _segmentLabelStyle),
                ),
              },
              onValueChanged: (v) {
                if (v == null) return;
                _setSegment(v);
              },
            ),
          ),
          const SizedBox(width: 10),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(34, 34),
            onPressed: widget.onDismiss,
            child: const Icon(
              CupertinoIcons.clear_thick,
              size: 18,
              color: Color(0xFF6E6E73),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedPreview() {
    final t = _selectedText.trim();
    if (t.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        t,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.25,
          color: Color(0xFF6E6E73),
        ),
      ),
    );
  }

  Widget _levelPicker() {
    const labels = <VocabularyLevel, String>{
      VocabularyLevel.zhongkao: '中考',
      VocabularyLevel.gaokao: '高考',
      VocabularyLevel.cet4: '四级',
      VocabularyLevel.cet6: '六级',
      VocabularyLevel.kaoyan: '考研',
      VocabularyLevel.ielts: '雅思',
      VocabularyLevel.toefl: '托福',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: CupertinoSlidingSegmentedControl<VocabularyLevel>(
        groupValue: _level,
        thumbColor: CupertinoColors.white.withValues(alpha: 0.90),
        backgroundColor: const Color(0x1F000000),
        children: {
          for (final entry in labels.entries)
            entry.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
              child: Text(entry.value, style: _segmentLabelStyle),
            ),
        },
        onValueChanged: (v) {
          if (v == null) return;
          _setLevel(v);
        },
      ),
    );
  }

  Widget _loadingRow(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          const CupertinoActivityIndicator(radius: 10),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(fontSize: 14, color: Color(0xFF6E6E73)),
          ),
        ],
      ),
    );
  }

  Widget _translationCard() {
    if (_translating) return _loadingRow('AI 翻译中...');
    final error = (_translationError ?? '').trim();
    final text = (_translation ?? '').trim();

    final h = MediaQuery.sizeOf(context).height;
    final boxH = math.min(h * 0.34, 260.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.white.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14000000)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 22,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: SizedBox(
          height: boxH,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: CupertinoScrollbar(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  text.isNotEmpty ? text : (error.isNotEmpty ? error : '暂无翻译结果'),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: text.isNotEmpty
                        ? const Color(0xFF1C1C1E)
                        : const Color(0xFF8E8E93),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _vocabCard(CoreVocabItem item) {
    final phonetic = item.phonetic.trim();
    final meaning = item.meaning.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: CupertinoColors.white.withValues(alpha: 0.72),
          border: Border.all(color: const Color(0x14000000)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 26,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.word,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                  if (phonetic.isNotEmpty)
                    Text(
                      phonetic,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                ],
              ),
              if (meaning.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  meaning,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSlivers() {
    final slivers = <Widget>[
      SliverToBoxAdapter(child: _header()),
      SliverToBoxAdapter(child: _selectedPreview()),
    ];

    if (_segment == _segmentTranslate) {
      slivers.add(SliverToBoxAdapter(child: _translationCard()));
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 10)));
      return slivers;
    }

    slivers.add(SliverToBoxAdapter(child: _levelPicker()));
    if (_extracting) {
      slivers.add(SliverToBoxAdapter(child: _loadingRow('AI 提取生词中...')));
    } else if ((_vocabError ?? '').trim().isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Text(
              _vocabError!,
              style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
            ),
          ),
        ),
      );
    } else if (_vocab.isEmpty) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Text(
              '该段落没有符合当前难度的核心生词。',
              style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
            ),
          ),
        ),
      );
    } else {
      slivers.add(
        SliverList.builder(
          itemCount: _vocab.length,
          itemBuilder: (context, index) => _vocabCard(_vocab[index]),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));
    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final safeHeight = mq.size.height - mq.padding.top - mq.padding.bottom;
    final minHeightRaw = math.min(240.0, safeHeight * 0.55);
    final minHeight = math.min(math.max(minHeightRaw, 160.0), safeHeight);
    final maxHeight = math.max(minHeight, safeHeight * 0.72);
    final defaultHeight =
        (safeHeight * 0.38).clamp(minHeight, maxHeight).toDouble();
    final panelHeight = ((_panelHeight > 0) ? _panelHeight : defaultHeight)
        .clamp(minHeight, maxHeight)
        .toDouble();

    final isTop = widget.dock == AppleGlassDock.top;
    final borderRadius = isTop
        ? const BorderRadius.vertical(bottom: Radius.circular(20))
        : const BorderRadius.vertical(top: Radius.circular(20));
    final topInset = mq.padding.top;
    final bottomInset = mq.padding.bottom;

    // Critical: provide Material + DefaultTextStyle context so text styles don't
    // fall back to weird debug styles (yellow underlines/red text).
    // NOTE: We intentionally avoid a full-screen Material ancestor here.
    // A full-screen RenderPhysicalModel can "catch" pointer events even outside
    // the visible panel, which would break native selection handle dragging
    // (especially in the PDF viewer).
    return Stack(
      children: [
        // Do not intercept touches outside the visible panel. This is critical
        // for letting native selection handles remain draggable underneath.
        const IgnorePointer(child: SizedBox.expand()),
        Positioned(
          left: 0,
          right: 0,
          top: isTop ? 0 : null,
          bottom: isTop ? null : 0,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            offset: _shown
                ? Offset.zero
                : (isTop ? const Offset(0, -0.25) : const Offset(0, 0.25)),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _shown ? 1.0 : 0.0,
              child: material.Material(
                type: material.MaterialType.transparency,
                child: DefaultTextStyle(
                  style: _panelBaseTextStyle,
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CupertinoColors.white.withValues(alpha: 0.82),
                          borderRadius: borderRadius,
                          border: Border.all(color: const Color(0x14000000)),
                        ),
                        child: SizedBox(
                          height: panelHeight,
                          width: double.infinity,
                          child: Column(
                            children: [
                              if (isTop) SizedBox(height: topInset),
                              if (!isTop)
                                _dragHandle(
                                  isTop: isTop,
                                  minHeight: minHeight,
                                  maxHeight: maxHeight,
                                  defaultHeight: defaultHeight,
                                ),
                              Expanded(
                                child: CustomScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  slivers: _buildSlivers(),
                                ),
                              ),
                              if (isTop)
                                _dragHandle(
                                  isTop: isTop,
                                  minHeight: minHeight,
                                  maxHeight: maxHeight,
                                  defaultHeight: defaultHeight,
                                ),
                              if (!isTop) SizedBox(height: bottomInset),
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
      ],
    );
  }
}

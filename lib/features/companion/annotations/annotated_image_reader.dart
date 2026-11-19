import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../services/native_image_ocr.dart';
import '../companion_controller.dart';
import '../reading_controls.dart';
import '../reading_preferences.dart';
import '../vocabulary_engine.dart';
import 'ocr_document.dart';

class AnnotatedImageReader extends StatefulWidget {
  const AnnotatedImageReader({
    super.key,
    required this.controller,
    required this.imagePath,
    this.title = '原图阅读',
  });
  final CompanionController controller;
  final String imagePath;
  final String title;
  @override
  State<AnnotatedImageReader> createState() => _AnnotatedImageReaderState();
}

class _AnnotatedImageReaderState extends State<AnnotatedImageReader> {
  OcrDocument? document;
  List<VocabularyHit> hits = const [];
  String? error;
  bool loading = true;
  int revision = 0;
  String signature = '';
  String source = '';
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    unawaited(_read());
  }

  String get _signature =>
      '${widget.controller.preferences.toJson()}|${widget.controller.level.name}';
  void _changed() {
    if (signature.isNotEmpty && signature != _signature) {
      unawaited(
        _read(reuse: source == widget.controller.preferences.source.code),
      );
    } else if (mounted &&
        document != null &&
        !widget.controller.translating &&
        widget.controller.lastText == document!.text) {
      setState(() {
        hits = widget.controller.lastHits;
      });
    }
  }

  Future<void> _read({bool reuse = false}) async {
    final token = ++revision;
    signature = _signature;
    source = widget.controller.preferences.source.code;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
        hits = const [];
      });
    }
    try {
      await widget.controller.initialize();
      signature = _signature;
      source = widget.controller.preferences.source.code;
      final page = reuse && document != null
          ? document!
          : OcrDocument.fromMap(
              await NativeImageOcr.layout(widget.imagePath, language: source),
            );
      if (page.text.trim().isEmpty) throw StateError('图片中没有读到清晰文字，请换一张截图。');
      if (mounted && token == revision) {
        setState(() {
          document = page;
        });
      }
      final found = await widget.controller.analyzeDocument(page);
      if (mounted && token == revision) {
        setState(() {
          hits = found;
          loading = false;
          error = widget.controller.error;
        });
      }
    } catch (_) {
      if (mounted && token == revision) {
        setState(() {
          loading = false;
          error = '图片未能读取完成，请检查所选原文语言或换一张清晰截图。';
        });
      }
    }
  }

  @override
  void dispose() {
    revision++;
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        ReadingLanguageControl(controller: widget.controller, compact: true),
        IconButton(
          tooltip: '重新识别',
          onPressed: () => _read(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (loading) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            loading
                ? '正在定位原词并翻译…'
                : error ?? '找到 ${hits.length} 个词 · 点译义或下划线查看详解 · 双指缩放原图',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final page = document;
              if (page == null) {
                return Center(
                  child: Image.file(
                    File(widget.imagePath),
                    fit: BoxFit.contain,
                  ),
                );
              }
              final width = constraints.maxWidth;
              final scale = width / page.width;
              final height = page.height * scale;
              final textBoxes = page.words
                  .map(
                    (w) => Rect.fromLTRB(
                      w.rect.left * scale,
                      w.rect.top * scale,
                      w.rect.right * scale,
                      w.rect.bottom * scale,
                    ),
                  )
                  .toList();
              final occupied = <Rect>[];
              final positioned = <Widget>[];
              for (final hit in hits.take(24)) {
                for (final box in page.anchors(hit)) {
                  final anchor = Rect.fromLTRB(
                    box.left * scale,
                    box.top * scale,
                    box.right * scale,
                    box.bottom * scale,
                  );
                  final painter = TextPainter(
                    text: TextSpan(
                      text: hit.shortTranslation,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF18324A),
                      ),
                    ),
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                  )..layout(maxWidth: 150);
                  final placement = AnnotationPlacer.place(
                    anchor: anchor,
                    labelSize: Size(painter.width + 16, 25),
                    viewport: Rect.fromLTWH(4, 4, width - 8, height - 8),
                    textBoxes: textBoxes,
                    occupied: occupied,
                  );
                  final label = placement.label;
                  positioned.add(
                    Positioned.fromRect(
                      rect: anchor.inflate(2),
                      child: Semantics(
                        label: '${hit.surface}，${hit.shortTranslation}，查看详解',
                        button: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => showGlassWordDetail(
                            context,
                            widget.controller,
                            hit,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: const Color(
                                    0xFF007AFF,
                                  ).withValues(alpha: .8),
                                  width: 1.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  if (label != null) {
                    occupied.add(label);
                    positioned.add(
                      Positioned.fromRect(
                        rect: label,
                        child: GestureDetector(
                          onTap: () => showGlassWordDetail(
                            context,
                            widget.controller,
                            hit,
                          ),
                          child: GlassSurface(
                            radius: 12,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              child: Text(
                                hit.shortTranslation,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF18324A),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                }
              }
              return InteractiveViewer(
                constrained: false,
                alignment: Alignment.topLeft,
                minScale: 1,
                maxScale: 5,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.file(
                          File(widget.imagePath),
                          fit: BoxFit.fill,
                        ),
                      ),
                      ...positioned,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

Future<void> showGlassWordDetail(
  BuildContext context,
  CompanionController controller,
  VocabularyHit hit,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _GlassWordDetail(controller: controller, hit: hit),
);

class _GlassWordDetail extends StatefulWidget {
  const _GlassWordDetail({required this.controller, required this.hit});
  final CompanionController controller;
  final VocabularyHit hit;
  @override
  State<_GlassWordDetail> createState() => _GlassWordDetailState();
}

class _GlassWordDetailState extends State<_GlassWordDetail> {
  Future<String>? answer;
  @override
  void initState() {
    super.initState();
    _explain();
  }

  void _explain() {
    answer = widget.controller.assistant.explain(
      text: widget.hit.context,
      word: widget.hit.entry.word,
      level: widget.controller.level.label,
      sourceLanguage: ReadingLanguage.parse(
        widget.hit.sourceLanguage,
        fallback: ReadingLanguage.auto,
      ),
      targetLanguage: ReadingLanguage.parse(
        widget.hit.targetLanguage,
        fallback: ReadingLanguage.zh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GlassSurface(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .76,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.hit.surface,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭详解',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              widget.hit.shortTranslation,
              style: const TextStyle(fontSize: 19),
            ),
            const SizedBox(height: 12),
            Text(widget.hit.context),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await widget.controller.save(widget.hit);
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(
                    widget.controller.saved.containsKey(widget.hit.studyKey)
                        ? '已收藏'
                        : '收藏',
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await widget.controller.markKnown(widget.hit.studyKey);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('已认识'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: FutureBuilder<String>(
                  future: answer,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('详解暂未连接，基础译义和收藏仍可使用。'),
                          TextButton(
                            onPressed: () => setState(_explain),
                            child: const Text('重试详解'),
                          ),
                        ],
                      );
                    }
                    return SelectableText(
                      snapshot.data ?? '暂未收到讲解。',
                      style: const TextStyle(fontSize: 16, height: 1.65),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

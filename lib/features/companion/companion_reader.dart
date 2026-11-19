part of 'companion_shell.dart';

class CompanionTextReader extends StatefulWidget {
  const CompanionTextReader({
    super.key,
    required this.controller,
    required this.title,
    this.text,
    this.imagePath,
  });
  final CompanionController controller;
  final String title;
  final String? text;
  final String? imagePath;
  @override
  State<CompanionTextReader> createState() => _CompanionTextReaderState();
}

class _CompanionTextReaderState extends State<CompanionTextReader> {
  String text = '';
  String? error;
  bool loading = true;
  String selected = '';
  bool showImage = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await widget.controller.initialize();
      var content = widget.text ?? '';
      final path = widget.imagePath;
      if (path != null) {
        if (Platform.isIOS || Platform.isMacOS) {
          content =
              await const MethodChannel(
                'lingfer/vision_ocr',
              ).invokeMethod<String>('recognizeText', {'path': path}) ??
              '';
        } else if (Platform.isAndroid) {
          content = await NativeImageOcr.text(path);
        } else {
          throw const AssistantUnavailable('这台设备暂不支持图片识别，请使用粘贴文字。');
        }
      }
      if (content.trim().isEmpty) {
        throw const AssistantUnavailable('没有识别到文字。试试更清晰的截图，或直接粘贴文字。');
      }
      if (!mounted) return;
      setState(() {
        text = content.trim();
        loading = false;
      });
      widget.controller.analyze(text);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is AssistantUnavailable
              ? e.message
              : '这次读取没有完成，请换一张清晰图片，或粘贴文字重试。';
          loading = false;
        });
      }
    }
  }

  void _retry() {
    setState(() {
      loading = true;
      error = null;
    });
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final hits = controller.lastHits;
      final fullTranslation =
          controller.preferences.mode == ReadingMode.translation;
      Widget companion() => fullTranslation
          ? PageTranslationView(
              parts: controller.pageTranslations,
              loading: controller.translating,
              error: controller.error,
              onRetry: () =>
                  controller.analyze(text, reuseLocalSnapshot: false),
            )
          : _words(controller, hits);
      final wide =
          MediaQuery.sizeOf(context).width >= 680 &&
          MediaQuery.textScalerOf(context).scale(16) <= 24;
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: LingferColors.paper,
          appBar: AppBar(
            backgroundColor: LingferColors.paper,
            title: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              ReadingLanguageControl(controller: controller, compact: true),
              if (!fullTranslation)
                TextButton(
                  onPressed: loading
                      ? null
                      : () => _showLevels(context, controller),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_shortLevel(controller.level)),
                      const SizedBox(width: 3),
                      const Icon(Icons.expand_more_rounded, size: 18),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
            ],
            bottom: loading || error != null || wide
                ? null
                : TabBar(
                    indicatorPadding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 6,
                    ),
                    tabs: [
                      const Tab(text: '原文'),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(fullTranslation ? '译文' : '词卡'),
                            const SizedBox(width: 7),
                            Text(
                              fullTranslation ? '' : '${hits.length}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          body: SafeArea(
            top: false,
            child: loading
                ? ListView(
                    children: [
                      _StatePanel(
                        icon: Icons.document_scanner_outlined,
                        title: widget.imagePath == null ? '正在读取文字' : '正在识别截图',
                        message: '识别完成后会显示原文和当前范围的词卡。',
                        loading: true,
                      ),
                    ],
                  )
                : error != null
                ? ListView(
                    children: [
                      _StatePanel(
                        icon: Icons.text_snippet_outlined,
                        title: '这次没有读到内容',
                        message: error!,
                        action: OutlinedButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('重新读取'),
                        ),
                        secondaryAction: TextButton(
                          onPressed: () => _pasteText(context, controller),
                          child: const Text('改用粘贴文字'),
                        ),
                      ),
                    ],
                  )
                : wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: _original(controller)),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 5,
                        child: ColoredBox(
                          color: LingferColors.background,
                          child: companion(),
                        ),
                      ),
                    ],
                  )
                : TabBarView(children: [_original(controller), companion()]),
          ),
        ),
      );
    },
  );

  Widget _original(CompanionController controller) => LayoutBuilder(
    builder: (context, constraints) {
      final inset = constraints.maxWidth < 360 ? 20.0 : 26.0;
      final side = ((constraints.maxWidth - 640) / 2).clamp(
        inset,
        double.infinity,
      );
      return ListView(
        key: const PageStorageKey('reader-original'),
        padding: EdgeInsets.fromLTRB(side, 22, side, 36),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '原文',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: LingferColors.muted,
                  ),
                ),
              ),
              if (widget.imagePath != null)
                TextButton.icon(
                  onPressed: () => setState(() => showImage = !showImage),
                  icon: Icon(
                    showImage
                        ? Icons.visibility_off_outlined
                        : Icons.image_outlined,
                    size: 17,
                  ),
                  label: Text(
                    showImage ? '收起截图' : '查看截图',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (showImage && widget.imagePath != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(widget.imagePath!),
                height: 230,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const _InfoStrip(
                  icon: Icons.broken_image_outlined,
                  text: '截图预览暂不可用，仍可阅读已识别的文字。',
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          AnchoredText(
            text: text,
            hits: controller.lastHits,
            style: LingferType.reading,
            controller: controller,
            child: SelectableText(
              text,
              style: LingferType.reading,
              onSelectionChanged: (selection, _) {
                selected = selection.isValid ? selection.textInside(text) : '';
              },
              contextMenuBuilder: (context, state) =>
                  AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: state.contextMenuAnchors,
                    buttonItems: [
                      ...state.contextMenuButtonItems,
                      ContextMenuButtonItem(
                        label: '语渡讲解',
                        onPressed: () {
                          ContextMenuController.removeAny();
                          if (selected.trim().isNotEmpty) {
                            _showExplanation(context, controller, selected);
                          }
                        },
                      ),
                    ],
                  ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 14),
          const Text(
            '长按原文选句，可查看语境讲解。',
            style: TextStyle(fontSize: 12, color: LingferColors.muted),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _showExplanation(context, controller, text),
              icon: const Icon(CupertinoIcons.text_alignleft, size: 18),
              label: const Text('讲解这段内容'),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'AI 讲解需要联网；基础释义可离线查看。',
            style: TextStyle(fontSize: 12, color: LingferColors.muted),
          ),
        ],
      );
    },
  );

  Widget _words(CompanionController controller, List<VocabularyHit> hits) =>
      ColoredBox(
        color: LingferColors.background,
        child: ListView.builder(
          key: const PageStorageKey('reader-words'),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          itemCount: hits.isEmpty ? 2 : hits.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeading(title: '先看词义，再读原句', trailing: '离线释义'),
                    const SizedBox(height: 7),
                    Text(
                      '找到 ${hits.length} 个匹配词 · ${controller.level.label}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: LingferColors.muted,
                      ),
                    ),
                  ],
                ),
              );
            }
            if (hits.isEmpty) {
              return _StatePanel(
                icon: Icons.check_circle_outline_rounded,
                title: '当前范围没有匹配词',
                message: '可以换一个学习范围，或回到原文选句讲解。',
                action: OutlinedButton(
                  onPressed: () => _showLevels(context, controller),
                  child: const Text('调整学习范围'),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: WordCard(hit: hits[index - 1], controller: controller),
            );
          },
        ),
      );
}

class WordCard extends StatelessWidget {
  const WordCard({
    super.key,
    required this.hit,
    required this.controller,
    this.savedView = false,
  });
  final VocabularyHit hit;
  final CompanionController controller;
  final bool savedView;

  void _toggleSaved(BuildContext context, bool saved) {
    if (saved) {
      unawaited(controller.removeSaved(hit.studyKey));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已移出收藏：${hit.surface}'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => controller.save(hit),
          ),
        ),
      );
    } else {
      unawaited(controller.save(hit));
    }
  }

  void _toggleKnown(BuildContext context, bool known) {
    unawaited(controller.markKnown(hit.studyKey, value: !known));
    if (!known) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已标为熟词：${hit.surface}'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => controller.markKnown(hit.studyKey, value: false),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = controller.saved.containsKey(hit.studyKey);
    final known = controller.known.contains(hit.studyKey);
    return _Surface(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(hit.surface, style: LingferType.word),
                ),
              ),
              IconButton(
                tooltip: saved ? '移出收藏' : '收藏生词',
                isSelected: saved,
                icon: const Icon(CupertinoIcons.bookmark, size: 23),
                selectedIcon: const Icon(
                  CupertinoIcons.bookmark_fill,
                  size: 23,
                ),
                onPressed: () => _toggleSaved(context, saved),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hit.entry.translation,
            style: const TextStyle(fontSize: 16, height: 1.65),
          ),
          if (hit.context.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(left: 12),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: LingferColors.line, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '原句',
                    style: TextStyle(fontSize: 11, color: LingferColors.muted),
                  ),
                  const SizedBox(height: 5),
                  Text.rich(
                    _contextSpan(),
                    style: LingferType.reading.copyWith(
                      fontSize: 15,
                      height: 1.75,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => _showExplanation(
                  context,
                  controller,
                  hit.context.isEmpty ? hit.surface : hit.context,
                  word: hit.entry.word,
                ),
                icon: const Icon(CupertinoIcons.text_alignleft, size: 18),
                label: const Text('语境讲解'),
              ),
              TextButton(
                onPressed: () => _toggleKnown(context, known),
                child: Text(
                  known ? '重新学习' : '标为熟词',
                  style: const TextStyle(color: LingferColors.muted),
                ),
              ),
              if (known && savedView)
                const Text(
                  '已认识',
                  style: TextStyle(fontSize: 11, color: LingferColors.muted),
                ),
            ],
          ),
        ],
      ),
    );
  }

  TextSpan _contextSpan() {
    final matches = RegExp(
      '\\b${RegExp.escape(hit.surface)}\\b',
      caseSensitive: false,
    ).allMatches(hit.context);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      spans.add(TextSpan(text: hit.context.substring(cursor, match.start)));
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: LingferColors.accent,
          ),
        ),
      );
      cursor = match.end;
    }
    spans.add(TextSpan(text: hit.context.substring(cursor)));
    return TextSpan(children: spans);
  }
}

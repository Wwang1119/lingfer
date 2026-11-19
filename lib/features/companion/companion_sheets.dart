part of 'companion_shell.dart';

Future<bool?> _showAndroidReadingNotice(
  BuildContext context, {
  required String title,
  required List<String> paragraphs,
  required String accept,
  required String cancel,
}) => showModalBottomSheet<bool>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 560),
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => _GlassSheet(
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(title: title, showClose: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final paragraph in paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        paragraph,
                        style: const TextStyle(fontSize: 15, height: 1.65),
                      ),
                    ),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: Text(accept),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: Text(cancel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

void _openText(
  BuildContext context,
  CompanionController controller,
  String text,
  String title,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          CompanionTextReader(controller: controller, title: title, text: text),
    ),
  );
}

Future<void> _showLevels(
  BuildContext context,
  CompanionController controller,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 560),
  backgroundColor: Colors.transparent,
  builder: (_) => _GlassSheet(child: _LevelSheet(controller: controller)),
);

class _LevelSheet extends StatefulWidget {
  const _LevelSheet({required this.controller});
  final CompanionController controller;
  @override
  State<_LevelSheet> createState() => _LevelSheetState();
}

class _LevelSheetState extends State<_LevelSheet> {
  VocabularyLevel? saving;
  String? error;
  Future<void> _choose(VocabularyLevel level) async {
    if (saving != null) return;
    setState(() {
      saving = level;
      error = null;
    });
    try {
      await widget.controller.setLevel(level);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = null;
          error = '学习范围暂未同步，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHeader(title: '选择学习范围', subtitle: '按考试词表筛选，随时可以调整。'),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              children: [
                for (final level in VocabularyLevel.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: widget.controller.level == level
                          ? LingferColors.tint
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        enabled: saving == null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        title: Text(
                          _shortLevel(level),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _levelDescription(level),
                          style: const TextStyle(
                            fontSize: 12,
                            color: LingferColors.muted,
                          ),
                        ),
                        trailing: saving == level
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                widget.controller.level == level
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                size: 22,
                                color: widget.controller.level == level
                                    ? LingferColors.accent
                                    : LingferColors.muted,
                              ),
                        onTap: () => _choose(level),
                      ),
                    ),
                  ),
                if (error != null)
                  _InfoStrip(
                    icon: Icons.info_outline_rounded,
                    text: error!,
                    warning: true,
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 16),
                  child: Text(
                    '词表范围不等同于个人水平。认识的词可标为熟词，之后自动略过。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: LingferColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _pasteText(
  BuildContext context,
  CompanionController controller,
) async {
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 680),
    backgroundColor: Colors.transparent,
    builder: (_) => const _GlassSheet(child: _TextInputSheet()),
  );
  if (result != null && context.mounted) {
    _openText(context, controller, result, '文字阅读');
  }
}

class _TextInputSheet extends StatefulWidget {
  const _TextInputSheet();
  @override
  State<_TextInputSheet> createState() => _TextInputSheetState();
}

class _TextInputSheetState extends State<_TextInputSheet> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: (MediaQuery.sizeOf(context).height * .8 - keyboard).clamp(
          240.0,
          680.0,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const _SheetHeader(
                title: '粘贴文字',
                subtitle: '放入想读的段落或句子，可选择翻译语言。',
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: TextField(
                    key: const ValueKey('reading-text-input'),
                    controller: input,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    maxLength: 12000,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(fontSize: 17, height: 1.7),
                    decoration: const InputDecoration(
                      hintText: '在这里粘贴原文…',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: input,
                    builder: (context, value, _) => FilledButton(
                      onPressed: value.text.trim().isEmpty
                          ? null
                          : () => Navigator.pop(context, value.text.trim()),
                      child: const Text('开始阅读'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showPlatformGuide(BuildContext context, bool android) {
  final steps = android
      ? [
          ('选择阅读的 App', '点「开启随屏阅读」，按系统提示授权。如果系统提供「单个应用」，可以只选择正在读的 App。'),
          ('学习辅助', '原词下方的细线标出可以点的词。点原词或短释义看词卡，也可以在词卡里点「翻译这段」。'),
          ('整页对照', '开启联网 AI 后，停稳的页面会提前翻译。轻点段落旁的页边展开译文。滑动正文翻页，滑动译文可继续读长段。点另一段的页边即可换段。'),
          ('结束阅读', '长按书本按钮即可停止读屏。'),
        ]
      : [
          ('开启实时读屏', 'iOS 27 或以上，在语渡点“开启随屏阅读”，再在系统面板选择“共享整个屏幕”。'),
          ('开启画中画预览', '系统共享开始后，先从底部回到语渡，点“画中画预览”，再切换到阅读 App。页面变化后会自动更新。'),
          ('查看完整词卡或停止', '画中画显示当前 3 个词义。返回语渡可看全部原句、讲解与收藏；点“停止”结束捕获。收起画中画不会停止读屏。'),
          ('打开系统分享', '在 Safari 打开网页，或选中一段文字，点系统分享按钮。'),
          ('选择“语渡阅读”', '首次使用可在分享菜单的“更多”中启用。'),
          ('直接查看词卡', '在分享面板选择学习范围、看释义和收藏；需要时再请求讲解。'),
          ('其他 App 用截图', '无法分享文字时，截屏后分享给语渡，或回到语渡选择截图。'),
        ];
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (context) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHeader(title: android ? '随屏阅读使用方法' : 'iOS 阅读使用方法'),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 27,
                              height: 27,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: LingferColors.tint,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: LingferColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    steps[i].$1,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    steps[i].$2,
                                    style: const TextStyle(
                                      color: LingferColors.muted,
                                      height: 1.7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    _InfoStrip(
                      icon: Icons.info_outline_rounded,
                      text: android
                          ? '受保护页面可能无法识别；锁屏或系统结束会话后，需要重新开启。'
                          : '实时读屏需要系统授权；较早的 iOS 可继续用分享或截图阅读。受保护页面可能无法读取。',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showExplanation(
  BuildContext context,
  CompanionController controller,
  String text, {
  String? word,
}) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 720),
    backgroundColor: Colors.transparent,
    builder: (_) => _GlassSheet(
      child: _ExplanationSheet(controller: controller, text: text, word: word),
    ),
  );
}

class _ExplanationSheet extends StatefulWidget {
  const _ExplanationSheet({
    required this.controller,
    required this.text,
    this.word,
  });
  final CompanionController controller;
  final String text;
  final String? word;
  @override
  State<_ExplanationSheet> createState() => _ExplanationSheetState();
}

class _ExplanationSheetState extends State<_ExplanationSheet> {
  late Future<String> request;
  @override
  void initState() {
    super.initState();
    request = _request();
  }

  Future<String> _request() => widget.controller.assistant.explain(
    text: widget.text,
    word: widget.word,
    level: widget.controller.level.label,
    sourceLanguage: widget.controller.preferences.source,
    targetLanguage: widget.controller.preferences.target,
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(
            title: '语境讲解',
            subtitle: widget.word == null
                ? '结合所选原文理解'
                : '结合原句理解 ${widget.word}',
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '原文',
                    style: TextStyle(color: LingferColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    widget.text,
                    style: LingferType.reading.copyWith(
                      fontSize: 17,
                      height: 1.7,
                    ),
                  ),
                  if (widget.word != null) ...[
                    const SizedBox(height: 14),
                    Builder(
                      builder: (context) {
                        final entry = widget.controller.engine?.lookup(
                          widget.word!,
                        );
                        return entry == null
                            ? const SizedBox.shrink()
                            : _InfoStrip(
                                icon: Icons.menu_book_outlined,
                                text: '基础释义 · ${entry.translation}',
                              );
                      },
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Divider(),
                  const SizedBox(height: 22),
                  const Text(
                    'AI 讲解',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: LingferColors.accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<String>(
                    future: request,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '正在结合原文讲解…',
                                  style: TextStyle(color: LingferColors.muted),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InfoStrip(
                              icon: Icons.cloud_off_outlined,
                              warning: true,
                              text: snapshot.error is AssistantUnavailable
                                  ? (snapshot.error as AssistantUnavailable)
                                        .message
                                  : '这次讲解未完成，请检查网络后重试。',
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => setState(() {
                                request = _request();
                              }),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('重新请求讲解'),
                            ),
                          ],
                        );
                      }
                      return SelectableText(
                        snapshot.data ?? '',
                        style: const TextStyle(fontSize: 16, height: 1.85),
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    '讲解仅依据这段原文。基础释义保留在本机，离线可用。',
                    style: TextStyle(fontSize: 12, color: LingferColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

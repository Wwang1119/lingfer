part of 'companion_shell.dart';

/// One scrolling column, with a bounded line length on tablets and foldables.
class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.children,
    this.maxWidth = 1040,
    this.scrollKey,
  });
  final List<Widget> children;
  final double maxWidth;
  final Key? scrollKey;
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth < 360
            ? 16.0
            : constraints.maxWidth >= 700
            ? 32.0
            : 22.0;
        final side = ((constraints.maxWidth - maxWidth) / 2).clamp(
          inset,
          double.infinity,
        );
        return ListView(
          key: scrollKey,
          padding: EdgeInsets.fromLTRB(
            side,
            18,
            side,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: children,
        );
      },
    ),
  );
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      Text(subtitle, style: const TextStyle(color: LingferColors.muted)),
    ],
  );
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Material(
    color: LingferColors.paper,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.trailing});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: LingferType.heading.copyWith(fontSize: 20)),
      ),
      if (trailing != null)
        Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text, required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: LingferColors.muted),
      const SizedBox(width: 5),
      Text(
        text,
        style: const TextStyle(fontSize: 12, color: LingferColors.muted),
      ),
    ],
  );
}

class _ReadingContextBar extends StatelessWidget {
  const _ReadingContextBar({required this.controller});
  final CompanionController controller;
  @override
  Widget build(BuildContext context) => LingferGlassSurface(
    radius: 26,
    shadow: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Row(
        children: [
          Semantics(
            label: controller.preferences.mode == ReadingMode.translation
                ? '阅读方式'
                : '学习范围',
            child: TextButton(
              key: const ValueKey('learning-range'),
              onPressed: controller.loading
                  ? null
                  : () => controller.preferences.mode == ReadingMode.translation
                        ? showReadingPreferences(context, controller)
                        : controller.usesEnglishScope
                        ? _showLevels(context, controller)
                        : showReadingPreferences(context, controller),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    controller.preferences.mode == ReadingMode.translation
                        ? '整页对照'
                        : controller.usesEnglishScope
                        ? _shortLevel(controller.level)
                        : controller.preferences.difficulty.label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: LingferColors.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    CupertinoIcons.chevron_down,
                    size: 10,
                    color: LingferColors.muted,
                  ),
                ],
              ),
            ),
          ),
          Container(height: 16, width: .5, color: LingferColors.line),
          Expanded(
            child: TextButton(
              onPressed: () => showReadingPreferences(context, controller),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      controller.preferences.directionLabel,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: LingferColors.muted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    CupertinoIcons.chevron_down,
                    size: 10,
                    color: LingferColors.muted,
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

class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.controller, this.embedded = false});
  final CompanionController controller;
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    if (controller.preferences.mode == ReadingMode.translation) {
      return ListTile(
        title: const Text('整页对照'),
        subtitle: const Text('完整译文 · 联网 · 不筛难度'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showReadingPreferences(context, controller),
      );
    }
    if (!controller.usesEnglishScope) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: GeneralDifficultyControl(controller: controller),
      );
    }
    final tile = ListTile(
      key: const ValueKey('learning-range'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: const Icon(
        CupertinoIcons.textformat_abc,
        color: LingferColors.accent,
        size: 23,
      ),
      title: const Text(
        '学习范围',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${_shortLevel(controller.level)} · ${_levelDescription(controller.level)}',
        style: const TextStyle(fontSize: 12, color: LingferColors.muted),
      ),
      trailing: const Icon(
        CupertinoIcons.chevron_up_chevron_down,
        size: 16,
        color: LingferColors.muted,
      ),
      onTap: controller.loading ? null : () => _showLevels(context, controller),
    );
    return embedded ? tile : _Surface(padding: EdgeInsets.zero, child: tile);
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({
    required this.icon,
    required this.text,
    this.warning = false,
  });
  final IconData icon;
  final String text;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: warning ? LingferColors.warningSurface : LingferColors.tint,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: warning ? LingferColors.warning : LingferColors.accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13, height: 1.6)),
        ),
      ],
    ),
  );
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    this.action,
    this.secondaryAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final bool loading;
  final Widget? action;
  final Widget? secondaryAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, color: LingferColors.muted, size: 30),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: LingferColors.muted,
            fontSize: 14,
            height: 1.7,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
        if (secondaryAction != null) ...[
          const SizedBox(height: 6),
          secondaryAction!,
        ],
      ],
    ),
  );
}

class _GlassSheet extends StatelessWidget {
  const _GlassSheet({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LingferGlassSurface(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
    shadow: false,
    child: child,
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 10),
      ExcludeSemantics(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: LingferColors.line,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LingferType.heading.copyWith(fontSize: 23),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x0D747480),
                foregroundColor: LingferColors.muted,
              ),
              icon: const Icon(CupertinoIcons.xmark, size: 18),
            ),
          ],
        ),
      ),
      const Divider(indent: 22, endIndent: 22),
    ],
  );
}

String _shortLevel(VocabularyLevel level) => switch (level) {
  VocabularyLevel.zhongkao => '中考',
  VocabularyLevel.gaokao => '高考',
  VocabularyLevel.cet4 => '四级',
  VocabularyLevel.cet6 => '六级',
  VocabularyLevel.kaoyan => '考研',
  VocabularyLevel.ielts => '雅思',
  VocabularyLevel.toefl => '托福',
};

String _levelDescription(VocabularyLevel level) => switch (level) {
  VocabularyLevel.zhongkao => '初中常见词汇',
  VocabularyLevel.gaokao => '高中考试词汇',
  VocabularyLevel.cet4 => '大学英语四级词汇',
  VocabularyLevel.cet6 => '大学英语六级词汇',
  VocabularyLevel.kaoyan => '研究生英语考试词汇',
  VocabularyLevel.ielts => '雅思核心词汇',
  VocabularyLevel.toefl => '托福高频词汇',
};

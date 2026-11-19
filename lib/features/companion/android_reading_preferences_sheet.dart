part of 'reading_controls.dart';

enum _LanguageRole { source, target }

class _AndroidReadingPreferencesSheet extends StatefulWidget {
  const _AndroidReadingPreferencesSheet({required this.controller});
  final CompanionController controller;

  @override
  State<_AndroidReadingPreferencesSheet> createState() =>
      _AndroidReadingPreferencesSheetState();
}

class _AndroidReadingPreferencesSheetState
    extends State<_AndroidReadingPreferencesSheet> {
  _LanguageRole? role;
  ReadingPreferences get preferences => widget.controller.preferences;

  void showRole(_LanguageRole? next) => setState(() => role = next);

  void update(ReadingPreferences value) {
    widget.controller.setReadingPreferences(value);
    // The controller applies the choice synchronously, then saves/syncs it.
    setState(() {});
  }

  void chooseLanguage(ReadingLanguage language) {
    final old = preferences;
    final fallback = language == ReadingLanguage.zh
        ? ReadingLanguage.en
        : ReadingLanguage.zh;
    if (role == _LanguageRole.source && old.source != language) {
      update(
        old.copyWith(
          source: language,
          target: old.target == language ? fallback : old.target,
        ),
      );
    } else if (role == _LanguageRole.target && old.target != language) {
      update(
        old.copyWith(
          target: language,
          source: old.source == language ? fallback : old.source,
        ),
      );
    }
    showRole(null);
  }

  void swap() {
    final old = preferences;
    final target = old.source == ReadingLanguage.auto
        ? (old.target == ReadingLanguage.en
              ? ReadingLanguage.zh
              : ReadingLanguage.en)
        : old.source;
    update(old.copyWith(source: old.target, target: target));
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: role == null,
    onPopInvokedWithResult: (popped, _) {
      if (!popped && role != null) showRole(null);
    },
    child: LayoutBuilder(
      builder: (context, bounds) {
        final inset = bounds.maxWidth < 360 ? 16.0 : 24.0;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: bounds.maxHeight * .94),
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7D8D0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      role == null ? inset : inset - 8,
                      10,
                      inset - 4,
                      12,
                    ),
                    child: Row(
                      children: [
                        if (role != null)
                          IconButton(
                            tooltip: '返回语言设置',
                            icon: const Icon(Icons.arrow_back_rounded),
                            onPressed: () => showRole(null),
                          ),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              switch (role) {
                                _LanguageRole.source => '原文语言',
                                _LanguageRole.target => '译文语言',
                                null => '语言与阅读方式',
                              },
                              style: LingferType.brandHeading.copyWith(
                                fontSize: 27,
                                height: 1.24,
                              ),
                            ),
                          ),
                        ),
                        if (role == null)
                          IconButton(
                            tooltip: '关闭语言设置',
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      key: PageStorageKey(
                        'reading-preferences-${role?.name ?? 'overview'}',
                      ),
                      padding: EdgeInsets.fromLTRB(inset, 0, inset, 22),
                      child: role == null ? overview(context) : languageList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget overview(BuildContext context) {
    final p = preferences;
    final learning = p.mode == ReadingMode.learning;
    final androidCapture = widget.controller.bridge.supported;
    final englishScope = widget.controller.usesEnglishScope;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFE8EEEA),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final stacked =
                  bounds.maxWidth <
                  MediaQuery.textScalerOf(context).scale(16) * 17;
              final source = languageRole(_LanguageRole.source, p.source);
              final target = languageRole(_LanguageRole.target, p.target);
              final exchange = IconButton(
                tooltip: '交换翻译方向',
                onPressed: swap,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFAFBF7),
                  foregroundColor: LingferColors.accent,
                ),
                icon: Icon(
                  stacked ? Icons.swap_vert_rounded : Icons.swap_horiz_rounded,
                  size: 21,
                ),
              );
              if (stacked) {
                return Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [source, target],
                        ),
                      ),
                      exchange,
                    ],
                  ),
                );
              }
              return Row(
                children: [
                  Expanded(child: source),
                  exchange,
                  Expanded(child: target),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        sectionTitle('阅读方式'),
        const SizedBox(height: 8),
        for (final mode in ReadingMode.values)
          _ReadingChoiceRow(
            key: ValueKey('reading-mode-${mode.name}'),
            title: mode.label,
            selected: p.mode == mode,
            onTap: () {
              if (p.mode != mode) update(p.copyWith(mode: mode));
            },
          ),
        const SizedBox(height: 8),
        if (!learning) note('逐段翻译全部原文，已完成的译文可在重试时保留。'),
        if (learning &&
            p.source == ReadingLanguage.auto &&
            p.target == ReadingLanguage.zh)
          note('遇到中文时，按所选英语词表提示对应英文。')
        else if (learning && englishScope)
          note('英语词汇按所选考试范围筛选。'),
        if (learning && !englishScope) ...[
          const SizedBox(height: 12),
          sectionTitle('通用学习难度（参考）'),
          const SizedBox(height: 6),
          for (final level in GeneralDifficulty.values)
            _ReadingChoiceRow(
              key: ValueKey('reading-difficulty-${level.name}'),
              title: level.label,
              contextLabel: level.reference,
              selected: p.difficulty == level,
              onTap: () {
                if (p.difficulty != level) {
                  update(p.copyWith(difficulty: level));
                }
              },
            ),
        ],
        if (androidCapture) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            key: const ValueKey('reading-automatic'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              '页面变化时自动更新',
              style: LingferType.interfaceHeading.copyWith(fontSize: 16),
            ),
            subtitle: note('读屏时生效，可在悬浮菜单暂停。'),
            value: p.automatic,
            onChanged: (value) => update(p.copyWith(automatic: value)),
          ),
        ],
        const SizedBox(height: 12),
        note(
          learning
              ? '英译中基础释义可离线，其他方向由联网 AI 处理对应文字，图片留在本机。'
              : '允许联网 AI 后，页面停稳时会发送可见段落文字预译。轻点段落旁的页边看译文，图片留在本机。',
        ),
      ],
    );
  }

  Widget languageRole(_LanguageRole which, ReadingLanguage language) {
    final label = which == _LanguageRole.source ? '原文语言' : '译文语言';
    return InkWell(
      key: ValueKey('reading-${which.name}-language'),
      onTap: () => showRole(which),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 8, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: LingferType.interfaceText.copyWith(
                color: const Color(0xFF50655F),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Flexible(
                  child: Text(
                    language.label,
                    style: LingferType.interfaceHeading.copyWith(fontSize: 19),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.expand_more_rounded,
                  size: 17,
                  color: LingferColors.accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget sectionTitle(String label) => Semantics(
    header: true,
    child: Text(
      label,
      style: LingferType.interfaceHeading.copyWith(fontSize: 17),
    ),
  );
  Widget note(String text) => Text(
    text,
    style: LingferType.interfaceText.copyWith(
      fontSize: 13,
      height: 1.55,
      color: const Color(0xFF54635F),
    ),
  );

  Widget languageList() {
    final selected = role == _LanguageRole.source
        ? preferences.source
        : preferences.target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (role == _LanguageRole.source && widget.controller.bridge.supported)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
            child: note('日语、韩语和印地语请手动选择。'),
          ),
        for (final language in ReadingLanguage.values.where(
          (lang) =>
              role == _LanguageRole.source || lang != ReadingLanguage.auto,
        ))
          _ReadingChoiceRow(
            key: ValueKey('reading-language-${language.code}'),
            title: language.label,
            contextLabel: switch (language) {
              ReadingLanguage.en => 'English',
              ReadingLanguage.ja => '日本語',
              ReadingLanguage.ko => '한국어',
              ReadingLanguage.fr => 'Français',
              ReadingLanguage.de => 'Deutsch',
              ReadingLanguage.es => 'Español',
              ReadingLanguage.pt => 'Português',
              ReadingLanguage.it => 'Italiano',
              ReadingLanguage.hi => 'हिन्दी',
              _ => null,
            },
            selected: language == selected,
            onTap: () => chooseLanguage(language),
          ),
      ],
    );
  }
}

class _ReadingChoiceRow extends StatelessWidget {
  const _ReadingChoiceRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.contextLabel,
  });
  final String title;
  final String? contextLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? const Color(0xFFE9EEEA) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 9,
                    runSpacing: 2,
                    children: [
                      Text(
                        title,
                        style: LingferType.interfaceText.copyWith(
                          fontSize: 16,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      if (contextLabel != null)
                        Text(
                          contextLabel!,
                          style: LingferType.interfaceText.copyWith(
                            fontSize: 13,
                            color: const Color(0xFF596660),
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.check_rounded,
                      color: LingferColors.accent,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../features/companion/lingfer_glass.dart';
import '../features/companion/lingfer_theme.dart';
import '../models/vocabulary_level.dart';

/// Keep the existing pagination metrics while using one quiet annotation ink.
abstract final class BookReaderTypography {
  static TextStyle body({required double size, required Color ink}) =>
      TextStyle(
        color: ink,
        fontSize: size,
        height: 1.6,
        letterSpacing: 0.5,
        decoration: TextDecoration.none,
        fontFamilyFallback: const [
          '.SF UI Text',
          '.SF Pro Text',
          'PingFang SC',
        ],
      );

  static Color annotationInk(Color ink) => ink.computeLuminance() > 0.5
      ? const Color(0xFFB1CED2)
      : LingferColors.accent;

  static TextStyle annotation({required double size, required Color ink}) =>
      body(
        size: (size - 2).clamp(12, 30).toDouble(),
        ink: annotationInk(ink),
      ).copyWith(fontWeight: FontWeight.w500);
}

class BookReaderChoice<T> {
  const BookReaderChoice({
    required this.value,
    required this.label,
    this.detail,
  });
  final T value;
  final String label;
  final String? detail;
}

Future<T?> showBookReaderChoices<T>(
  BuildContext context, {
  required String title,
  required T selected,
  required List<BookReaderChoice<T>> choices,
  String? subtitle,
  bool isDark = false,
}) => showCupertinoModalPopup<T>(
  context: context,
  builder: (sheetContext) => BookReaderChoices<T>(
    title: title,
    selected: selected,
    choices: choices,
    subtitle: subtitle,
    isDark: isDark,
    onClose: () => Navigator.pop(sheetContext),
    onSelected: (value) => Navigator.pop(sheetContext, value),
  ),
);

/// A bounded, scrollable paper list shared by reading settings menus.
class BookReaderChoices<T> extends StatelessWidget {
  const BookReaderChoices({
    super.key,
    required this.title,
    required this.selected,
    required this.choices,
    required this.onSelected,
    required this.onClose,
    this.subtitle,
    this.isDark = false,
  });

  final String title;
  final T selected;
  final List<BookReaderChoice<T>> choices;
  final ValueChanged<T> onSelected;
  final VoidCallback onClose;
  final String? subtitle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? const Color(0xFFF4F4F0) : LingferColors.ink;
    final muted = isDark ? const Color(0xFFB2BCBD) : LingferColors.muted;
    final accent = isDark ? const Color(0xFFB1CED2) : LingferColors.accent;
    final line = isDark ? const Color(0xFF404A4B) : LingferColors.line;
    final hasSubtitle = subtitle?.trim().isNotEmpty == true;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: BookReaderControlSurface(
                isDark: isDark,
                radius: 22,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: LingferType.interfaceHeading.copyWith(
                                  fontSize: 18,
                                  color: ink,
                                ),
                              ),
                            ),
                            Semantics(
                              label: '关闭$title',
                              button: true,
                              child: CupertinoButton(
                                minimumSize: const Size(48, 48),
                                padding: EdgeInsets.zero,
                                onPressed: onClose,
                                child: Icon(
                                  CupertinoIcons.xmark,
                                  color: muted,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(height: 1, color: line),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          itemCount: choices.length + (hasSubtitle ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(height: 2),
                          itemBuilder: (context, index) {
                            if (hasSubtitle && index == 0) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  6,
                                  10,
                                  8,
                                ),
                                child: Text(
                                  subtitle!,
                                  style: LingferType.interfaceText.copyWith(
                                    fontSize: 12,
                                    color: muted,
                                  ),
                                ),
                              );
                            }
                            final choice =
                                choices[index - (hasSubtitle ? 1 : 0)];
                            final active = choice.value == selected;
                            return Semantics(
                              selected: active,
                              child: CupertinoButton(
                                key: ValueKey('book-choice-${choice.value}'),
                                minimumSize: const Size(48, 48),
                                padding: EdgeInsets.zero,
                                onPressed: () => onSelected(choice.value),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 48,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? (isDark
                                              ? const Color(0xFF344347)
                                              : LingferColors.tint)
                                        : null,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              choice.label,
                                              style: LingferType.interfaceText
                                                  .copyWith(
                                                    fontSize: 15,
                                                    height: 1.3,
                                                    fontWeight: active
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                    color: active
                                                        ? accent
                                                        : ink,
                                                  ),
                                            ),
                                            if (choice.detail != null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                choice.detail!,
                                                style: LingferType.interfaceText
                                                    .copyWith(
                                                      fontSize: 12,
                                                      height: 1.35,
                                                      color: muted,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 20,
                                        child: active
                                            ? Icon(
                                                CupertinoIcons.check_mark,
                                                color: accent,
                                                size: 17,
                                              )
                                            : null,
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
  }
}

class BookReaderControlSurface extends StatelessWidget {
  const BookReaderControlSurface({
    super.key,
    required this.child,
    this.isDark = false,
    this.radius = 28,
  });
  final Widget child;
  final bool isDark;
  final double radius;

  @override
  Widget build(BuildContext context) => isDark
      ? DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xED252D2F),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFF465254)),
          ),
          child: child,
        )
      : LingferGlassSurface(radius: radius, child: child);
}

/// A small reading control with the same bounded glass as the home controls.
class BookReaderActionChip extends StatelessWidget {
  const BookReaderActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.trailingIcon,
    this.semanticLabel,
    this.isDark = false,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final IconData? trailingIcon;
  final String? semanticLabel;
  final bool isDark;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? const Color(0xFFF4F4F0) : LingferColors.ink;
    final accent = isDark ? const Color(0xFFB1CED2) : LingferColors.accent;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: active ? accent : ink),
            const SizedBox(width: 8),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                label,
                style: LingferType.interfaceText.copyWith(
                  color: active ? accent : ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, size: 13, color: accent),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      label: semanticLabel,
      selected: active ? true : null,
      child: CupertinoButton(
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: isDark
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF344347)
                      : const Color(0xED2B3436),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF465254)),
                ),
                child: content,
              )
            : LingferGlassSurface(radius: 24, shadow: false, child: content),
      ),
    );
  }
}

/// One range summary shared by book, PDF and scanned-text selection panels.
class BookReaderRangeSelector extends StatelessWidget {
  const BookReaderRangeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final VocabularyLevel selected;
  final ValueChanged<VocabularyLevel> onSelected;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    heightFactor: 1,
    child: BookReaderActionChip(
      key: const ValueKey('book-reading-range-summary'),
      icon: CupertinoIcons.slider_horizontal_3,
      label: selected.label,
      semanticLabel: '学习范围',
      trailingIcon: CupertinoIcons.chevron_down,
      onPressed: () async {
        final value = await showBookReaderChoices<VocabularyLevel>(
          context,
          title: '学习范围',
          selected: selected,
          choices: [
            for (final level in VocabularyLevel.values)
              BookReaderChoice(value: level, label: level.label),
          ],
        );
        if (value != null && context.mounted) onSelected(value);
      },
    ),
  );
}

class BookReadFailureView extends StatelessWidget {
  const BookReadFailureView({
    super.key,
    required this.title,
    required this.message,
    required this.onBack,
    required this.onRetry,
    this.isDark = false,
  });
  final String title;
  final String message;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? const Color(0xFFF4F4F0) : LingferColors.ink;
    final muted = isDark ? const Color(0xFFB2BCBD) : LingferColors.muted;
    final accent = isDark ? const Color(0xFFB1CED2) : LingferColors.accent;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onBack,
              child: Text('返回', style: TextStyle(color: accent)),
            ),
            const SizedBox(height: 36),
            Text(
              '暂时无法打开',
              style: LingferType.interfaceHeading.copyWith(
                color: ink,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(color: ink, fontSize: 17, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: muted, fontSize: 15, height: 1.6),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                CupertinoButton(
                  color: accent,
                  onPressed: onRetry,
                  child: Text(
                    '重新读取',
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFF182324)
                          : CupertinoColors.white,
                    ),
                  ),
                ),
                CupertinoButton(
                  onPressed: onBack,
                  child: Text('返回重新导入', style: TextStyle(color: accent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

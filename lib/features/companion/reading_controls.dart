import 'dart:io';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'reading_preferences.dart';
import 'lingfer_theme.dart';
import 'lingfer_glass.dart';

class ReadingLanguageControl extends StatelessWidget {
  const ReadingLanguageControl({
    super.key,
    required this.controller,
    this.compact = false,
  });
  final CompanionController controller;
  final bool compact;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (compact) {
        return IconButton(
          tooltip: '语言与自动更新',
          icon: const Icon(Icons.translate_rounded),
          onPressed: () => showReadingPreferences(context, controller),
        );
      }
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        leading: const Icon(
          Icons.translate_rounded,
          color: LingferColors.accent,
          size: 22,
        ),
        title: Text(
          controller.preferences.directionLabel,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          controller.preferences.mode == ReadingMode.translation
              ? '完整译文 · 不按难度筛选'
              : Platform.isAndroid && controller.preferences.automatic
              ? '原词定位 · 页面变化后自动更新'
              : '在原文位置查看译义',
          style: const TextStyle(fontSize: 12, color: LingferColors.muted),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: LingferColors.muted,
          size: 20,
        ),
        onTap: () => showReadingPreferences(context, controller),
      );
    },
  );
}

Future<void> showReadingPreferences(
  BuildContext context,
  CompanionController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => GlassSurface(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          22,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '语言与阅读方式',
                    style: TextStyle(
                      fontFamily: LingferType.interfaceFontFamily,
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭语言设置',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ReadingMode>(
              initialValue: controller.preferences.mode,
              decoration: const InputDecoration(labelText: '阅读方式'),
              items: ReadingMode.values
                  .map(
                    (mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                  )
                  .toList(),
              onChanged: (mode) {
                if (mode != null) {
                  controller.setReadingPreferences(
                    controller.preferences.copyWith(mode: mode),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            if (controller.preferences.mode == ReadingMode.translation)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('逐段对照原文和完整译文，需要联网；不按难度筛选，也不排除熟词。'),
              ),
            if (controller.preferences.source == ReadingLanguage.auto &&
                controller.preferences.mode == ReadingMode.learning &&
                controller.preferences.target == ReadingLanguage.zh)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('自动识别到中文时，按所选英语词表提示英文词汇；其他语言译为中文。'),
              ),
            DropdownButtonFormField<ReadingLanguage>(
              key: ValueKey('source-${controller.preferences.source.code}'),
              initialValue: controller.preferences.source,
              decoration: const InputDecoration(labelText: '原文语言'),
              items: ReadingLanguage.values
                  .map((l) => DropdownMenuItem(value: l, child: Text(l.label)))
                  .toList(),
              onChanged: (source) {
                if (source == null) return;
                final target = source == controller.preferences.target
                    ? (source == ReadingLanguage.zh
                          ? ReadingLanguage.en
                          : ReadingLanguage.zh)
                    : controller.preferences.target;
                controller.setReadingPreferences(
                  controller.preferences.copyWith(
                    source: source,
                    target: target,
                  ),
                );
              },
            ),
            Align(
              alignment: Alignment.center,
              child: IconButton(
                tooltip: '交换翻译方向',
                icon: const Icon(Icons.swap_vert_rounded),
                onPressed: () {
                  final old = controller.preferences;
                  controller.setReadingPreferences(
                    old.copyWith(
                      source: old.target,
                      target: old.source == ReadingLanguage.auto
                          ? ReadingLanguage.en
                          : old.source,
                    ),
                  );
                },
              ),
            ),
            DropdownButtonFormField<ReadingLanguage>(
              key: ValueKey('target-${controller.preferences.target.code}'),
              initialValue: controller.preferences.target,
              decoration: const InputDecoration(labelText: '译文语言'),
              items: ReadingLanguage.values
                  .where((l) => l != ReadingLanguage.auto)
                  .map((l) => DropdownMenuItem(value: l, child: Text(l.label)))
                  .toList(),
              onChanged: (target) {
                if (target == null) return;
                final source = target == controller.preferences.source
                    ? (target == ReadingLanguage.zh
                          ? ReadingLanguage.en
                          : ReadingLanguage.zh)
                    : controller.preferences.source;
                controller.setReadingPreferences(
                  controller.preferences.copyWith(
                    source: source,
                    target: target,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            if (controller.preferences.mode == ReadingMode.learning) ...[
              if (!controller.usesEnglishScope) ...[
                const Text('通用学习难度（参考分级）'),
                const SizedBox(height: 10),
                GeneralDifficultyControl(controller: controller),
                const SizedBox(height: 12),
              ] else
                const Text('英语相关方向会按所选考试范围筛词。中文→英语会校验对应的英文词汇。'),
            ],
            if (Platform.isAndroid)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('页面变化时自动更新'),
                subtitle: const Text('在你开启读屏会话后生效。点悬浮按钮可暂停，长按可停止。'),
                value: controller.preferences.automatic,
                onChanged: (value) => controller.setReadingPreferences(
                  controller.preferences.copyWith(automatic: value),
                ),
              ),
            const SizedBox(height: 8),
            if (Platform.isAndroid)
              Text(
                '日语、韩语和印地语的图片或页面，请先选好原文语言。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Text(
              controller.preferences.mode == ReadingMode.translation
                  ? '整页翻译需要联网，仅发送对应文字；图片留在本机，已完成译文会保留供重试。'
                  : '英语→中文的基础释义可离线使用。其他翻译方向需要联网，对应文字会发送给 AI 服务，图片留在本机。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  ),
);

class GeneralDifficultyControl extends StatelessWidget {
  const GeneralDifficultyControl({super.key, required this.controller});
  final CompanionController controller;
  @override
  Widget build(BuildContext context) => SegmentedButton<GeneralDifficulty>(
    segments: GeneralDifficulty.values
        .map((v) => ButtonSegment(value: v, label: Text(v.label)))
        .toList(),
    selected: {controller.preferences.difficulty},
    onSelectionChanged: (selected) => controller.setReadingPreferences(
      controller.preferences.copyWith(difficulty: selected.single),
    ),
  );
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.radius = 28});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) =>
      LingferGlassSurface(radius: radius, child: child);
}

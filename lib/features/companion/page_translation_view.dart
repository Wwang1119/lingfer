import 'package:flutter/material.dart';
import 'lingfer_theme.dart';
import 'page_translation.dart';

class PageTranslationView extends StatelessWidget {
  const PageTranslationView({
    super.key,
    required this.parts,
    required this.loading,
    required this.error,
    required this.onRetry,
  });
  final List<TranslatedParagraph> parts;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('page-translation'),
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
    children: [
      Text('整页对照', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        '已翻译 ${parts.where((p) => p.translation != null).length} / ${parts.length} 段 · 需要联网',
        style: const TextStyle(color: LingferColors.muted),
      ),
      if (loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: LinearProgressIndicator(),
        ),
      if (error != null) ...[
        const SizedBox(height: 12),
        Text(error!, style: const TextStyle(color: LingferColors.warning)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: loading ? null : onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试未完成段落'),
          ),
        ),
      ],
      for (final p in parts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                p.source,
                style: const TextStyle(fontSize: 16, height: 1.7),
              ),
              const SizedBox(height: 12),
              SelectableText(
                p.translation ?? '尚未翻译',
                style: TextStyle(
                  fontSize: 17,
                  height: 1.8,
                  color: p.translation == null
                      ? LingferColors.muted
                      : LingferColors.accent,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
            ],
          ),
        ),
      if (!loading && error == null && parts.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('没有可翻译的文字，请回到原文检查。'),
        ),
    ],
  );
}

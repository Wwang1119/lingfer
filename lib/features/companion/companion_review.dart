import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'lingfer_theme.dart';
import 'review_schedule.dart';
import 'vocabulary_engine.dart';

class CompanionReviewPage extends StatefulWidget {
  const CompanionReviewPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<CompanionReviewPage> createState() => _CompanionReviewPageState();
}

class _CompanionReviewPageState extends State<CompanionReviewPage> {
  late final List<VocabularyHit> queue = widget.controller
      .dueWords()
      .take(20)
      .toList();
  int index = 0;
  bool revealed = false;
  bool saving = false;
  String? error;
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> grade(RecallRating rating) async {
    if (saving || index >= queue.length) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.gradeReview(queue[index].studyKey, rating);
      if (mounted) {
        setState(() {
          index++;
          revealed = false;
        });
      }
      if (mounted && scroll.hasClients) scroll.jumpTo(0);
    } catch (_) {
      if (mounted) setState(() => error = '复习进度暂未保存，请重试。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = index >= queue.length;
    final hit = done ? null : queue[index];
    final english =
        hit != null &&
        (hit.sourceLanguage == 'en' || hit.targetLanguage == 'en');
    final meaning = hit == null
        ? ''
        : english
        ? widget.controller.engine?.lookup(hit.entry.word)?.translation ??
              hit.entry.translation
        : hit.entry.translation;
    return Scaffold(
      appBar: AppBar(title: const Text('生词复习')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  done
                      ? '本轮已完成 ${queue.length} 个'
                      : '${index + 1} / ${queue.length}',
                  style: const TextStyle(color: LingferColors.muted),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: queue.isEmpty ? 1 : index / queue.length,
                ),
                const SizedBox(height: 28),
                if (hit == null) ...[
                  const Icon(
                    Icons.check_circle_outline,
                    color: LingferColors.accent,
                    size: 40,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '这轮复习完成了',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '认识的词会隔一段时间再出现；没记住的词，10 分钟后再复习。阅读中的熟词排除仍由你手动决定。',
                    style: TextStyle(color: LingferColors.muted),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('回到生词本'),
                  ),
                ] else ...[
                  Text(
                    english ? hit.entry.word : hit.surface,
                    style: const TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 34,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!revealed) ...[
                    const Text(
                      '先想一想它的意思，再翻看答案。',
                      style: TextStyle(color: LingferColors.muted),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: () => setState(() => revealed = true),
                      child: const Text('查看答案'),
                    ),
                  ] else ...[
                    SelectableText(
                      meaning,
                      style: const TextStyle(fontSize: 18, height: 1.7),
                    ),
                    if (hit.context.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(),
                      ),
                      const Text(
                        '遇见它的原句',
                        style: TextStyle(color: LingferColors.muted),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        hit.context,
                        style: const TextStyle(fontSize: 18, height: 1.8),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text(
                      '这次记得怎么样？',
                      style: TextStyle(color: LingferColors.muted),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => grade(RecallRating.again),
                          child: const Text('没记住'),
                        ),
                        FilledButton(
                          onPressed: saving
                              ? null
                              : () => grade(RecallRating.remembered),
                          child: const Text('认识'),
                        ),
                        OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => grade(RecallRating.easy),
                          child: const Text('很熟悉'),
                        ),
                      ],
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(error!),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

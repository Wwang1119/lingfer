import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../../app/lens_state.dart';
import '../../models/book.dart';
import '../../models/vocabulary_level.dart';
import '../browser/browser_screen.dart';
import '../../screens/reading/reading_screen.dart';
import '../../widgets/book_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final state = LensScope.of(context);
    final size = MediaQuery.sizeOf(context);
    final columns = size.width >= 900
        ? 4
        : size.width >= 650
            ? 3
            : 2;

    const pageBg = Color(0xFFF2F2F7);

    return CupertinoPageScaffold(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: pageBg),
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              backgroundColor: pageBg.withValues(alpha: 0.72),
              border: null,
              largeTitle: const Text('语渡'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LevelPill(
                    level: state.selectedLevel,
                    onPressed: () => _showLevelPicker(context, state),
                  ),
                  const SizedBox(width: 10),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _importBook(context, state),
                    child: const Icon(CupertinoIcons.add_circled_solid),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: CupertinoColors.white.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x11000000)),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.book, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '我的书架',
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .navTitleTextStyle,
                            ),
                          ),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            onPressed: () => _openBookStore(context),
                            child: const Text('去网上找书'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
              sliver: state.bookshelf.isEmpty
                  ? const SliverToBoxAdapter(child: _EmptyShelfHint())
                  : SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.78,
                      ),
                      delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final book = state.bookshelf[index];
                    return BookCard(
                      book: book,
                      onPressed: () => _openReading(context, book),
                    );
                  },
                  childCount: state.bookshelf.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLevelPicker(BuildContext context, LensState state) async {
    final selected = state.selectedLevel;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: const Text('词汇难度'),
          message: const Text('选择 AI 提取并标注的词汇考点范围'),
          actions: [
            for (final level in VocabularyLevel.values)
              CupertinoActionSheetAction(
                onPressed: () {
                  state.setLevel(level);
                  Navigator.of(context).pop();
                },
                isDefaultAction: level == selected,
                child: Text(level.label),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            isDestructiveAction: false,
            child: const Text('取消'),
          ),
        );
      },
    );
  }

  Future<void> _importBook(BuildContext context, LensState state) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'epub'],
        allowMultiple: false,
      );
      final picked =
          (result == null || result.files.isEmpty) ? null : result.files.first;
      final path = picked?.path;
      if (path == null || path.isEmpty) return;

      final lower = path.toLowerCase();
      if (!lower.endsWith('.txt') && !lower.endsWith('.epub')) return;

      final book = Book.fromLocalPath(path, defaultLevel: state.selectedLevel);
      state.addImported(book);

      if (!context.mounted) return;
      _openReading(context, book);
    } catch (_) {
      // Silent by design for MVP. We'll add user-facing toasts later.
    }
  }

  void _openReading(BuildContext context, Book book) {
    // Immersive reading: push onto the root Navigator to fully cover the tab
    // scaffold (avoid the "ghost bottom bar" reserved space).
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => ReadingScreen(book: book),
      ),
    );
  }

  void _openBookStore(BuildContext context) {
    final uri = Uri.parse('https://cn.bing.com');
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => BrowserPage(initialUrl: uri.toString()),
      ),
    );
  }
}

class _EmptyShelfHint extends StatelessWidget {
  const _EmptyShelfHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 40, bottom: 12),
      child: Center(
        child: Text(
          '书架为空。\n把书放到 assets/books/（例如 1.txt、2.epub），或点右上角 + 导入。',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: Color(0xFF6E6E73),
          ),
        ),
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.level, required this.onPressed});

  final VocabularyLevel level;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: CupertinoColors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x11000000)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.sparkles, size: 14),
            const SizedBox(width: 6),
            Text(
              level.label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C1E)),
            ),
            const SizedBox(width: 6),
            const Icon(CupertinoIcons.chevron_down, size: 14),
          ],
        ),
      ),
    );
  }
}

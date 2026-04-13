import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../models/book.dart';
import '../../models/vocabulary_level.dart';
import '../../services/imported_file_store.dart';
import '../../services/book_storage_cleaner.dart';
import '../../services/scan_book_store.dart';
import '../reading/pdf_reader_page.dart';
import '../reading/reading_screen.dart';
import '../scan/scan_reader_page.dart';
import '../../widgets/book_shelf_card.dart';
import '../../widgets/level_action_sheet.dart';
import '../../widgets/scan_import_sort_page.dart';

enum _AddMenuAction { file, photo, camera }

const _supportedImportExtensions = <String>[
  'txt',
  'epub',
  'docx',
  'pdf',
  'png',
  'jpg',
  'jpeg',
  'heic',
  'webp',
];

class ShelfTab extends StatelessWidget {
  const ShelfTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    const pageBg = Color(0xFFF6F4EE);
    final scanCount = state.shelf.where((book) => book.isScanDocument).length;

    // Critical: keep a Material + Scaffold context to avoid any debug baseline
    // underlines and ensure consistent text rendering across platforms.
    return material.Scaffold(
      backgroundColor: pageBg,
      body: material.Material(
        color: pageBg,
        child: CupertinoPageScaffold(
          backgroundColor: pageBg,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: pageBg),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Expanded(
                            child: Text(
                              '我的书架',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                color: Color(0xFF1C1C1E),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: BackdropFilter(
                              filter:
                                  ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                height: 40,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFCF6),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0x1A000000),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(40, 40),
                                      onPressed: () => _showAboutDialog(context),
                                      child: const Icon(
                                        CupertinoIcons.info_circle,
                                        size: 26,
                                        color: Color(0xFF1C1C1E),
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 18,
                                      color: const Color(0x22000000),
                                    ),
                                    Builder(
                                      builder: (btnCtx) => CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(40, 40),
                                        onPressed: () =>
                                            _showAddMenu(btnCtx, context, state),
                                        child: const Icon(
                                          CupertinoIcons.add,
                                          size: 28,
                                          color: Color(0xFF1C1C1E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFCF6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0x10000000)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 26,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ShelfStat(
                              label: '当前书架',
                              value: '${state.shelf.length} 本',
                            ),
                          ),
                          Expanded(
                            child: _ShelfStat(
                              label: '扫描文稿',
                              value: '$scanCount 本',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  sliver: state.shelf.isEmpty
                      ? const SliverToBoxAdapter(child: _EmptyHint())
                      : SliverList.separated(
                          itemBuilder: (context, index) {
                            final book = state.shelf[index];
                            final progress = state.progressTopChunk(book);
                            return _ShelfSwipeRow(
                              book: book,
                              onDelete: () => _deleteBook(state, book),
                              onTogglePinned: () => state.togglePinned(book),
                              child: BookShelfCard(
                                book: book,
                                progressTopChunk: progress,
                                onPressed: () => _openBook(context, state, book),
                              ),
                            );
                          },
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 12),
                          itemCount: state.shelf.length,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importLocal(BuildContext context, AppState state) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _supportedImportExtensions,
        allowMultiple: false,
      );
      final picked =
          (result == null || result.files.isEmpty) ? null : result.files.first;
      final path = picked?.path;
      if (path == null || path.isEmpty) return;

      final lower = path.toLowerCase();
      if (!_isSupportedImportPath(lower)) {
        return;
      }

      if (_isImagePath(lower)) {
        if (!context.mounted) return;
        await _importScanImages(
          context,
          state,
          originalPaths: <String>[path],
          author: '文件图片',
        );
        return;
      }

      if (!context.mounted) return;
      final level = await showVocabularyLevelActionSheet(
        context,
        selected: VocabularyLevel.cet4,
        message: '选择这本书的目标词汇难度。后续可在阅读页中途切换，分段混排并分别缓存。',
      );
      if (level == null) return;

      final storedPath = await ImportedFileStore.ingest(path);
      final book = _buildImportedBook(
        originalPath: path,
        storedPath: storedPath,
        level: level,
      );
      await state.addToShelf(book);
      if (!context.mounted) return;
      _openBook(context, state, book);
    } catch (_) {}
  }

  Future<void> _showAddMenu(
    BuildContext anchorContext,
    BuildContext pageContext,
    AppState state,
  ) async {
    const menuWidth = 260.0;
    final overlay = Overlay.of(pageContext, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final box = anchorContext.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchorRect =
        Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height);

    final dx = (anchorRect.right - menuWidth)
        .clamp(12.0, overlayBox.size.width - menuWidth - 12.0)
        .toDouble();
    final dy = (anchorRect.bottom + 10)
        .clamp(12.0, overlayBox.size.height - 12.0)
        .toDouble();

    final action = await showGeneralDialog<_AddMenuAction>(
      context: pageContext,
      barrierLabel: 'dismiss',
      barrierDismissible: true,
      barrierColor: const Color(0x00000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return material.Material(
          color: material.Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: dx,
                top: dy,
                child: FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
                    alignment: Alignment.topRight,
                    child: _AddPopoverMenu(
                      width: menuWidth,
                      onSelected: (value) => Navigator.of(context).pop(value),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!pageContext.mounted) return;
    switch (action) {
      case _AddMenuAction.file:
        await _importLocal(pageContext, state);
        return;
      case _AddMenuAction.photo:
        await _scanFromGallery(pageContext, state);
        return;
      case _AddMenuAction.camera:
        await _scanFromCamera(pageContext, state);
        return;
      case null:
        return;
    }
  }

  Future<void> _scanFromCamera(BuildContext context, AppState state) async {
    // Camera capture is not available on macOS.
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await _showInfoDialog(context, '当前平台不支持拍照扫描');
      return;
    }

    try {
      final picker = ImagePicker();
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      final path = photo?.path;
      if (path == null || path.isEmpty) return;
      if (!context.mounted) return;
      await _importScanImages(
        context,
        state,
        originalPaths: <String>[path],
        author: '拍照扫描',
      );
    } catch (_) {
    } finally {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _scanFromGallery(BuildContext context, AppState state) async {
    try {
      final picker = ImagePicker();
      final photos = await picker.pickMultiImage(imageQuality: 92);
      final paths = photos
          .map((photo) => photo.path)
          .where((path) => path.trim().isNotEmpty)
          .toList(growable: false);
      if (paths.isEmpty) return;
      if (!context.mounted) return;
      await _importScanImages(
        context,
        state,
        originalPaths: paths,
        author: '照片导入',
      );
    } catch (_) {}
  }

  Future<void> _importScanImages(
    BuildContext context,
    AppState state, {
    required List<String> originalPaths,
    required String author,
  }) async {
    var paths = originalPaths
        .where((path) => path.trim().isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) return;

    if (paths.length > 1) {
      final ordered = await Navigator.of(context, rootNavigator: true).push<List<String>>(
        CupertinoPageRoute<List<String>>(
          builder: (_) => ScanImportSortPage(
            paths: paths,
            title: '调整扫描顺序',
          ),
        ),
      );
      if (!context.mounted) return;
      if (ordered == null || ordered.isEmpty) return;
      paths = ordered;
    }

    final level = await showVocabularyLevelActionSheet(
      context,
      selected: VocabularyLevel.cet4,
      message: '选择这张图片的目标词汇难度。导入后会出现在书架中，可反复点开继续长按识别。',
    );
    if (!context.mounted) return;
    if (level == null) return;

    final defaultTitle = ScanBookStore.defaultTitle();
    final title = await _promptScanTitle(
      context,
      initialValue: defaultTitle,
    );
    if (!context.mounted) return;
    if (title == null) return;

    final doc = await ScanBookStore.createFromImages(
      title: title,
      imagePaths: paths,
    );
    final book = doc.toBook(level);

    await state.addToShelf(book);
    if (!context.mounted) return;
    _openBook(context, state, book, initialScanPageIndex: 0);
  }

  Future<String?> _promptScanTitle(
    BuildContext context, {
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: const Text('命名扫描册'),
          content: Column(
            children: [
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                placeholder: '输入书名或章节名',
                clearButtonMode: OverlayVisibilityMode.editing,
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Book _buildImportedBook({
    required String originalPath,
    required String storedPath,
    required VocabularyLevel level,
    String? forcedAuthor,
  }) {
    final originalName = originalPath.split(Platform.pathSeparator).last;
    final title = originalName.replaceAll(
      RegExp(
        r'\.(txt|epub|docx|pdf|png|jpg|jpeg|heic|webp)$',
        caseSensitive: false,
      ),
      '',
    );
    final lower = originalPath.toLowerCase();
    final author = forcedAuthor ??
        (_isImagePath(lower) ? '图片导入' : '本地导入');
    return Book(
      title: title.isEmpty ? originalName : title,
      author: author,
      defaultLevel: level,
      source: BookSource.localFile,
      locator: storedPath,
    );
  }

  bool _isSupportedImportPath(String lowerPath) {
    return lowerPath.endsWith('.txt') ||
        lowerPath.endsWith('.epub') ||
        lowerPath.endsWith('.docx') ||
        lowerPath.endsWith('.pdf') ||
        _isImagePath(lowerPath);
  }

  bool _isImagePath(String lowerPath) {
    return lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.heic') ||
        lowerPath.endsWith('.webp');
  }

  Future<void> _showInfoDialog(BuildContext context, String message) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: const Text('提示'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  void _openBook(
    BuildContext context,
    AppState state,
    Book book, {
    int initialScanPageIndex = 0,
  }) {
    () async {
      var openBook = book;
      if (book.source == BookSource.localFile &&
          !book.isScanDocument &&
          !book.isImage) {
        final ingested = await ImportedFileStore.ingest(book.locator);
        if (ingested != book.locator) {
          openBook = Book(
            title: book.title,
            author: book.author,
            defaultLevel: book.defaultLevel,
            source: book.source,
            locator: ingested,
            isPinned: book.isPinned,
            coverAssetPath: book.coverAssetPath,
            coverFilePath: book.coverFilePath,
            blurb: book.blurb,
          );
          await state.addToShelf(openBook);
        }
      }
      if (!context.mounted) return;
      if (openBook.isScanDocument) {
        Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute<void>(
            builder: (_) => ScanReaderPage(
              scanDocumentPath: openBook.locator,
              initialLevel: openBook.defaultLevel,
              bookTitle: openBook.title,
              sourceLabel: openBook.author,
              initialPageIndex: initialScanPageIndex,
            ),
          ),
        );
        return;
      }
      if (openBook.isImage) {
        Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute<void>(
            builder: (_) => ScanReaderPage(
              imagePath: openBook.locator,
              initialLevel: openBook.defaultLevel,
              bookTitle: openBook.title,
              sourceLabel: openBook.author,
            ),
          ),
        );
        return;
      }
      if (openBook.isPdf) {
        Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute<void>(
            builder: (_) => PdfReaderPage(book: openBook),
          ),
        );
        return;
      }
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute<void>(
          builder: (_) => ReadingScreen(book: openBook),
        ),
      );
    }();
  }

  Future<void> _deleteBook(AppState state, Book book) async {
    try {
      await state.removeFromShelf(book);
      await BookStorageCleaner.deepClean(book);
    } catch (_) {}
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('关于《语渡》'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/branding/app_icon.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(CupertinoIcons.app, size: 60),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '语渡',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'v1.2.9',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6E6E73)),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () async {
                Navigator.of(context).pop();
                await _openPrivacyPolicy();
              },
              child: const Text('隐私权政策'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPrivacyPolicy() async {
    const url = 'https://docs.qq.com/doc/DRnZUeGhsY2JraXJD';
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) debugPrint('[privacy] launchUrl returned false: $url');
    } catch (e, st) {
      debugPrint('[privacy] launchUrl error=$e');
      debugPrintStack(stackTrace: st);
    }
  }
}

class _AddPopoverMenu extends StatelessWidget {
  const _AddPopoverMenu({
    required this.width,
    required this.onSelected,
  });

  final double width;
  final ValueChanged<_AddMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoColors.white.withValues(alpha: 0.92);
    const border = Color(0x14000000);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 34,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AddPopoverRow(
                label: '文件',
                icon: CupertinoIcons.paperclip,
                showDivider: true,
                onPressed: () => onSelected(_AddMenuAction.file),
              ),
              _AddPopoverRow(
                label: '照片',
                icon: CupertinoIcons.photo,
                showDivider: true,
                onPressed: () => onSelected(_AddMenuAction.photo),
              ),
              _AddPopoverRow(
                label: '相机',
                icon: CupertinoIcons.camera,
                showDivider: false,
                onPressed: () => onSelected(_AddMenuAction.camera),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfStat extends StatelessWidget {
  const _ShelfStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1C1C1E),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF8E8E93),
          ),
        ),
      ],
    );
  }
}

class _ShelfSwipeRow extends StatefulWidget {
  const _ShelfSwipeRow({
    required this.book,
    required this.child,
    required this.onDelete,
    required this.onTogglePinned,
  });

  final Book book;
  final Widget child;
  final Future<void> Function() onDelete;
  final Future<void> Function() onTogglePinned;

  @override
  State<_ShelfSwipeRow> createState() => _ShelfSwipeRowState();
}

class _ShelfSwipeRowState extends State<_ShelfSwipeRow> {
  static const double _actionWidth = 88;
  static const double _maxReveal = _actionWidth * 2 + 8;

  double _offset = 0;

  void _setOpen(bool open) {
    setState(() => _offset = open ? -_maxReveal : 0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 106,
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ShelfActionButton(
                    backgroundColor: widget.book.isPinned
                        ? const Color(0xFFD4B04C)
                        : const Color(0xFF4F8EF7),
                    icon: widget.book.isPinned
                        ? CupertinoIcons.pin_slash_fill
                        : CupertinoIcons.pin_fill,
                    label: widget.book.isPinned ? '取消置顶' : '置顶',
                    onPressed: () async {
                      _setOpen(false);
                      await widget.onTogglePinned();
                    },
                  ),
                  const SizedBox(width: 8),
                  _ShelfActionButton(
                    backgroundColor: const Color(0xFFFF5A5F),
                    icon: CupertinoIcons.delete_solid,
                    label: '删除',
                    onPressed: () async {
                      _setOpen(false);
                      await widget.onDelete();
                    },
                  ),
                ],
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _offset != 0 ? () => _setOpen(false) : null,
              onHorizontalDragUpdate: (details) {
                final next = (_offset + details.delta.dx).clamp(-_maxReveal, 0.0);
                if (next == _offset) return;
                setState(() => _offset = next);
              },
              onHorizontalDragEnd: (details) {
                final shouldOpen = _offset.abs() > _maxReveal * 0.36 ||
                    details.primaryVelocity != null &&
                        details.primaryVelocity! < -240;
                _setOpen(shouldOpen);
              },
              child: AbsorbPointer(
                absorbing: _offset != 0,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfActionButton extends StatelessWidget {
  const _ShelfActionButton({
    required this.backgroundColor,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Color backgroundColor;
  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Container(
        width: 88,
        height: 106,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 22,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: CupertinoColors.white, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: CupertinoColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPopoverRow extends StatelessWidget {
  const _AddPopoverRow({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.showDivider,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final dividerColor = const Color(0x14000000);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      pressedOpacity: 0.6,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: dividerColor, width: 0.8))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E),
                  decoration: TextDecoration.none,
                  fontFamily: '.SF UI Text',
                ),
              ),
            ),
            Icon(
              icon,
              size: 24,
              color: const Color(0xFF1C1C1E),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: Center(
        child: Text(
          '还没有书。\n点右上角 + 导入本地 txt/epub，或去「探索」加入公版书。',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Color(0xFF6E6E73),
          ),
        ),
      ),
    );
  }
}

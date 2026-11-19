import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_state.dart';
import '../../models/book.dart';
import '../../widgets/book_display_title.dart';
import '../../widgets/ai_consent_panel.dart';
import '../../models/vocabulary_level.dart';
import '../../screens/reading/pdf_reader_page.dart';
import '../../screens/reading/reading_screen.dart';
import '../../screens/scan/scan_reader_page.dart';
import '../../services/imported_file_store.dart';
import '../../services/asset_books_service.dart';
import '../../services/native_image_ocr.dart';
import 'android_reading_cover.dart';
import 'companion_controller.dart';
import 'companion_review.dart';
import 'learning_backup_controls.dart';
import 'reader_storage_controls.dart';
import 'lingfer_theme.dart';
import 'lingfer_glass.dart';
import 'reading_assistant.dart';
import 'vocabulary_engine.dart';
import 'reading_controls.dart';
import 'reading_preferences.dart';
import 'page_translation_view.dart';
import 'annotations/annotated_image_reader.dart';
import 'annotations/anchored_text.dart';

part 'companion_components.dart';
part 'android_library.dart';
part 'companion_reader.dart';
part 'companion_sheets.dart';

class CompanionShell extends StatefulWidget {
  const CompanionShell({super.key});
  @override
  State<CompanionShell> createState() => _CompanionShellState();
}

class _CompanionShellState extends State<CompanionShell>
    with WidgetsBindingObserver {
  final controller = CompanionController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.refreshScreenStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  void _openDestination({required bool saved}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Scaffold(
            appBar: AppBar(
              backgroundColor: LingferColors.background,
              title: Text(
                '语渡',
                style: LingferType.heading.copyWith(
                  fontSize: 19,
                  color: LingferColors.muted,
                ),
              ),
            ),
            body: saved
                ? _SavedWords(controller: controller)
                : _Settings(controller: controller),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      // Fold/unfold and initial Android attachment can briefly report a zero
      // viewport. Wait for real bounds before constructing fixed-width controls.
      if (MediaQuery.sizeOf(context).width < 160) {
        return const SizedBox.shrink();
      }
      final androidStyle = Theme.of(context).platform == TargetPlatform.android;
      final compactHeader =
          MediaQuery.sizeOf(context).width <
          220 + MediaQuery.textScalerOf(context).scale(64);
      final settings = IconButton(
        key: const ValueKey('open-settings'),
        tooltip: '设置',
        onPressed: () => _openDestination(saved: false),
        icon: Icon(
          androidStyle
              ? Icons.tune_rounded
              : CupertinoIcons.slider_horizontal_3,
          size: 21,
          color: LingferColors.ink,
        ),
      );
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Scaffold(
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1104),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 20, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '语渡',
                              style: LingferType.brandHeading.copyWith(
                                fontSize: androidStyle ? 36 : 32,
                              ),
                            ),
                          ),
                          if (androidStyle && compactHeader)
                            IconButton(
                              key: const ValueKey('open-vocabulary'),
                              tooltip: '生词本',
                              onPressed: () => _openDestination(saved: true),
                              icon: const Icon(
                                Icons.bookmarks_outlined,
                                size: 21,
                              ),
                            )
                          else
                            TextButton(
                              key: const ValueKey('open-vocabulary'),
                              onPressed: () => _openDestination(saved: true),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (androidStyle) ...[
                                    const Icon(
                                      Icons.bookmark_border_rounded,
                                      size: 18,
                                      color: LingferColors.accent,
                                    ),
                                    const SizedBox(width: 5),
                                  ],
                                  const Text(
                                    '生词本',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: LingferColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 8),
                          if (androidStyle)
                            Material(
                              color: const Color(0xFFE9EEEA),
                              shape: const CircleBorder(),
                              child: settings,
                            )
                          else
                            LingferGlassSurface(radius: 25, child: settings),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: _ReadHome(controller: controller),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ReadHome extends StatelessWidget {
  const _ReadHome({required this.controller});
  final CompanionController controller;

  @override
  Widget build(BuildContext context) {
    final shelf = AppScope.of(context).shelf;
    final android = controller.bridge.supported;
    final androidStyle = Theme.of(context).platform == TargetPlatform.android;
    return _PageFrame(
      scrollKey: const ValueKey('reading-home-scroll'),
      children: [
        if (!androidStyle) ...[
          _ReadingContextBar(controller: controller),
          const AiConsentEntry(firstUseOnly: true),
          const SizedBox(height: 18),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final primary = _ReadingEntry(
              controller: controller,
              android: android,
            );
            final shortcuts = _Shortcuts(
              controller: controller,
              android: android,
            );
            if (constraints.maxWidth >= 620) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: primary),
                  const SizedBox(width: 20),
                  Expanded(flex: 5, child: shortcuts),
                ],
              );
            }
            return Column(
              children: [primary, const SizedBox(height: 14), shortcuts],
            );
          },
        ),
        if (androidStyle) const AiConsentEntry(firstUseOnly: true),
        if (controller.error != null) ...[
          const SizedBox(height: 16),
          _InfoStrip(
            icon: Icons.info_outline_rounded,
            text: controller.error!,
            warning: true,
          ),
        ],
        if (controller.lastText.isNotEmpty) ...[
          const SizedBox(height: 30),
          const _SectionHeading(title: '上次阅读'),
          const SizedBox(height: 12),
          _Surface(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () =>
                  _openText(context, controller, controller.lastText, '上次阅读'),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.lastText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LingferType.reading.copyWith(
                        fontSize: 17,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            controller.preferences.mode ==
                                    ReadingMode.translation
                                ? '整页对照'
                                : '${_shortLevel(controller.level)} · ${controller.lastHits.length} 个匹配词',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const Text(
                          '继续阅读',
                          style: TextStyle(
                            color: LingferColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.arrow_forward_rounded, size: 17),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 30),
        _SectionHeading(title: '本地资料', trailing: '${shelf.length} 份'),
        const SizedBox(height: 6),
        Text(
          Theme.of(context).platform == TargetPlatform.android
              ? '只列出你主动导入或加入阅读的资料。'
              : '只显示你主动导入、保存或加入阅读的资料，不会扫描手机里的其他文件。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: LingferColors.muted,
          ),
        ),
        const SizedBox(height: 12),
        if (shelf.isEmpty &&
            Theme.of(context).platform == TargetPlatform.android)
          _AndroidEmptyLibrary(
            onImport: controller.loading
                ? null
                : () => _importFile(context, controller),
            onReadSample: () =>
                _openText(context, controller, _sampleText, '英文试读'),
          )
        else if (shelf.isEmpty)
          _Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '英文试读',
                  style: TextStyle(fontSize: 12, color: LingferColors.muted),
                ),
                const SizedBox(height: 14),
                Text(
                  _sampleText.split('\n\n').first,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: LingferType.reading.copyWith(
                    fontSize: 18,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        _openText(context, controller, _sampleText, '英文试读'),
                    child: const Text('试读一段'),
                  ),
                ),
                const Text(
                  '当前还没有导入资料。可导入文件，或从下方公版书开始阅读。',
                  style: TextStyle(fontSize: 12, color: LingferColors.muted),
                ),
              ],
            ),
          )
        else
          _Surface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < shelf.length; i++) ...[
                  if (i > 0) const Divider(indent: 18, endIndent: 18),
                  _LocalBookRow(book: shelf[i]),
                ],
              ],
            ),
          ),
        if (shelf.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  _openText(context, controller, _sampleText, '英文试读'),
              icon: const Icon(Icons.article_outlined, size: 18),
              label: const Text('试读一段'),
            ),
          ),
        const SizedBox(height: 28),
        _BundledBooksSection(level: controller.level),
      ],
    );
  }
}

class _BundledBooksSection extends StatelessWidget {
  const _BundledBooksSection({required this.level});
  final VocabularyLevel level;

  Future<void> _open(
    BuildContext context,
    BundledPublicDomainBook entry,
  ) async {
    final book = entry.toBook(level);
    await AppScope.of(context).addToShelf(book);
    if (context.mounted) _openBook(context, book);
  }

  void _showSources(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 580),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: LingferGlassSurface(
          radius: 28,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '书目与来源',
                          style: LingferType.heading.copyWith(fontSize: 22),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭来源说明',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(CupertinoIcons.xmark, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '三本均为英文原著完整正文，已内置，可离线阅读；不包含现代中文译本或插画。',
                    style: TextStyle(height: 1.7, color: LingferColors.muted),
                  ),
                  for (final entry
                      in AssetBooksService.publicDomainCatalog) ...[
                    const SizedBox(height: 20),
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${entry.originalTitle}\n${entry.author} · ${entry.publicationYear}',
                      style: const TextStyle(fontSize: 13, height: 1.7),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      entry.sourceUrl,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: LingferColors.accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    '来源致谢：Project Gutenberg。仅保留原著正文，已移除下载站页头、页尾和品牌包装；未删节原著内容。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.7,
                      color: LingferColors.muted,
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

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '内置公版书',
              style: LingferType.interfaceHeading.copyWith(fontSize: 20),
            ),
          ),
          const Text(
            '3 本',
            style: TextStyle(fontSize: 12, color: LingferColors.muted),
          ),
        ],
      ),
      const SizedBox(height: 6),
      const Text(
        '英文原著全本 · 离线阅读',
        style: TextStyle(fontSize: 12, height: 1.6, color: LingferColors.muted),
      ),
      const SizedBox(height: 12),
      if (Theme.of(context).platform == TargetPlatform.android)
        _AndroidBookShelf(onOpen: (entry) => _open(context, entry))
      else
        _Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (
                var i = 0;
                i < AssetBooksService.publicDomainCatalog.length;
                i++
              ) ...[
                if (i > 0) const Divider(height: 1, indent: 18, endIndent: 18),
                ListTile(
                  key: ValueKey(
                    'bundled-book-${AssetBooksService.publicDomainCatalog[i].assetPath}',
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  leading: const Icon(
                    CupertinoIcons.book,
                    size: 26,
                    color: LingferColors.accent,
                  ),
                  title: Text(
                    AssetBooksService.publicDomainCatalog[i].title,
                    style: LingferType.interfaceHeading.copyWith(
                      fontSize: 17,
                      height: 1.5,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '${AssetBooksService.publicDomainCatalog[i].author} · 英文全本',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: LingferColors.muted,
                      ),
                    ),
                  ),
                  trailing: const Icon(
                    CupertinoIcons.chevron_right,
                    size: 15,
                    color: LingferColors.muted,
                  ),
                  onTap: () =>
                      _open(context, AssetBooksService.publicDomainCatalog[i]),
                ),
              ],
            ],
          ),
        ),
      TextButton(
        onPressed: () => _showSources(context),
        child: const Text('书目与来源'),
      ),
    ],
  );
}

class _ReadingEntry extends StatefulWidget {
  const _ReadingEntry({required this.controller, required this.android});
  final CompanionController controller;
  final bool android;
  @override
  State<_ReadingEntry> createState() => _ReadingEntryState();
}

class _ReadingEntryState extends State<_ReadingEntry> {
  bool busy = false;
  Future<void> _activate() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (widget.android || Platform.isIOS) {
        await _startScreenReading(context, widget.controller);
      } else {
        await _pickImage(context, widget.controller, ImageSource.gallery);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.android || Platform.isIOS;
    final running = live && widget.controller.running;
    final androidStyle = Theme.of(context).platform == TargetPlatform.android;
    final title = live ? '随屏阅读' : '截图阅读';
    final description =
        widget.controller.preferences.mode == ReadingMode.translation
        ? (widget.android ? '停稳后预译当前页。轻点段落旁的页边看译文，在正文上滑动翻页。' : '开启系统读屏后自动翻译，画中画预览部分译文。')
        : widget.android
        ? '释义就在原词旁。想读整段，点书本按钮选段翻译。'
        : Platform.isIOS
        ? '开启系统读屏后自动识别，画中画查看当前词义。'
        : '在原词旁看释义，点按理解原句。';
    final action = FilledButton(
      key: const ValueKey('primary-reading-action'),
      onPressed: busy || widget.controller.loading ? null : _activate,
      style: androidStyle
          ? FilledButton.styleFrom(
              foregroundColor: AndroidReadingCover.ink,
              backgroundColor: AndroidReadingCover.paper,
              disabledBackgroundColor: const Color(0xFFC0D1CC),
              disabledForegroundColor: AndroidReadingCover.ink,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            )
          : null,
      child: Row(
        mainAxisSize: androidStyle ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy) ...[
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: androidStyle ? AndroidReadingCover.ink : Colors.white,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              busy
                  ? '正在打开…'
                  : live
                  ? (running
                        ? (Platform.isIOS ? '查看随屏阅读' : '停止随屏阅读')
                        : '开启随屏阅读')
                  : '选择截图',
              textAlign: TextAlign.center,
            ),
          ),
          if (!busy) ...[
            const SizedBox(width: 10),
            Icon(
              androidStyle && running
                  ? Icons.stop_rounded
                  : CupertinoIcons.arrow_right,
              size: 17,
            ),
          ],
        ],
      ),
    );
    if (androidStyle) {
      return AndroidReadingCover(
        title: title,
        description: description,
        running: running,
        action: action,
        preferences: _ReadingContextBar(
          controller: widget.controller,
          embedded: true,
        ),
      );
    }
    return _Surface(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: LingferType.heading.copyWith(fontSize: 25),
                ),
              ),
              if (running)
                const _StatusLabel(
                  text: '会话中',
                  icon: CupertinoIcons.circle_fill,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.65,
              color: LingferColors.muted,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: action),
        ],
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.controller, required this.android});
  final CompanionController controller;
  final bool android;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 1) return const SizedBox.shrink();
      final androidStyle = Theme.of(context).platform == TargetPlatform.android;
      final actions = [
        if (android || Platform.isIOS)
          (
            CupertinoIcons.photo,
            '截图阅读',
            () => _pickImage(context, controller, ImageSource.gallery),
          ),
        (
          CupertinoIcons.doc_plaintext,
          '粘贴文字',
          () => _pasteText(context, controller),
        ),
        (
          CupertinoIcons.camera,
          '拍照识别',
          () => _pickImage(context, controller, ImageSource.camera),
        ),
        (
          CupertinoIcons.folder_open,
          '导入资料',
          () => _importFile(context, controller),
        ),
      ];
      // Each four-character label shares its tile with a 32dp icon and padding.
      final entryWidth =
          32 + 10 + 10 + 4 * MediaQuery.textScalerOf(context).scale(14);
      final single = androidStyle
          ? constraints.maxWidth < 24 + 8 + 2 * entryWidth
          : constraints.maxWidth < 260 &&
                MediaQuery.textScalerOf(context).scale(14) > 20;
      final columns = single ? 1 : 2;
      final width = (constraints.maxWidth - 24 - 8 * (columns - 1)) / columns;
      final content = Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actions)
                  SizedBox(
                    key: ValueKey('entry-${action.$2}'),
                    width: width,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 56),
                        padding: EdgeInsets.symmetric(
                          horizontal: androidStyle ? 5 : 12,
                          vertical: androidStyle ? 10 : 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: androidStyle
                            ? Colors.transparent
                            : Colors.white.withValues(alpha: .68),
                        foregroundColor: LingferColors.ink,
                      ),
                      onPressed: controller.loading ? null : action.$3,
                      child: Row(
                        children: [
                          if (androidStyle)
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2EF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                action.$1,
                                size: 18,
                                color: LingferColors.accent,
                              ),
                            )
                          else
                            Icon(
                              action.$1,
                              size: 19,
                              color: LingferColors.accent,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              action.$2,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 10, bottom: 2),
              child: Divider(height: 1, indent: 8, endIndent: 8),
            ),
            TextButton(
              onPressed: () => _showPlatformGuide(context, android),
              style: TextButton.styleFrom(
                foregroundColor: LingferColors.muted,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    android
                        ? CupertinoIcons.question_circle
                        : CupertinoIcons.square_arrow_up,
                    size: 17,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      android ? '随屏阅读使用方法' : '从 Safari 分享阅读',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  const Icon(CupertinoIcons.chevron_right, size: 11),
                ],
              ),
            ),
          ],
        ),
      );
      return androidStyle
          ? _Surface(padding: EdgeInsets.zero, child: content)
          : LingferGlassSurface(radius: 24, shadow: false, child: content);
    },
  );
}

class _LocalBookRow extends StatelessWidget {
  const _LocalBookRow({required this.book});
  final Book book;
  String get _format => book.isPdf
      ? 'PDF'
      : book.lowerLocator.endsWith('.epub')
      ? 'EPUB'
      : book.lowerLocator.endsWith('.docx')
      ? 'DOCX'
      : book.isScanContent
      ? '图片'
      : 'TXT';
  Future<void> _showActions(BuildContext context) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: LingferGlassSurface(
          radius: 28,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetHeader(title: book.displayTitle, subtitle: '资料操作'),
                ListTile(
                  minTileHeight: 60,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Icon(
                    book.isPinned
                        ? CupertinoIcons.pin_slash
                        : CupertinoIcons.pin,
                    size: 21,
                    color: LingferColors.accent,
                  ),
                  title: Text(book.isPinned ? '取消置顶' : '置顶'),
                  onTap: () => Navigator.pop(sheetContext, 'pin'),
                ),
                const Divider(height: 1, indent: 24, endIndent: 24),
                ListTile(
                  minTileHeight: 68,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: const Icon(
                    CupertinoIcons.minus_circle,
                    size: 21,
                    color: LingferColors.muted,
                  ),
                  title: const Text('从资料列表移除'),
                  subtitle: const Text(
                    '文件仍保留在本机',
                    style: TextStyle(fontSize: 12, color: LingferColors.muted),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'remove'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
    if (value == null || !context.mounted) return;
    final state = AppScope.of(context);
    if (value == 'pin') await state.togglePinned(book);
    if (value == 'remove') {
      await state.removeFromShelf(book);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已移出资料列表，文件仍保留在本机'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => state.addToShelf(book),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final android = Theme.of(context).platform == TargetPlatform.android;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
      horizontalTitleGap: 14,
      leading: android
          ? _AndroidFileMark(format: _format)
          : Container(
              width: 48,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LingferColors.tint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                _format,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .4,
                  color: LingferColors.accent,
                ),
              ),
            ),
      title: Text(
        book.displayTitle,
        maxLines: android ? null : 2,
        overflow: android ? TextOverflow.visible : TextOverflow.ellipsis,
        style: LingferType.heading.copyWith(fontSize: 17, height: 1.4),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          '${book.isPinned ? '置顶 · ' : ''}${book.defaultLevel.label} · ${book.subtitle}',
          style: const TextStyle(fontSize: 12, color: LingferColors.muted),
        ),
      ),
      trailing: IconButton(
        tooltip: '资料操作',
        onPressed: () => _showActions(context),
        icon: Icon(
          android ? Icons.more_vert_rounded : CupertinoIcons.ellipsis,
          size: 22,
          color: LingferColors.muted,
        ),
      ),
      onTap: () => _openBook(context, book),
    );
  }
}

class _SavedWords extends StatelessWidget {
  const _SavedWords({required this.controller});
  final CompanionController controller;
  @override
  Widget build(BuildContext context) {
    final words = controller.saved.values.toList().reversed.toList();
    return _PageFrame(
      maxWidth: 780,
      scrollKey: const PageStorageKey('saved-words-scroll'),
      children: [
        const _PageTitle(title: '生词本', subtitle: '词义和遇见它的原句，一起保存。'),
        LearningBackupControls(controller: controller),
        const SizedBox(height: 22),
        Row(
          children: [
            Text(
              '已收藏 ${words.length} 个',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '已标记熟词 ${controller.known.length} 个',
                style: const TextStyle(
                  color: LingferColors.muted,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (words.isEmpty)
          const _StatePanel(
            icon: Icons.bookmark_border_rounded,
            title: '还没有收藏的词',
            message: '阅读时点词卡右上角的收藏按钮。\n基础释义和原句会保存在这台设备上。',
          ),
        if (words.isNotEmpty) ...[
          _Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '待复习 ${controller.dueWords().length} 个 · 今天已复习 ${controller.reviewedToday} 个',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: controller.dueWords().isEmpty
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                CompanionReviewPage(controller: controller),
                          ),
                        ),
                  icon: const Icon(Icons.style_outlined),
                  label: const Text('开始复习'),
                ),
                const SizedBox(height: 6),
                const Text(
                  '先回忆，再看释义和原句。进度保存在这台设备上。',
                  style: TextStyle(fontSize: 12, color: LingferColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        for (final hit in words)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: WordCard(hit: hit, controller: controller, savedView: true),
          ),
      ],
    );
  }
}

class _Settings extends StatelessWidget {
  const _Settings({required this.controller});
  final CompanionController controller;
  @override
  Widget build(BuildContext context) => _PageFrame(
    maxWidth: 780,
    scrollKey: const PageStorageKey('settings-scroll'),
    children: [
      const _PageTitle(title: '设置', subtitle: '学习范围、连接与阅读方式。'),
      const SizedBox(height: 28),
      const _SectionHeading(title: '阅读'),
      const SizedBox(height: 12),
      _Surface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _LevelRow(controller: controller, embedded: true),
            const Divider(indent: 20, endIndent: 20),
            ReadingLanguageControl(controller: controller),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 24),
        child: Text(
          '已标记 ${controller.known.length} 个熟词，筛选时会自动略过。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      const _SectionHeading(title: '连接与使用'),
      const SizedBox(height: 12),
      const AiConsentEntry(),
      const SizedBox(height: 12),
      _Surface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              leading: const Icon(Icons.cloud_outlined, size: 22),
              title: const Text(
                'AI 讲解',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                controller.connection,
                style: const TextStyle(
                  fontSize: 12,
                  color: LingferColors.muted,
                ),
              ),
              trailing: controller.connection == '正在检查连接…'
                  ? const Padding(
                      padding: EdgeInsets.all(15),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: '检查连接',
                      onPressed: controller.checkConnection,
                      icon: const Icon(Icons.refresh_rounded, size: 22),
                    ),
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: const Icon(Icons.offline_pin_outlined, size: 22),
              title: const Text(
                '离线阅读',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                '基础释义、难度筛词和收藏无需联网',
                style: TextStyle(fontSize: 12, color: LingferColors.muted),
              ),
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Icon(
                controller.bridge.supported
                    ? CupertinoIcons.square_on_square
                    : CupertinoIcons.square_arrow_up,
                size: 22,
              ),
              title: Text(
                controller.bridge.supported ? 'Android 随屏阅读' : 'iOS 随屏与分享阅读',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: const Text(
                '查看使用方法',
                style: TextStyle(fontSize: 12, color: LingferColors.muted),
              ),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 20),
              onTap: () =>
                  _showPlatformGuide(context, controller.bridge.supported),
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: const Icon(Icons.privacy_tip_outlined, size: 22),
              title: const Text(
                '内容与隐私',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 20),
              onTap: () => showAiConsentPanel(context),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      ReaderStorageControls(appState: AppScope.of(context)),
      const SizedBox(height: 28),
      const Text(
        '语渡 Lingfer 2.1',
        textAlign: TextAlign.center,
        style: TextStyle(color: LingferColors.muted, fontSize: 12),
      ),
    ],
  );
}

Future<void> _pickImage(
  BuildContext context,
  CompanionController controller,
  ImageSource source,
) async {
  try {
    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2400,
      imageQuality: 95,
    );
    if (image != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AnnotatedImageReader(
            controller: controller,
            title: '原图阅读',
            imagePath: image.path,
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法打开相机或相册，请检查权限后重试。')));
    }
  }
}

Future<void> _importFile(
  BuildContext context,
  CompanionController controller,
) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub', 'pdf', 'docx'],
      allowMultiple: false,
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null || !context.mounted) return;
    final state = AppScope.of(context);
    final stored = await ImportedFileStore.ingest(path);
    final book = Book.fromLocalPath(stored, defaultLevel: controller.level);
    await state.addToShelf(book);
    if (context.mounted) _openBook(context, book);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('资料未能导入，请确认文件完整后重试。')));
    }
  }
}

Future<void> _openBook(BuildContext context, Book book) async {
  var readableBook = book;
  if (book.source == BookSource.mock) {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('这条旧版示例没有正文'),
        content: const Text('记录会保留。可以从主页的内置公版书开始阅读，或导入完整文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回主页'),
          ),
        ],
      ),
    );
    return;
  }
  if (book.source == BookSource.localFile) {
    final path = await ImportedFileStore.resolveReadablePath(book.locator);
    final file = File(path);
    var present = false;
    var hasContent = false;
    try {
      present = await file.exists();
      hasContent = present && await file.length() > 0;
    } on FileSystemException {
      // Treat a file that moved during opening as unavailable, not a crash.
    }
    if (!context.mounted) return;
    if (!hasContent) {
      final chooseAgain = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(present ? '这份文件是空的' : '找不到这份资料的文件'),
          content: Text(
            book.isScanContent
                ? '原记录和阅读进度会保留。请重新扫描，或从主页导入原文件。'
                : '原记录和阅读进度会保留。重新选择同一份资料的完整文件后，可以接着阅读。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回'),
            ),
            if (!book.isScanContent)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('重新选择文件'),
              ),
          ],
        ),
      );
      if (chooseAgain == true && context.mounted)
        await _repairImportedBook(context, book);
      return;
    }
    // Text books resolve inside BookTextService and retain their old cache key.
    // File-based native viewers need the currently readable absolute path.
    if (path != book.locator && (book.isPdf || book.isScanContent)) {
      readableBook = book.withLocator(path);
    }
  }
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => readableBook.isPdf
          ? PdfReaderPage(book: readableBook)
          : readableBook.isScanDocument
          ? ScanReaderPage(
              scanDocumentPath: readableBook.locator,
              initialLevel: readableBook.defaultLevel,
              bookTitle: readableBook.title,
            )
          : ReadingScreen(book: readableBook),
    ),
  );
}

Future<void> _repairImportedBook(BuildContext context, Book book) async {
  try {
    final extension = book.isPdf
        ? 'pdf'
        : book.lowerLocator.endsWith('.epub')
        ? 'epub'
        : book.lowerLocator.endsWith('.docx')
        ? 'docx'
        : 'txt';
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择这份资料的完整文件',
      type: FileType.custom,
      allowedExtensions: [extension],
      allowMultiple: false,
    );
    final selectedPath = result?.files.firstOrNull?.path;
    if (selectedPath == null || !context.mounted) return;
    final storedPath = await ImportedFileStore.ingest(selectedPath);
    if (!await File(storedPath).exists() ||
        await File(storedPath).length() == 0) {
      throw const FormatException('empty or unavailable selected file');
    }
    if (!context.mounted) return;
    final repaired = book.withLocator(storedPath);
    await AppScope.of(context).replaceBook(oldId: book.id, newBook: repaired);
    if (context.mounted) await _openBook(context, repaired);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未能读取新选择的文件，请选择同一份资料的完整文件。原记录会保留。')),
      );
    }
  }
}

Future<void> _startScreenReading(
  BuildContext context,
  CompanionController controller,
) async {
  if (Platform.isIOS) {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    if (prefs.getBool('apple_screen_disclosure_v1') != true) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('开启 iPhone 随屏阅读'),
          content: const Text(
            '需要 iOS 27 或以上。你主动开启系统屏幕共享后，语渡会在本机识别当前画面，自动显示翻译画中画，并在灵动岛与锁屏实时活动中显示阅读摘要。长按灵动岛可以暂停、停止或返回词卡。浮窗不能将词义贴到其他 App 的原词上。屏幕图片不上传、不自动保存；联网翻译与 AI 讲解会发送对应文字。可以随时从语渡或系统结束共享。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('了解，继续'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      await prefs.setBool('apple_screen_disclosure_v1', true);
    }
    await controller.start();
    return;
  }
  if (controller.running) {
    await controller.stop();
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  if (prefs.getBool('screen_disclosure_v2') != true) {
    final accepted = await _showAndroidReadingNotice(
      context,
      title: '开启随屏阅读',
      paragraphs: const [
        '选择阅读的 App 后，语渡会在本机识别当前页面。学习辅助把释义标在原词旁。整页对照在页面停稳后预译可见段落，轻点段落旁的页边即可展开译文。',
        '英译中的基础词义可离线查看。段落翻译、整页翻译和语境讲解等功能需要另行允许联网 AI，才会发送对应文字。屏幕图片不会上传或自动存入相册。',
      ],
      accept: '了解，继续',
      cancel: '暂不开启',
    );
    if (accepted != true) return;
    await prefs.setBool('screen_disclosure_v2', true);
  }
  await controller.refreshScreenStatus();
  if (!context.mounted) return;
  if (!controller.overlayAllowed) {
    final accepted = await _showAndroidReadingNotice(
      context,
      title: '允许显示悬浮按钮',
      paragraphs: const [
        '在系统设置中，允许语渡显示在其他应用上层。这样在浏览器或阅读器里，释义就能出现在原词旁。',
        '授权后回到语渡，再点一次「开启随屏阅读」。',
      ],
      accept: '前往设置',
      cancel: '取消',
    );
    if (accepted == true) await controller.bridge.requestOverlayPermission();
    return;
  }
  final started = await controller.start();
  if (started && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已开启。切换到想读的 App，页面停稳后会自动更新译义。')),
    );
  }
}

const _sampleText =
    'Learning a language is not only about memorizing isolated words. A familiar context can reveal a subtle distinction and make an unfamiliar expression easier to remember.\n\nResearchers maintain that consistent practice is more effective than occasional effort. An innovative approach does not necessarily require complicated technology: a small adjustment can transform an ordinary reading experience.\n\nWhen you encounter a difficult paragraph, identify the essential argument, consider the evidence, and resist the temptation to translate every single word.';

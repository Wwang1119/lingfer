import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../models/vocabulary_level.dart';
import '../services/imported_file_store.dart';
import '../services/scan_book_store.dart';
import '../screens/scan/scan_reader_page.dart';
import '../screens/reading/pdf_reader_page.dart';
import '../screens/reading/reading_screen.dart';
import '../widgets/level_action_sheet.dart';
import 'app_state.dart';
import '../features/companion/companion_shell.dart';

final GlobalKey<NavigatorState> lensNavigatorKey = GlobalKey<NavigatorState>();

class LensAppHost extends StatefulWidget {
  const LensAppHost({super.key, required this.state});

  final AppState state;

  @override
  State<LensAppHost> createState() => _LensAppHostState();
}

class _LensAppHostState extends State<LensAppHost> {
  static const MethodChannel _fileOpenChannel = MethodChannel(
    'lingfer/file_open',
  );

  final List<String> _pendingOpenPaths = <String>[];
  bool _flushScheduled = false;
  String? _lastOpenedPath;

  @override
  void initState() {
    super.initState();

    _fileOpenChannel.setMethodCallHandler((call) async {
      if (call.method != 'openFile') return;
      final arg = call.arguments;
      if (arg is! String || arg.isEmpty) return;
      _enqueueExternalOpen(arg);
    });

    _schedulePendingFlush();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _enqueueExternalOpen(String path) {
    _pendingOpenPaths.add(path);
    _schedulePendingFlush();
  }

  void _openFileFromExternal(String path) {
    final lower = path.toLowerCase();
    if (!lower.endsWith('.txt') &&
        !lower.endsWith('.epub') &&
        !lower.endsWith('.docx') &&
        !lower.endsWith('.pdf') &&
        !lower.endsWith('.png') &&
        !lower.endsWith('.jpg') &&
        !lower.endsWith('.jpeg') &&
        !lower.endsWith('.heic') &&
        !lower.endsWith('.webp')) {
      return;
    }
    if (_lastOpenedPath == path) return;
    _lastOpenedPath = path;

    // When invoked via Finder, the file may be security-scoped. We rely on the
    // native side to startAccessingSecurityScopedResource().
    if (!File(path).existsSync()) return;

    final navigator = lensNavigatorKey.currentState;
    if (navigator == null) {
      _pendingOpenPaths.add(path);
      _schedulePendingFlush();
      return;
    }

    () async {
      await widget.state.initialize();
      if (!mounted) return;
      final ctx = lensNavigatorKey.currentContext;
      VocabularyLevel? level;
      if (ctx == null || !ctx.mounted) {
        level = VocabularyLevel.cet4;
      } else {
        level = await showVocabularyLevelActionSheet(
          ctx,
          selected: VocabularyLevel.cet4,
          message: '通过 Finder 打开文件时，请选择这本书的目标难度。',
        );
        if (level == null) return;
      }

      final originalName = path.split(Platform.pathSeparator).last;
      final title = originalName.replaceAll(
        RegExp(
          r'\.(txt|epub|docx|pdf|png|jpg|jpeg|heic|webp)$',
          caseSensitive: false,
        ),
        '',
      );
      late final Book book;
      if (lower.endsWith('.png') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.heic') ||
          lower.endsWith('.webp')) {
        final doc = await ScanBookStore.create(
          title: title.isEmpty ? ScanBookStore.defaultTitle() : title,
          firstImagePath: path,
        );
        book = Book(
          title: doc.title,
          author: '图片导入',
          defaultLevel: level,
          source: BookSource.localFile,
          locator: doc.path,
          coverFilePath: doc.coverPath,
        );
      } else {
        final storedPath = await ImportedFileStore.ingest(path);
        book = Book(
          title: title.isEmpty ? originalName : title,
          author: '本地导入',
          defaultLevel: level,
          source: BookSource.localFile,
          locator: storedPath,
        );
      }

      // Persist into shelf so it appears in Tab 1.
      await widget.state.addToShelf(book);
      if (book.isScanDocument) {
        navigator.push(
          CupertinoPageRoute<void>(
            builder: (_) => ScanReaderPage(
              scanDocumentPath: book.locator,
              initialLevel: book.defaultLevel,
              bookTitle: book.title,
              sourceLabel: book.author,
            ),
          ),
        );
      } else if (lower.endsWith('.pdf')) {
        navigator.push(
          CupertinoPageRoute<void>(builder: (_) => PdfReaderPage(book: book)),
        );
      } else {
        navigator.push(
          CupertinoPageRoute<void>(builder: (_) => ReadingScreen(book: book)),
        );
      }
    }();
  }

  void _schedulePendingFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (_pendingOpenPaths.isEmpty) return;
      final pending = List<String>.from(_pendingOpenPaths);
      _pendingOpenPaths.clear();
      for (final path in pending) {
        _openFileFromExternal(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const CompanionShell();
  }
}

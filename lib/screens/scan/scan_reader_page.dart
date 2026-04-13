import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../app/app_state.dart';
import '../../models/book.dart';
import '../../models/translation_mode.dart';
import '../../models/vocabulary_level.dart';
import '../../services/ai_translation_service.dart';
import '../../services/scan_book_store.dart';
import '../../widgets/apple_glass_sheet.dart';
import '../../widgets/liquid_selection_controls.dart';
import '../../widgets/scan_import_sort_page.dart';

const String _deepSeekProxyUrl =
    String.fromEnvironment('DEEPSEEK_PROXY_URL', defaultValue: '');
const String _appSecret = String.fromEnvironment('APP_SECRET', defaultValue: '');

/// Photo-based OCR reader for homework scenarios.
///
/// The image itself keeps a transparent selectable OCR layer so users can
/// long-press directly on the photo, while the text below is a cleaner
/// body-text rendition refined by AI.
class ScanReaderPage extends StatefulWidget {
  const ScanReaderPage({
    super.key,
    this.imagePath,
    this.scanDocumentPath,
    this.initialLevel = VocabularyLevel.cet6,
    this.bookTitle,
    this.sourceLabel,
    this.initialPageIndex = 0,
  });

  final String? imagePath;
  final String? scanDocumentPath;
  final VocabularyLevel initialLevel;
  final String? bookTitle;
  final String? sourceLabel;
  final int initialPageIndex;

  @override
  State<ScanReaderPage> createState() => _ScanReaderPageState();
}

class _ScanReaderPageState extends State<ScanReaderPage> {
  static const MethodChannel _visionOcr = MethodChannel('lingfer/vision_ocr');

  late final AiTranslationService _ai = AiTranslationService(
    proxyUrl: _deepSeekProxyUrl,
    appSecret: _appSecret,
  );

  bool _loading = true;
  String? _error;
  String _rawText = '';
  String _displayText = '';
  bool _refiningText = false;
  Size? _imageSize;
  List<_OcrLine> _overlayLines = const [];
  int _ocrRevision = 0;
  String? _scanDocumentPath;
  String? _scanTitle;
  List<String> _pages = const <String>[];
  Map<String, ScanBookOcrCache> _pageCaches = const <String, ScanBookOcrCache>{};
  int _currentPageIndex = 0;
  bool _loadingDocument = false;
  bool _inlineVocabEnabled = true;
  bool _annotatingText = false;
  String? _annotatedText;
  String? _annotatedError;
  late final PageController _pageController;

  final ValueNotifier<String> _glassSelectedText = ValueNotifier<String>('');
  bool _glassVisible = false;
  AppleGlassDock _glassDock = AppleGlassDock.bottom;
  Offset? _lastPointerDownGlobal;
  Timer? _glassDebounce;
  String? _pendingGlassText;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialPageIndex);
    _bootstrap();
  }

  @override
  void dispose() {
    _glassDebounce?.cancel();
    _glassSelectedText.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _scanDocumentPath = widget.scanDocumentPath;
    _currentPageIndex = widget.initialPageIndex;
    if (_scanDocumentPath != null) {
      await _loadScanDocument();
    } else {
      await _runOcr();
    }
  }

  String? get _activeImagePath {
    if (_pages.isNotEmpty) {
      final idx = _currentPageIndex.clamp(0, _pages.length - 1);
      return _pages[idx];
    }
    return widget.imagePath;
  }

  bool get _isScanBook => _scanDocumentPath != null;

  String get _previewImagePath => _activeImagePath ?? '';

  String get _displayTitle {
    final scanTitle = _scanTitle?.trim();
    if (scanTitle != null && scanTitle.isNotEmpty) return scanTitle;
    final provided = widget.bookTitle?.trim();
    if (provided != null && provided.isNotEmpty) return provided;
    final current = _activeImagePath ?? widget.imagePath ?? '';
    final name = current.split(Platform.pathSeparator).last;
    return name.replaceAll(
      RegExp(r'\.(png|jpg|jpeg|heic|webp)$', caseSensitive: false),
      '',
    );
  }

  Size get _effectiveImageSize => _imageSize ?? const Size(1, 1);

  String get _visibleBodyText {
    final cleaned = _displayText.trim();
    final annotated = (_annotatedText ?? '').trim();
    if (_inlineVocabEnabled && annotated.isNotEmpty) {
      return annotated;
    }
    return cleaned.isNotEmpty ? cleaned : _rawText;
  }

  TranslationMode _inferMode(String text) {
    final cjk = RegExp(r'[\u4E00-\u9FFF]').allMatches(text).length;
    final latin = RegExp(r'[A-Za-z]').allMatches(text).length;
    return cjk >= latin ? TranslationMode.zhToEn : TranslationMode.enToZh;
  }

  String _annotationCacheKey(String text) {
    final mode = _inferMode(text);
    return '${widget.initialLevel.name}_${mode.name}';
  }

  Future<void> _persistCurrentPageCache({
    required String rawText,
    required String cleanedText,
    required Size imageSize,
    required List<_OcrLine> lines,
    String? annotatedText,
  }) async {
    final manifest = _scanDocumentPath;
    final pagePath = _activeImagePath;
    if (manifest == null || pagePath == null || pagePath.isEmpty) return;

    final current = _pageCaches[pagePath];
    final annotatedTexts = <String, String>{
      ...?current?.annotatedTexts,
    };
    final cleaned = cleanedText.trim();
    if (annotatedText != null && cleaned.isNotEmpty) {
      annotatedTexts[_annotationCacheKey(cleaned)] = annotatedText;
    }

    final cache = ScanBookOcrCache(
      rawText: rawText,
      cleanedText: cleanedText,
      imageWidth: imageSize.width,
      imageHeight: imageSize.height,
      lines: lines
          .map(
            (line) => ScanBookOcrLine(
              text: line.text,
              left: line.left,
              top: line.top,
              width: line.width,
              height: line.height,
            ),
          )
          .toList(growable: false),
      annotatedTexts: annotatedTexts,
    );

    _pageCaches = <String, ScanBookOcrCache>{
      ..._pageCaches,
      pagePath: cache,
    };
    await ScanBookStore.updatePageCache(
      manifestPath: manifest,
      pagePath: pagePath,
      cache: cache,
    );
  }

  Future<void> _restoreFromCache(String pagePath, ScanBookOcrCache cache) async {
    final cleaned = cache.cleanedText.trim();
    final raw = cache.rawText.trim();
    final display = cleaned.isNotEmpty ? cleaned : raw;
    final annotated = cache.annotatedTexts[_annotationCacheKey(display)];

    setState(() {
      _loading = false;
      _error = display.isEmpty ? '未识别到文字，请换一张更清晰的照片' : null;
      _rawText = cache.rawText;
      _displayText = display;
      _overlayLines = cache.lines
          .map(
            (line) => _OcrLine(
              text: line.text,
              left: line.left,
              top: line.top,
              width: line.width,
              height: line.height,
            ),
          )
          .toList(growable: false);
      _imageSize = Size(cache.imageWidth, cache.imageHeight);
      _refiningText = false;
      _annotatedText = annotated;
      _annotatingText = false;
      _annotatedError = null;
    });

    if (_inlineVocabEnabled && annotated == null && display.isNotEmpty) {
      unawaited(_annotateDisplayText(display, _ocrRevision));
    }
  }

  Future<void> _loadScanDocument() async {
    final manifest = _scanDocumentPath;
    if (manifest == null) return;
    setState(() => _loadingDocument = true);
    final doc = await ScanBookStore.load(manifest);
    if (!mounted) return;
    if (doc == null || doc.pages.isEmpty) {
      setState(() {
        _loadingDocument = false;
        _error = '扫描册数据已损坏或页面为空';
      });
      return;
    }
    final nextIndex = _currentPageIndex.clamp(0, doc.pages.length - 1);
    setState(() {
      _scanTitle = doc.title;
      _pages = doc.pages.map((e) => e.path).toList(growable: false);
      _pageCaches = <String, ScanBookOcrCache>{
        for (final page in doc.pages)
          if (page.cache != null) page.path: page.cache!,
      };
      _currentPageIndex = nextIndex;
      _loadingDocument = false;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(nextIndex);
    }
    await _runOcr();
  }

  Future<void> _runOcr() async {
    final path = _activeImagePath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      setState(() {
        _loading = false;
        _error = '图片不存在或无法读取';
      });
      return;
    }

    final revision = ++_ocrRevision;
    setState(() {
      _loading = true;
      _error = null;
      _rawText = '';
      _displayText = '';
      _refiningText = false;
      _annotatedText = null;
      _annotatedError = null;
      _annotatingText = false;
      _overlayLines = const [];
      _imageSize = null;
    });

    try {
      final cached = _pageCaches[path];
      if (cached != null) {
        await _restoreFromCache(path, cached);
        return;
      }

      final next = await _ocrTextForPath(path);
      if (!mounted || revision != _ocrRevision) return;

      final localCleaned = _cleanOcrTextLocally(next.text);
      final initialDisplay = localCleaned.isEmpty ? next.text : localCleaned;

      setState(() {
        _loading = false;
        _rawText = next.text;
        _displayText = initialDisplay;
        _refiningText = next.text.trim().isNotEmpty;
        _overlayLines = next.lines;
        _imageSize = next.imageSize;
        _error = next.text.trim().isEmpty ? '未识别到文字，请换一张更清晰的照片' : null;
      });
      await _persistCurrentPageCache(
        rawText: next.text,
        cleanedText: initialDisplay,
        imageSize: next.imageSize,
        lines: next.lines,
      );

      if (next.text.trim().isNotEmpty) {
        unawaited(_refineTextWithAi(next.text, initialDisplay, revision));
        if (_inlineVocabEnabled) {
          unawaited(_annotateDisplayText(initialDisplay, revision));
        }
      }
    } catch (e) {
      if (!mounted || revision != _ocrRevision) return;
      setState(() {
        _loading = false;
        _error = '识别失败，请稍后重试';
      });
    }
  }

  Future<void> _refineTextWithAi(
    String raw,
    String localFallback,
    int revision,
  ) async {
    final refined = await _ai.cleanupOcrPlainText(raw: raw);
    if (!mounted || revision != _ocrRevision) return;
    final cleaned = refined.trim().isEmpty ? localFallback : refined.trim();
    setState(() {
      _refiningText = false;
      _displayText = cleaned;
    });
    await _persistCurrentPageCache(
      rawText: raw,
      cleanedText: cleaned,
      imageSize: _effectiveImageSize,
      lines: _overlayLines,
      annotatedText: _annotatedText,
    );
    if (_inlineVocabEnabled && cleaned.isNotEmpty) {
      unawaited(_annotateDisplayText(cleaned, revision));
    }
  }

  Future<void> _annotateDisplayText(String cleanedText, int revision) async {
    final trimmed = cleanedText.trim();
    if (trimmed.isEmpty) return;

    final pagePath = _activeImagePath;
    if (pagePath != null) {
      final cached = _pageCaches[pagePath];
      final cachedText = cached?.annotatedTexts[_annotationCacheKey(trimmed)];
      if (cachedText != null && cachedText.trim().isNotEmpty) {
        if (!mounted || revision != _ocrRevision) return;
        setState(() {
          _annotatedText = cachedText;
          _annotatingText = false;
          _annotatedError = null;
        });
        return;
      }
    }

    if (!mounted || revision != _ocrRevision) return;
    setState(() {
      _annotatingText = true;
      _annotatedError = null;
    });

    final annotated = await _ai.translateChunk(
      raw: trimmed,
      level: widget.initialLevel,
      mode: _inferMode(trimmed),
    );
    if (!mounted || revision != _ocrRevision) return;

    final resolved = annotated.trim().isEmpty ? trimmed : annotated.trim();
    setState(() {
      _annotatingText = false;
      _annotatedText = resolved;
      _annotatedError = null;
    });
    await _persistCurrentPageCache(
      rawText: _rawText,
      cleanedText: _displayText,
      imageSize: _effectiveImageSize,
      lines: _overlayLines,
      annotatedText: resolved,
    );
  }

  Future<_OcrResult> _ocrTextForPath(String path) async {
    final imageSize = await _readImageDimensions(path);

    if (Platform.isIOS) {
      try {
        final payload = await _visionOcr.invokeMethod<Object?>(
          'recognizeTextLayout',
          {'path': path},
        );
        if (payload is Map) {
          return _parseVisionLayoutPayload(payload, imageSize);
        }
      } catch (_) {}

      try {
        final text = await _visionOcr
            .invokeMethod<String>('recognizeText', {'path': path});
        return _OcrResult(
          text: (text ?? '').trim(),
          imageSize: imageSize,
          lines: _synthesizeOcrLines((text ?? '').trim(), imageSize),
        );
      } catch (_) {
        return _OcrResult(
          text: '',
          imageSize: imageSize,
          lines: const <_OcrLine>[],
        );
      }
    }

    final input = InputImage.fromFilePath(path);
    final latin =
        await _recognizeWithScript(input, TextRecognitionScript.latin);
    final chinese =
        await _recognizeWithScript(input, TextRecognitionScript.chinese);
    final best = latin.score >= chinese.score ? latin : chinese;
    return _OcrResult(
      text: best.text.trim(),
      imageSize: imageSize,
      lines: best.lines.isNotEmpty
          ? best.lines
          : _synthesizeOcrLines(best.text.trim(), imageSize),
    );
  }

  Future<_OcrCandidate> _recognizeWithScript(
    InputImage input,
    TextRecognitionScript script,
  ) async {
    final recognizer = TextRecognizer(script: script);
    try {
      final result = await recognizer.processImage(input);
      final text = result.text.trim();
      final lines = <_OcrLine>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final raw = line.text.trim();
          if (raw.isEmpty) continue;
          final rect = line.boundingBox;
          lines.add(
            _OcrLine(
              text: raw,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
            ),
          );
        }
      }
      return _OcrCandidate(
        text: text,
        score: _ocrScore(text),
        script: script,
        lines: lines,
      );
    } catch (_) {
      return _OcrCandidate(
        text: '',
        score: 0,
        script: script,
        lines: const <_OcrLine>[],
      );
    } finally {
      await recognizer.close();
    }
  }

  _OcrResult _parseVisionLayoutPayload(
    Map payload,
    Size fallbackSize,
  ) {
    final text = (payload['text'] ?? '').toString().trim();
    final width = _asDouble(payload['imageWidth']) ?? fallbackSize.width;
    final height = _asDouble(payload['imageHeight']) ?? fallbackSize.height;
    final lines = <_OcrLine>[];
    final rawLines = payload['lines'];
    if (rawLines is List) {
      for (final item in rawLines) {
        if (item is! Map) continue;
        final lineText = (item['text'] ?? '').toString().trim();
        final left = _asDouble(item['left']) ?? 0;
        final top = _asDouble(item['top']) ?? 0;
        final lineWidth = _asDouble(item['width']) ?? 0;
        final lineHeight = _asDouble(item['height']) ?? 0;
        if (lineText.isEmpty || lineWidth <= 0 || lineHeight <= 0) continue;
        lines.add(
          _OcrLine(
            text: lineText,
            left: left,
            top: top,
            width: lineWidth,
            height: lineHeight,
          ),
        );
      }
    }
    return _OcrResult(
      text: text,
      imageSize: Size(width, height),
      lines: lines.isNotEmpty ? lines : _synthesizeOcrLines(text, Size(width, height)),
    );
  }

  List<_OcrLine> _synthesizeOcrLines(String text, Size imageSize) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || imageSize.width <= 1 || imageSize.height <= 1) {
      return const <_OcrLine>[];
    }

    final lines = trimmed
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return const <_OcrLine>[];

    final maxCount = math.min(lines.length, 30);
    final horizontalInset = imageSize.width * 0.08;
    final usableWidth = math.max(80.0, imageSize.width - horizontalInset * 2);
    final lineHeight =
        (imageSize.height / math.max(maxCount + 6, 18)).clamp(22.0, 40.0);
    final topInset = imageSize.height * 0.1;

    return List<_OcrLine>.generate(maxCount, (index) {
      return _OcrLine(
        text: lines[index],
        left: horizontalInset,
        top: topInset + index * lineHeight * 1.18,
        width: usableWidth,
        height: lineHeight,
      );
    }, growable: false);
  }

  double? _asDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<Size> _readImageDimensions(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return const Size(1, 1);
      return Size(decoded.width.toDouble(), decoded.height.toDouble());
    } catch (_) {
      return const Size(1, 1);
    }
  }

  int _ocrScore(String text) {
    if (text.trim().isEmpty) return 0;
    final alpha = RegExp(r'[A-Za-z]').allMatches(text).length;
    final digit = RegExp(r'\d').allMatches(text).length;
    final cjk = RegExp(r'[\u4E00-\u9FFF]').allMatches(text).length;
    final useful = alpha + digit + cjk;
    if (useful <= 0) return 0;
    final lenBonus = text.length > 2400 ? 2400 : text.length;
    return useful * 20 + lenBonus;
  }

  String _cleanOcrTextLocally(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final filtered = normalized
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where(_looksLikeBodyLine)
        .toList();

    if (filtered.isEmpty) return normalized.trim();

    final buffer = StringBuffer();
    String? previous;
    for (final line in filtered) {
      if (previous == null) {
        buffer.write(line);
        previous = line;
        continue;
      }

      if (_startsNewParagraph(previous, line)) {
        buffer.write('\n\n');
        buffer.write(line);
      } else {
        if (_needsSpace(previous, line)) {
          buffer.write(' ');
        }
        buffer.write(line);
      }
      previous = line;
    }

    return buffer.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  bool _looksLikeBodyLine(String line) {
    if (line.isEmpty) return false;
    if (RegExp(r'^(第?\s*\d+\s*页|\d+\s*/\s*\d+|\d+)$').hasMatch(line)) {
      return false;
    }
    final useful = RegExp(r'[A-Za-z0-9\u4E00-\u9FFF]').allMatches(line).length;
    if (useful == 0) return false;

    final whitespace = RegExp(r'\s').allMatches(line).length;
    final symbolCount = math.max(0, line.length - useful - whitespace);
    if (useful == 1 && line.length <= 1) return false;
    if (symbolCount > useful * 2 &&
        !RegExp(r'[，。！？,.!?：:;；（）()《》“”"\[\]-]').hasMatch(line)) {
      return false;
    }
    return true;
  }

  bool _startsNewParagraph(String previous, String next) {
    if (previous.isEmpty || next.isEmpty) return false;
    if (RegExp(r'[。！？.!?：:]$').hasMatch(previous)) return true;
    if (next.length <= 8 && !RegExp(r'[，。！？,.!?]').hasMatch(next)) {
      return true;
    }
    return false;
  }

  bool _needsSpace(String previous, String next) {
    if (previous.isEmpty || next.isEmpty) return false;
    final prev = previous.codeUnitAt(previous.length - 1);
    final nextCode = next.codeUnitAt(0);
    final prevAscii = (prev >= 48 && prev <= 57) ||
        (prev >= 65 && prev <= 90) ||
        (prev >= 97 && prev <= 122);
    final nextAscii = (nextCode >= 48 && nextCode <= 57) ||
        (nextCode >= 65 && nextCode <= 90) ||
        (nextCode >= 97 && nextCode <= 122);
    return prevAscii && nextAscii;
  }

  Future<void> _renameScanBook() async {
    final manifest = _scanDocumentPath;
    if (manifest == null) return;

    final controller = TextEditingController(text: _displayTitle);
    final nextTitle = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: const Text('重命名扫描册'),
          content: Column(
            children: [
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                clearButtonMode: OverlayVisibilityMode.editing,
                placeholder: '输入书名或章节名',
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

    final title = nextTitle?.trim();
    if (title == null || title.isEmpty) return;

    final doc = await ScanBookStore.rename(
      manifestPath: manifest,
      title: title,
    );
    if (!mounted || doc == null) return;

    final oldTitle = _scanTitle ?? widget.bookTitle ?? _displayTitle;
    final appState = AppScope.of(context);
    final existingBook = appState.shelf.cast<Book?>().firstWhere(
          (book) => book?.locator == manifest,
          orElse: () => null,
        );
    final oldBook = Book(
      title: oldTitle,
      author: '${_pages.isEmpty ? 1 : _pages.length} 页扫描',
      defaultLevel: widget.initialLevel,
      source: BookSource.localFile,
      locator: manifest,
      coverFilePath: doc.coverPath,
    );
    final newBook = doc.toBook(
      widget.initialLevel,
      isPinned: existingBook?.isPinned ?? false,
    );
    await appState.replaceBook(oldId: oldBook.stableKey, newBook: newBook);

    if (!mounted) return;
    setState(() => _scanTitle = doc.title);
  }

  Future<void> _addPage() async {
    final action = await showCupertinoModalPopup<_AddScanPageAction>(
      context: context,
      builder: (ctx) {
        return CupertinoActionSheet(
          title: const Text('添加页面'),
          message: const Text('继续为这本扫描册追加新的一页。'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(_AddScanPageAction.camera),
              child: const Text('拍照添加'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(_AddScanPageAction.gallery),
              child: const Text('从相册添加'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(_AddScanPageAction.file),
              child: const Text('从文件添加'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        );
      },
    );
    if (action == null) return;

    List<String> paths = const <String>[];
    switch (action) {
      case _AddScanPageAction.camera:
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
          return;
        }
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        final photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
        );
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        final path = photo?.path;
        if (path != null && path.isNotEmpty) {
          paths = <String>[path];
        }
        break;
      case _AddScanPageAction.gallery:
        final photos = await ImagePicker().pickMultiImage(imageQuality: 92);
        paths = photos
            .map((photo) => photo.path)
            .where((path) => path.trim().isNotEmpty)
            .toList(growable: false);
        break;
      case _AddScanPageAction.file:
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['png', 'jpg', 'jpeg', 'heic', 'webp'],
          allowMultiple: true,
        );
        paths = (result == null || result.files.isEmpty)
            ? const <String>[]
            : result.files
                .map((file) => file.path ?? '')
                .where((path) => path.trim().isNotEmpty)
                .toList(growable: false);
        break;
    }

    if (!mounted || paths.isEmpty) return;
    if (paths.length > 1) {
      final ordered = await Navigator.of(context, rootNavigator: true).push<List<String>>(
        CupertinoPageRoute<List<String>>(
          builder: (_) => ScanImportSortPage(
            paths: paths,
            title: '调整新增页面顺序',
          ),
        ),
      );
      if (!mounted || ordered == null || ordered.isEmpty) return;
      paths = ordered;
    }
    final currentImagePath = _activeImagePath;

    if (_scanDocumentPath == null) {
      if (currentImagePath == null || currentImagePath.isEmpty) return;
      final doc = await ScanBookStore.create(
        title: _displayTitle,
        firstImagePath: currentImagePath,
      );
      _scanDocumentPath = doc.path;
      _scanTitle = doc.title;
      _pages = doc.pages.map((e) => e.path).toList(growable: false);
      _currentPageIndex = 0;
    }

    final doc = await ScanBookStore.appendPages(
      manifestPath: _scanDocumentPath!,
      imagePaths: paths,
    );
    if (!mounted || doc == null) return;

    final appState = AppScope.of(context);
    final existingBook = appState.shelf.cast<Book?>().firstWhere(
          (book) => book?.locator == doc.path,
          orElse: () => null,
        );
    final updatedBook = doc.toBook(
      widget.initialLevel,
      isPinned: existingBook?.isPinned ?? false,
    );
    if (existingBook == null) {
      await appState.addToShelf(updatedBook);
    } else {
      await appState.replaceBook(
        oldId: existingBook.stableKey,
        newBook: updatedBook,
      );
    }

    setState(() {
      _scanTitle = doc.title;
      _pages = doc.pages.map((e) => e.path).toList(growable: false);
      _pageCaches = <String, ScanBookOcrCache>{
        for (final page in doc.pages)
          if (page.cache != null) page.path: page.cache!,
      };
      _currentPageIndex = _pages.length - paths.length;
      _glassVisible = false;
    });
    _pageController.jumpToPage(_currentPageIndex);
    await _runOcr();
  }

  void _openZoomViewer() {
    final active = _activeImagePath;
    if (active == null || active.isEmpty) return;
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => _ScanZoomPage(
          imagePath: active,
          imageSize: _effectiveImageSize,
          overlayLines: _overlayLines,
          fullText: _visibleBodyText.trim().isNotEmpty ? _visibleBodyText : _rawText,
          initialLevel: widget.initialLevel,
          ai: _ai,
          title: _displayTitle,
        ),
      ),
    );
  }

  Future<void> _handlePreviewPageChanged(int index) async {
    if (index == _currentPageIndex || index < 0 || index >= _pages.length) {
      return;
    }
    setState(() {
      _currentPageIndex = index;
      _glassVisible = false;
    });
    await _runOcr();
  }

  Future<void> _jumpToPage(int index) async {
    if (index < 0 || index >= _pages.length) return;
    if (_pageController.hasClients) {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _handlePreviewPageChanged(index);
  }

  Future<void> _openPageEditor() async {
    final manifest = _scanDocumentPath;
    if (manifest == null || _pages.isEmpty) return;

    final orderedPaths = await Navigator.of(context, rootNavigator: true).push<List<String>>(
      CupertinoPageRoute<List<String>>(
        builder: (_) => _ScanPageEditor(
          title: _displayTitle,
          pages: _pages,
          currentPageIndex: _currentPageIndex,
        ),
      ),
    );
    if (!mounted || orderedPaths == null) return;

    final appState = AppScope.of(context);
    final existingBook = appState.shelf.cast<Book?>().firstWhere(
          (book) => book?.locator == manifest,
          orElse: () => null,
        );
    final currentPath = _activeImagePath;
    final doc = await ScanBookStore.syncPages(
      manifestPath: manifest,
      orderedPagePaths: orderedPaths,
    );

    if (!mounted) return;
    if (doc == null) {
      if (existingBook != null) {
        await appState.removeFromShelf(existingBook);
      }
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }

    final updatedBook = doc.toBook(
      widget.initialLevel,
      isPinned: existingBook?.isPinned ?? false,
    );
    if (existingBook == null) {
      await appState.addToShelf(updatedBook);
    } else {
      await appState.replaceBook(
        oldId: existingBook.stableKey,
        newBook: updatedBook,
      );
    }

    final nextPages = doc.pages.map((e) => e.path).toList(growable: false);
    final currentIndex = currentPath == null ? 0 : nextPages.indexOf(currentPath);
    final nextIndex = (currentIndex < 0 ? 0 : currentIndex).clamp(0, nextPages.length - 1);

    setState(() {
      _scanTitle = doc.title;
      _pages = nextPages;
      _pageCaches = <String, ScanBookOcrCache>{
        for (final page in doc.pages)
          if (page.cache != null) page.path: page.cache!,
      };
      _currentPageIndex = nextIndex;
      _glassVisible = false;
    });
    _pageController.jumpToPage(nextIndex);
    await _runOcr();
  }

  void _toggleInlineVocab() {
    final next = !_inlineVocabEnabled;
    setState(() => _inlineVocabEnabled = next);
    if (next && _annotatedText == null && _displayText.trim().isNotEmpty) {
      unawaited(_annotateDisplayText(_displayText, _ocrRevision));
    }
  }

  void _onSelectionChanged(SelectedContent? content) {
    final raw = (content?.plainText ?? '').trim();
    if (raw.isEmpty) return;

    final y = _lastPointerDownGlobal?.dy;
    final h = MediaQuery.sizeOf(context).height;
    final nextDock =
        (y != null && y > h * 0.5) ? AppleGlassDock.top : AppleGlassDock.bottom;
    if (!_glassVisible || nextDock != _glassDock) {
      setState(() {
        _glassVisible = true;
        _glassDock = nextDock;
      });
    }

    _pendingGlassText = raw;
    _glassDebounce?.cancel();
    _glassDebounce = Timer(const Duration(milliseconds: 220), () {
      final stable = _pendingGlassText;
      if (!mounted || stable == null) return;
      final trimmed = stable.trim();
      if (trimmed.isEmpty) return;

      final expanded = _glassSelectedText.value.isEmpty
          ? _expandSelection(trimmed)
          : trimmed;
      if (_glassSelectedText.value != expanded) {
        _glassSelectedText.value = expanded;
      }
    });
  }

  String _expandSelection(String selected) {
    final fromCleaned = _smartExpandToSentence(_displayText, selected);
    if (fromCleaned != selected) return fromCleaned;
    return _smartExpandToSentence(_rawText, selected);
  }

  String _smartExpandToSentence(String full, String needle) {
    final t = needle.trim();
    if (t.isEmpty) return t;
    if (t.length > 80) return t;
    if (full.trim().isEmpty) return t;

    var pos = full.indexOf(t);
    if (pos < 0) {
      final lowerFull = full.toLowerCase();
      final lowerNeedle = t.toLowerCase();
      pos = lowerFull.indexOf(lowerNeedle);
      if (pos < 0) return t;
    }

    var start = pos;
    for (var i = pos - 1; i >= 0; i -= 1) {
      final ch = full.codeUnitAt(i);
      if (_isSentenceBoundary(ch)) {
        start = i + 1;
        break;
      }
      if (i == 0) start = 0;
    }

    var end = pos + t.length;
    for (var i = end; i < full.length; i += 1) {
      final ch = full.codeUnitAt(i);
      if (_isSentenceBoundary(ch)) {
        end = i + 1;
        break;
      }
      if (i == full.length - 1) end = full.length;
    }

    final sentence = full.substring(start, end).trim();
    if (sentence.isEmpty) return t;
    return sentence;
  }

  bool _isSentenceBoundary(int codeUnit) {
    switch (codeUnit) {
      case 0x0A:
      case 0x0D:
      case 0x2E:
      case 0x3F:
      case 0x21:
      case 0x3002:
      case 0xFF1F:
      case 0xFF01:
        return true;
      default:
        return false;
    }
  }

  bool _shouldKeepOverlayLine(_OcrLine line) {
    return line.text.trim().isNotEmpty && line.width > 8 && line.height > 8;
  }

  Widget _buildImageSelectionCard() {
    final previewPaths = _pages.isEmpty ? <String>[_previewImagePath] : _pages;
    const previewHeight = 364.0;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFCFFFFFF),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x11000000)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 36,
            offset: Offset(0, 22),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                height: previewHeight,
                color: const Color(0xFFF7F5EF),
                child: material.LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return PageView.builder(
                      controller: _pageController,
                      physics: previewPaths.length > 1
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: previewPaths.length,
                      onPageChanged: (index) {
                        unawaited(_handlePreviewPageChanged(index));
                      },
                      itemBuilder: (context, index) {
                        final pagePath = previewPaths[index];
                        final isCurrent = index == _currentPageIndex;
                        final height = previewHeight;
                        final imageRect = _resolveContainedImageRect(
                          viewportSize: Size(width, height),
                          imageSize: _effectiveImageSize,
                        );
                        return GestureDetector(
                          onTap: () {
                            if (!isCurrent && _pages.length > 1) {
                              unawaited(_jumpToPage(index));
                              return;
                            }
                            _openZoomViewer();
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned.fromRect(
                                rect: imageRect,
                                child: material.Image.file(
                                  File(pagePath),
                                  fit: material.BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Color(0xFFF2F2F7),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        CupertinoIcons.photo,
                                        color: Color(0xFF8E8E93),
                                        size: 44,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (isCurrent)
                                ..._overlayLines
                                    .where(_shouldKeepOverlayLine)
                                    .map((line) => _buildOverlayLine(line, imageRect)),
                              if (isCurrent && _loading)
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CupertinoColors.white.withValues(alpha: 0.92),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: const Color(0x12000000)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CupertinoActivityIndicator(radius: 7),
                                          SizedBox(width: 8),
                                          Text(
                                            '正在识别这一页',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF4A4A4F),
                                              decoration: TextDecoration.none,
                                              fontFamily: '.SF UI Text',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            if (_pages.length > 1) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _pages.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final selected = index == _currentPageIndex;
                    final pagePath = _pages[index];
                    return GestureDetector(
                      onTap: () => _jumpToPage(index),
                      child: Container(
                        width: 70,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFF1ECE2)
                              : CupertinoColors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF8E7B59)
                                : const Color(0x10000000),
                            width: selected ? 1.3 : 1,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: material.Image.file(
                                  File(pagePath),
                                  fit: material.BoxFit.cover,
                                  errorBuilder:
                                      (context, error, stackTrace) =>
                                          const ColoredBox(
                                    color: Color(0xFFF2F2F7),
                                    child: SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFF1C1C1E)
                                      : const Color(0xCCFFFFFC),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? CupertinoColors.white
                                        : const Color(0xFF4A4A4F),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayLine(_OcrLine line, Rect imageRect) {
    final imageSize = _effectiveImageSize;
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return const SizedBox.shrink();
    }

    final left = imageRect.left + (line.left / imageSize.width) * imageRect.width;
    final top = imageRect.top + (line.top / imageSize.height) * imageRect.height;
    final boxWidth = (line.width / imageSize.width) * imageRect.width;
    final boxHeight = (line.height / imageSize.height) * imageRect.height;

    final safeLeft =
        left.clamp(imageRect.left, math.max(imageRect.left, imageRect.right - 12)).toDouble();
    final safeTop =
        top.clamp(imageRect.top, math.max(imageRect.top, imageRect.bottom - 12)).toDouble();
    final maxWidth = math.max(18.0, imageRect.right - safeLeft);
    final maxHeight = math.max(16.0, imageRect.bottom - safeTop);
    final safeWidth = math.min(math.max(18.0, boxWidth), maxWidth);
    final safeHeight = math.min(math.max(16.0, boxHeight), maxHeight);
    final fontSize = safeHeight.clamp(13.0, 28.0).toDouble() * 0.72;

    return Positioned(
      left: safeLeft,
      top: safeTop,
      width: safeWidth,
      height: safeHeight,
      child: material.Material(
        type: material.MaterialType.transparency,
        child: Text(
          line.text,
          maxLines: 3,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.05,
            color: const Color(0x01000000),
            decoration: TextDecoration.none,
            fontFamily: '.SF UI Text',
          ),
        ),
      ),
    );
  }

  Widget _buildCleanedTextCard() {
    final text = _visibleBodyText.trim().isNotEmpty
        ? _visibleBodyText
        : (_loading ? '图片已导入，正在识别并整理这一页的正文…' : '');
    final toggleLabel = _inlineVocabEnabled ? '关闭插词' : '开启插词';
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFBF8),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x11000000)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 36,
            offset: Offset(0, 22),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'AI 整理后的正文',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E),
                      decoration: TextDecoration.none,
                      fontFamily: '.SF UI Text',
                    ),
                  ),
                ),
                if (_loading || _refiningText || _annotatingText) ...[
                  const CupertinoActivityIndicator(radius: 7),
                  const SizedBox(width: 8),
                  Text(
                    _loading
                        ? 'OCR 识别中'
                        : _refiningText
                            ? 'AI 整理中'
                            : 'AI 插词中',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E6E73),
                      decoration: TextDecoration.none,
                      fontFamily: '.SF UI Text',
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: _toggleInlineVocab,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _inlineVocabEnabled
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFFF0ECE2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      toggleLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _inlineVocabEnabled
                            ? CupertinoColors.white
                            : const Color(0xFF4A4A4F),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _inlineVocabEnabled
                      ? '按当前难度自动插入词义'
                      : '仅显示整理后的纯正文',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8E8E93),
                    decoration: TextDecoration.none,
                    fontFamily: '.SF UI Text',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFEFB),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x12000000)),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.72,
                  color: Color(0xFF1C1C1E),
                  decoration: TextDecoration.none,
                  fontFamily: '.SF UI Text',
                ),
              ),
            ),
            if ((_annotatedError ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _annotatedError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ],
            if ((_error ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8E8E93),
                  decoration: TextDecoration.none,
                  fontFamily: '.SF UI Text',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPageMetaCard() {
    final pageCount = _pages.isEmpty ? 1 : _pages.length;
    final current = _pages.isEmpty ? 1 : _currentPageIndex + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x10000000)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '第 $current / $pageCount 页',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A4A4F),
                decoration: TextDecoration.none,
                fontFamily: '.SF UI Text',
              ),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: _addPage,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.add_circled_solid,
                  size: 18,
                  color: Color(0xFF3D3A34),
                ),
                  SizedBox(width: 6),
                  Text(
                    '添加页面',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF3D3A34),
                  ),
                ),
              ],
            ),
          ),
          if (_isScanBook) ...[
            const SizedBox(width: 10),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _openPageEditor,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.square_list,
                    size: 18,
                    color: Color(0xFF3D3A34),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '页面管理',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF3D3A34),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingBody() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoActivityIndicator(),
          SizedBox(height: 10),
          Text(
            '正在识别图片文字...',
            style: TextStyle(
              color: Color(0xFF6E6E73),
              decoration: TextDecoration.none,
              fontFamily: '.SF UI Text',
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6E6E73),
            decoration: TextDecoration.none,
            fontFamily: '.SF UI Text',
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildContentBody() {
    return material.SelectionArea(
      selectionControls: liquidCupertinoTextSelectionControls,
      onSelectionChanged: _onSelectionChanged,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _lastPointerDownGlobal = e.position,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 14),
              _buildPageMetaCard(),
              const SizedBox(height: 16),
              _buildImageSelectionCard(),
              const SizedBox(height: 18),
              _buildCleanedTextCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x10000000)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 34,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F1F3),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  CupertinoIcons.doc_text_viewfinder,
                  size: 22,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1C1C1E),
                              decoration: TextDecoration.none,
                              fontFamily: '.SF UI Text',
                            ),
                          ),
                        ),
                        if (_isScanBook)
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(32, 32),
                            onPressed: _renameScanBook,
                            child: const Icon(
                              CupertinoIcons.pencil_circle,
                              size: 20,
                              color: Color(0xFF6E6E73),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _isScanBook
                          ? '扫描册'
                          : (widget.sourceLabel?.trim().isNotEmpty == true
                              ? widget.sourceLabel!
                              : '扫描阅读'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6E6E73),
                        decoration: TextDecoration.none,
                        fontFamily: '.SF UI Text',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF6F4EE);
    final title = _displayTitle;
    final hasPreview = (_activeImagePath ?? '').trim().isNotEmpty;

    return material.Scaffold(
      backgroundColor: bg,
      body: material.Material(
        color: bg,
        child: CupertinoPageScaffold(
          backgroundColor: bg,
          navigationBar: CupertinoNavigationBar(
            backgroundColor: bg.withValues(alpha: 0.94),
            border: null,
            middle: Text(title),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Icon(
                CupertinoIcons.chevron_back,
                size: 20,
                color: Color(0xFF3D3A34),
              ),
            ),
          ),
          child: Stack(
            children: [
              SafeArea(
                child: hasPreview
                    ? _buildContentBody()
                    : !hasPreview && _loadingDocument
                        ? _buildLoadingBody()
                        : !hasPreview && _loading
                            ? _buildLoadingBody()
                            : (_error != null)
                                ? _buildErrorBody()
                                : _buildContentBody(),
              ),
              if (_glassVisible)
                Positioned.fill(
                  child: AppleGlassPanel(
                    selectedTextListenable: _glassSelectedText,
                    dock: _glassDock,
                    initialLevel: widget.initialLevel,
                    ai: _ai,
                    onDismiss: () => setState(() => _glassVisible = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OcrResult {
  const _OcrResult({
    required this.text,
    required this.imageSize,
    required this.lines,
  });

  final String text;
  final Size imageSize;
  final List<_OcrLine> lines;
}

class _OcrLine {
  const _OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
}

class _OcrCandidate {
  const _OcrCandidate({
    required this.text,
    required this.score,
    required this.script,
    required this.lines,
  });

  final String text;
  final int score;
  final TextRecognitionScript script;
  final List<_OcrLine> lines;
}

Rect _resolveContainedImageRect({
  required Size viewportSize,
  required Size imageSize,
}) {
  if (viewportSize.width <= 0 || viewportSize.height <= 0) {
    return Rect.zero;
  }
  if (imageSize.width <= 0 || imageSize.height <= 0) {
    return Offset.zero & viewportSize;
  }

  final viewportAspect = viewportSize.width / viewportSize.height;
  final imageAspect = imageSize.width / imageSize.height;
  if (imageAspect >= viewportAspect) {
    final width = viewportSize.width;
    final height = width / imageAspect;
    final top = (viewportSize.height - height) / 2;
    return Rect.fromLTWH(0, top, width, height);
  }

  final height = viewportSize.height;
  final width = height * imageAspect;
  final left = (viewportSize.width - width) / 2;
  return Rect.fromLTWH(left, 0, width, height);
}

enum _AddScanPageAction { camera, gallery, file }

class _ScanPageEditor extends StatefulWidget {
  const _ScanPageEditor({
    required this.title,
    required this.pages,
    required this.currentPageIndex,
  });

  final String title;
  final List<String> pages;
  final int currentPageIndex;

  @override
  State<_ScanPageEditor> createState() => _ScanPageEditorState();
}

class _ScanPageEditorState extends State<_ScanPageEditor> {
  final List<String> _pages = <String>[];

  @override
  void initState() {
    super.initState();
    _pages.addAll(widget.pages);
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF6F4EE);
    return material.Scaffold(
      backgroundColor: bg,
      body: material.Material(
        color: bg,
        child: CupertinoPageScaffold(
          backgroundColor: bg,
          navigationBar: CupertinoNavigationBar(
            backgroundColor: bg.withValues(alpha: 0.94),
            border: null,
            middle: Text(widget.title),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Icon(
                CupertinoIcons.xmark,
                size: 18,
                color: Color(0xFF3D3A34),
              ),
            ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: () => Navigator.of(context).pop(_pages),
              child: const Icon(
                CupertinoIcons.check_mark,
                size: 18,
                color: Color(0xFF3D3A34),
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: CupertinoColors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0x10000000)),
                    ),
                    child: const Text(
                      '拖动可调整顺序，删除错误导入的页面。返回扫描册后会保留已有 OCR 和 AI 整理缓存。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF6E6E73),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: material.ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    itemCount: _pages.length,
                    proxyDecorator: (child, index, animation) => material.Material(
                      color: material.Colors.transparent,
                      child: child,
                    ),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _pages.removeAt(oldIndex);
                        _pages.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final path = _pages[index];
                      final isCurrent = index == widget.currentPageIndex;
                      return Container(
                        key: ValueKey(path),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: CupertinoColors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isCurrent
                                ? const Color(0x22C89B3C)
                                : const Color(0x10000000),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 22,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  width: 54,
                                  height: 72,
                                  child: material.Image.file(
                                    File(path),
                                    fit: material.BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const ColoredBox(
                                      color: Color(0xFFF2F2F7),
                                      child: SizedBox.expand(),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '第 ${index + 1} 页',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1C1C1E),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isCurrent ? '当前阅读页' : '拖动可调整顺序',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF8E8E93),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(34, 34),
                                onPressed: () {
                                  setState(() => _pages.removeAt(index));
                                },
                                child: const Icon(
                                  CupertinoIcons.delete_solid,
                                  color: Color(0xFFFF5A5F),
                                  size: 20,
                                ),
                              ),
                              material.ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(
                                    CupertinoIcons.line_horizontal_3,
                                    color: Color(0xFF8E8E93),
                                  ),
                                ),
                              ),
                            ],
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
    );
  }
}

class _ScanZoomPage extends StatefulWidget {
  const _ScanZoomPage({
    required this.imagePath,
    required this.imageSize,
    required this.overlayLines,
    required this.fullText,
    required this.initialLevel,
    required this.ai,
    required this.title,
  });

  final String imagePath;
  final Size imageSize;
  final List<_OcrLine> overlayLines;
  final String fullText;
  final VocabularyLevel initialLevel;
  final AiTranslationService ai;
  final String title;

  @override
  State<_ScanZoomPage> createState() => _ScanZoomPageState();
}

class _ScanZoomPageState extends State<_ScanZoomPage> {
  final ValueNotifier<String> _selectedText = ValueNotifier<String>('');
  AppleGlassDock _dock = AppleGlassDock.bottom;
  bool _glassVisible = false;
  Offset? _lastPointerDownGlobal;
  Timer? _debounce;
  String? _pending;

  @override
  void dispose() {
    _debounce?.cancel();
    _selectedText.dispose();
    super.dispose();
  }

  void _onSelectionChanged(SelectedContent? content) {
    final raw = (content?.plainText ?? '').trim();
    if (raw.isEmpty) return;
    final y = _lastPointerDownGlobal?.dy;
    final h = MediaQuery.sizeOf(context).height;
    final nextDock =
        (y != null && y > h * 0.5) ? AppleGlassDock.top : AppleGlassDock.bottom;
    if (!_glassVisible || nextDock != _dock) {
      setState(() {
        _glassVisible = true;
        _dock = nextDock;
      });
    }
    _pending = raw;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      final stable = _pending?.trim();
      if (!mounted || stable == null || stable.isEmpty) return;
      _selectedText.value = _smartExpand(widget.fullText, stable);
    });
  }

  String _smartExpand(String full, String needle) {
    if (needle.isEmpty || full.isEmpty) return needle;
    var pos = full.indexOf(needle);
    if (pos < 0) return needle;
    var start = pos;
    for (var i = pos - 1; i >= 0; i -= 1) {
      final ch = full.codeUnitAt(i);
      if (ch == 0x0A || ch == 0x2E || ch == 0x3F || ch == 0x21 || ch == 0x3002) {
        start = i + 1;
        break;
      }
      if (i == 0) start = 0;
    }
    var end = pos + needle.length;
    for (var i = end; i < full.length; i += 1) {
      final ch = full.codeUnitAt(i);
      if (ch == 0x0A || ch == 0x2E || ch == 0x3F || ch == 0x21 || ch == 0x3002) {
        end = i + 1;
        break;
      }
      if (i == full.length - 1) end = full.length;
    }
    final sentence = full.substring(start, end).trim();
    return sentence.isEmpty ? needle : sentence;
  }

  @override
  Widget build(BuildContext context) {
    return material.Scaffold(
      backgroundColor: const Color(0xFFF6F4EE),
      body: material.Material(
        color: const Color(0xFFF6F4EE),
        child: CupertinoPageScaffold(
          backgroundColor: const Color(0xFFF6F4EE),
          navigationBar: CupertinoNavigationBar(
            backgroundColor: const Color(0xFFF6F4EE).withValues(alpha: 0.94),
            border: null,
            middle: Text(widget.title),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Icon(
                CupertinoIcons.chevron_back,
                size: 20,
                color: Color(0xFF3D3A34),
              ),
            ),
          ),
          child: Stack(
            children: [
              SafeArea(
                child: material.LayoutBuilder(
                  builder: (context, constraints) {
                    final viewport = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final imageRect = _resolveContainedImageRect(
                      viewportSize: viewport,
                      imageSize: widget.imageSize,
                    );
                    final displaySize = imageRect.size;

                    return material.SelectionArea(
                      selectionControls: liquidCupertinoTextSelectionControls,
                      onSelectionChanged: _onSelectionChanged,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (e) => _lastPointerDownGlobal = e.position,
                        child: Center(
                          child: material.InteractiveViewer(
                            constrained: false,
                            minScale: 1,
                            maxScale: 4.5,
                            boundaryMargin: const EdgeInsets.all(160),
                            child: SizedBox(
                              width: displaySize.width,
                              height: displaySize.height,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: material.Image.file(
                                      File(widget.imagePath),
                                      fit: material.BoxFit.contain,
                                    ),
                                  ),
                                  ...widget.overlayLines.where((line) {
                                    return line.text.trim().isNotEmpty &&
                                        line.width > 8 &&
                                        line.height > 8;
                                  }).map(
                                    (line) => _ZoomOverlayLine(
                                      line: line,
                                      imageSize: widget.imageSize,
                                      imageRect: Offset.zero & displaySize,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_glassVisible)
                Positioned.fill(
                  child: AppleGlassPanel(
                    selectedTextListenable: _selectedText,
                    dock: _dock,
                    initialLevel: widget.initialLevel,
                    ai: widget.ai,
                    onDismiss: () => setState(() => _glassVisible = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomOverlayLine extends StatelessWidget {
  const _ZoomOverlayLine({
    required this.line,
    required this.imageSize,
    required this.imageRect,
  });

  final _OcrLine line;
  final Size imageSize;
  final Rect imageRect;

  @override
  Widget build(BuildContext context) {
    final left = imageRect.left + (line.left / imageSize.width) * imageRect.width;
    final top = imageRect.top + (line.top / imageSize.height) * imageRect.height;
    final boxWidth = (line.width / imageSize.width) * imageRect.width;
    final boxHeight = (line.height / imageSize.height) * imageRect.height;
    final fontSize = boxHeight.clamp(14.0, 34.0) * 0.72;

    return Positioned(
      left: left,
      top: top,
      width: math.max(24.0, boxWidth),
      height: math.max(18.0, boxHeight),
      child: material.Material(
        type: material.MaterialType.transparency,
        child: Text(
          line.text,
          maxLines: 4,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: fontSize.toDouble(),
            height: 1.05,
            color: const Color(0x01000000),
            decoration: TextDecoration.none,
            fontFamily: '.SF UI Text',
          ),
        ),
      ),
    );
  }
}

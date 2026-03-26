import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../models/vocabulary_level.dart';
import '../../services/ai_translation_service.dart';
import '../../widgets/apple_glass_sheet.dart';

const String _deepSeekProxyUrl =
    String.fromEnvironment('DEEPSEEK_PROXY_URL', defaultValue: '');
const String _appSecret = String.fromEnvironment('APP_SECRET', defaultValue: '');

/// Photo-based OCR reader for homework scenarios.
///
/// This keeps the recognized text fully selectable so users can long-press,
/// adjust selection handles, and invoke the same "Apple Glass" translation
/// panel used in PDF/TXT/EPUB readers.
class ScanReaderPage extends StatefulWidget {
  const ScanReaderPage({
    super.key,
    required this.imagePath,
    this.initialLevel = VocabularyLevel.cet6,
  });

  final String imagePath;
  final VocabularyLevel initialLevel;

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
  String _text = '';
  bool _bwEnhance = false;
  bool _enhancing = false;
  String? _enhancedImagePath;

  // Apple Glass panel state.
  final ValueNotifier<String> _glassSelectedText = ValueNotifier<String>('');
  bool _glassVisible = false;
  AppleGlassDock _glassDock = AppleGlassDock.bottom;
  Offset? _lastPointerDownGlobal;
  Timer? _glassDebounce;
  String? _pendingGlassText;

  @override
  void initState() {
    super.initState();
    _runOcr();
  }

  @override
  void dispose() {
    _glassDebounce?.cancel();
    _glassSelectedText.dispose();
    super.dispose();
  }

  String get _previewImagePath {
    if (_bwEnhance) {
      final enhanced = _enhancedImagePath;
      if (enhanced != null && File(enhanced).existsSync()) return enhanced;
    }
    return widget.imagePath;
  }

  Future<void> _runOcr() async {
    final path = widget.imagePath;
    if (path.isEmpty || !File(path).existsSync()) {
      setState(() {
        _loading = false;
        _error = '图片不存在或无法读取';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _text = '';
    });

    try {
      final ocrPath = _bwEnhance ? await _buildBwEnhancedImage(path) : path;
      final next = await _ocrTextForPath(ocrPath);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _text = next;
        _error = next.isEmpty ? '未识别到文字，请换一张更清晰的照片' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '识别失败，请稍后重试';
      });
    }
  }

  Future<String> _ocrTextForPath(String path) async {
    // iOS: use Apple Vision so we don't rely on MLKit language pods that are
    // downloaded from dl.google.com during `pod install`.
    if (Platform.isIOS) {
      try {
        final text = await _visionOcr
            .invokeMethod<String>('recognizeText', {'path': path});
        return (text ?? '').trim();
      } catch (_) {
        return '';
      }
    }

    final input = InputImage.fromFilePath(path);
    // Android: run both recognizers and pick the better result.
    final latin =
        await _recognizeWithScript(input, TextRecognitionScript.latin);
    final chinese =
        await _recognizeWithScript(input, TextRecognitionScript.chinese);
    return (latin.score >= chinese.score ? latin.text : chinese.text).trim();
  }

  Future<_OcrCandidate> _recognizeWithScript(
    InputImage input,
    TextRecognitionScript script,
  ) async {
    final recognizer = TextRecognizer(script: script);
    try {
      final result = await recognizer.processImage(input);
      final text = (result.text).trim();
      return _OcrCandidate(
        text: text,
        score: _ocrScore(text),
        script: script,
      );
    } catch (_) {
      return _OcrCandidate(text: '', score: 0, script: script);
    } finally {
      await recognizer.close();
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
    // Weight useful characters more heavily than sheer length.
    return useful * 20 + lenBonus;
  }

  Future<String> _buildBwEnhancedImage(String sourcePath) async {
    // Memoize the enhanced image for the current source file.
    final cached = _enhancedImagePath;
    if (cached != null && File(cached).existsSync()) return cached;

    setState(() => _enhancing = true);
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return sourcePath;

      // Grayscale + contrast + simple binarization for OCR.
      final gray = img.grayscale(decoded);
      img.contrast(gray, 155);

      final pix = gray.getBytes();
      int sum = 0;
      for (var i = 0; i < pix.length; i += 4) {
        sum += pix[i];
      }
      final avg = sum ~/ (pix.length ~/ 4);
      final threshold = (avg * 0.92).clamp(70, 200).toInt();
      for (var i = 0; i < pix.length; i += 4) {
        final v = pix[i] >= threshold ? 255 : 0;
        pix[i] = v;
        pix[i + 1] = v;
        pix[i + 2] = v;
      }

      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/scan_bw_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outBytes = img.encodeJpg(gray, quality: 92);
      await File(outPath).writeAsBytes(outBytes, flush: true);

      if (!mounted) return outPath;
      setState(() => _enhancedImagePath = outPath);
      return outPath;
    } catch (_) {
      return sourcePath;
    } finally {
      if (mounted) setState(() => _enhancing = false);
    }
  }

  void _toggleBwEnhance() {
    if (_loading) return;
    setState(() => _bwEnhance = !_bwEnhance);
    _runOcr();
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
    _glassDebounce = Timer(const Duration(milliseconds: 240), () {
      final stable = _pendingGlassText;
      if (!mounted || stable == null) return;
      final t = stable.trim();
      if (t.isEmpty) return;

      final expanded = _glassSelectedText.value.isEmpty
          ? _smartExpandToSentence(_text, t)
          : t;
      if (_glassSelectedText.value != expanded) {
        _glassSelectedText.value = expanded;
      }
    });
  }

  String _smartExpandToSentence(String full, String needle) {
    final t = needle.trim();
    if (t.isEmpty) return t;
    if (t.length > 80) return t;
    if (full.trim().isEmpty) return t;

    int pos = full.indexOf(t);
    if (pos < 0) {
      final lowerFull = full.toLowerCase();
      final lowerNeedle = t.toLowerCase();
      pos = lowerFull.indexOf(lowerNeedle);
      if (pos < 0) return t;
    }

    int start = pos;
    for (var i = pos - 1; i >= 0; i -= 1) {
      final ch = full.codeUnitAt(i);
      if (_isSentenceBoundary(ch)) {
        start = i + 1;
        break;
      }
      if (i == 0) start = 0;
    }

    int end = pos + t.length;
    for (var i = end; i < full.length; i += 1) {
      final ch = full.codeUnitAt(i);
      if (_isSentenceBoundary(ch)) {
        end = i + 1;
        break;
      }
      if (i == full.length - 1) end = full.length;
    }

    final s = full.substring(start, end).trim();
    if (s.isEmpty) return t;
    return s;
  }

  bool _isSentenceBoundary(int codeUnit) {
    switch (codeUnit) {
      case 0x0A: // \n
      case 0x0D: // \r
      case 0x2E: // .
      case 0x3F: // ?
      case 0x21: // !
      case 0x3002: // 。
      case 0xFF1F: // ？
      case 0xFF01: // ！
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = material.Colors.white;
    final title = _loading ? '识别中' : '拍照扫描';

    return material.Scaffold(
      backgroundColor: bg,
      body: material.Material(
        color: bg,
        child: CupertinoPageScaffold(
          backgroundColor: bg,
          navigationBar: CupertinoNavigationBar(
            middle: Text(title),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('返回'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _loading ? null : _toggleBwEnhance,
                  child: Icon(
                    _bwEnhance
                        ? CupertinoIcons.circle_filled
                        : CupertinoIcons.circle_lefthalf_fill,
                    color: _bwEnhance
                        ? const Color(0xFF1C1C1E)
                        : const Color(0xFF6E6E73),
                    size: 22,
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _loading ? null : _runOcr,
                  child: const Icon(CupertinoIcons.refresh),
                ),
              ],
            ),
          ),
          child: Stack(
            children: [
              SafeArea(
                child: _loading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CupertinoActivityIndicator(),
                            SizedBox(height: 10),
                            Text(
                              '正在识别文字...',
                              style: TextStyle(
                                color: Color(0xFF6E6E73),
                                decoration: TextDecoration.none,
                                fontFamily: '.SF UI Text',
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : (_error != null)
                        ? Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
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
                          )
                        : material.SelectionArea(
                            selectionControls: cupertinoTextSelectionControls,
                            onSelectionChanged: _onSelectionChanged,
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (e) =>
                                  _lastPointerDownGlobal = e.position,
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  22,
                                  16,
                                  22,
                                  28,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x14000000),
                                            blurRadius: 30,
                                            offset: Offset(0, 18),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(18),
                                        child: Stack(
                                          children: [
                                            material.Image.file(
                                              File(_previewImagePath),
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) =>
                                                      const SizedBox(
                                                height: 180,
                                                child: Center(
                                                  child: Icon(
                                                    CupertinoIcons.photo,
                                                    color: Color(0xFF8E8E93),
                                                    size: 44,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (_enhancing)
                                              Positioned.fill(
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: const Color(0x99000000),
                                                    borderRadius:
                                                        BorderRadius.circular(18),
                                                  ),
                                                  child: const Center(
                                                    child: CupertinoActivityIndicator(
                                                      color: CupertinoColors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      _text,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        height: 1.6,
                                        color: Color(0xFF1C1C1E),
                                        decoration: TextDecoration.none,
                                        fontFamily: '.SF UI Text',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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

class _OcrCandidate {
  const _OcrCandidate({
    required this.text,
    required this.score,
    required this.script,
  });

  final String text;
  final int score;
  final TextRecognitionScript script;
}

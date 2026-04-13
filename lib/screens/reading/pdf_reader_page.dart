import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/book.dart';
import '../../services/ai_translation_service.dart';
import '../../widgets/apple_glass_sheet.dart';

const String _deepSeekProxyUrl =
    String.fromEnvironment('DEEPSEEK_PROXY_URL', defaultValue: '');
const String _appSecret = String.fromEnvironment('APP_SECRET', defaultValue: '');

class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key, required this.book});

  final Book book;

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  final PdfViewerController _pdfController = PdfViewerController();

  late final AiTranslationService _ai = AiTranslationService(
    proxyUrl: _deepSeekProxyUrl,
    appSecret: _appSecret,
  );

  final ValueNotifier<String> _glassSelectedText = ValueNotifier<String>('');
  bool _glassVisible = false;
  AppleGlassDock _glassDock = AppleGlassDock.bottom;

  Timer? _selectionDebounce;
  String? _pendingSelectedText;
  Rect? _pendingSelectedRegion;

  @override
  void dispose() {
    _selectionDebounce?.cancel();
    _glassSelectedText.dispose();
    super.dispose();
  }

  void _onTextSelectionChanged(PdfTextSelectionChangedDetails details) {
    final raw = details.selectedText;
    if (raw == null) {
      _selectionDebounce?.cancel();
      _pendingSelectedText = null;
      _pendingSelectedRegion = null;
      return;
    }

    final text = raw.trim();
    if (text.isEmpty) {
      _selectionDebounce?.cancel();
      _pendingSelectedText = null;
      _pendingSelectedRegion = null;
      return;
    }

    _pendingSelectedText = text;
    _pendingSelectedRegion = details.globalSelectedRegion;
    _selectionDebounce?.cancel();
    _selectionDebounce = Timer(const Duration(milliseconds: 260), () {
      final stable = _pendingSelectedText;
      if (stable == null) return;
      final t = stable.trim();
      if (t.isEmpty) return;
      if (!mounted) return;
      final mq = MediaQuery.of(context);
      final h = mq.size.height;
      final topInset = mq.padding.top;
      final bottomInset = mq.padding.bottom;
      final safeHeight = h - topInset - bottomInset;
      // Match AppleGlassPanel's default height heuristics.
      final defaultPanelHeight =
          (safeHeight * 0.38).clamp(160.0, safeHeight * 0.72).toDouble();
      final bottomPanelTotalHeight = defaultPanelHeight + bottomInset;
      final topPanelTotalHeight = defaultPanelHeight + topInset;

      final region = _pendingSelectedRegion;
      final y = region?.center.dy;
      // Prefer the dock that doesn't cover the selection handles.
      final nextDock = (region != null)
          ? ((region.bottom > h - bottomPanelTotalHeight)
              ? AppleGlassDock.top
              : (region.top < topPanelTotalHeight)
                  ? AppleGlassDock.bottom
                  : (y != null && y > h * 0.5)
                      ? AppleGlassDock.top
                      : AppleGlassDock.bottom)
          : ((y != null && y > h * 0.5) ? AppleGlassDock.top : AppleGlassDock.bottom);

      if (!_glassVisible || nextDock != _glassDock) {
        setState(() {
          _glassVisible = true;
          _glassDock = nextDock;
        });
      }
      if (_glassSelectedText.value != t) {
        _glassSelectedText.value = t;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF6F4EE);
    final widgetTitle =
        widget.book.title.trim().isEmpty ? 'PDF' : widget.book.title.trim();

    final viewer = switch (widget.book.source) {
      BookSource.asset => SfPdfViewer.asset(
          widget.book.locator,
          controller: _pdfController,
          enableTextSelection: true,
          onTextSelectionChanged: _onTextSelectionChanged,
          // Keep the native selection handles fully functional (draggable),
          // but hide Syncfusion's default context menu (Copy/Highlight/Underline)
          // since we provide our own "Apple Glass" panel.
          canShowTextSelectionMenu: false,
        ),
      BookSource.localFile => SfPdfViewer.file(
          File(widget.book.locator),
          controller: _pdfController,
          enableTextSelection: true,
          onTextSelectionChanged: _onTextSelectionChanged,
          canShowTextSelectionMenu: false,
        ),
      BookSource.mock => SfPdfViewer.asset(
          widget.book.locator,
          controller: _pdfController,
          enableTextSelection: true,
          onTextSelectionChanged: _onTextSelectionChanged,
          canShowTextSelectionMenu: false,
        ),
    };

    return material.Scaffold(
      backgroundColor: bg,
      body: material.Material(
        color: bg,
        child: CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            backgroundColor: bg.withValues(alpha: 0.94),
            border: null,
            middle: Text(widgetTitle),
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
          child: DecoratedBox(
            decoration: const BoxDecoration(color: bg),
            child: Stack(
              children: [
                // Keep the PDF content out of the Home Indicator area.
                SafeArea(top: false, child: viewer),
                if (_glassVisible)
                  Positioned.fill(
                    child: AppleGlassPanel(
                      selectedTextListenable: _glassSelectedText,
                      dock: _glassDock,
                      initialLevel: widget.book.defaultLevel,
                      ai: _ai,
                      onDismiss: () => setState(() => _glassVisible = false),
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

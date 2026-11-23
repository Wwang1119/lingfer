import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'pdf_offline_probe_view.dart';
import 'pdf_probe_models.dart';
import 'pdf_probe_session.dart';
import 'pdf_restore.dart';
import 'syncfusion_selection_snapshot.dart';

const String syntheticProbeAsset = 'assets/probe/synthetic_probe.pdf';

class PdfObservationApp extends StatelessWidget {
  const PdfObservationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PdfObservationHost(),
    );
  }
}

class PdfObservationHost extends StatefulWidget {
  const PdfObservationHost({super.key});

  @override
  State<PdfObservationHost> createState() => _PdfObservationHostState();
}

class _PdfObservationHostState extends State<PdfObservationHost> {
  final PdfViewerController _controller = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _viewerKey = GlobalKey();
  final PdfProbeSession _session = PdfProbeSession();
  final Map<int, Size> _pageSizes = <int, Size>{};
  String? _fingerprint;
  String? _loadError;
  String? _readback;
  Size _screen = const Size(400, 800);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screen = MediaQuery.sizeOf(context);
  }

  @override
  void initState() {
    super.initState();
    _loadFingerprint();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Future<void> _loadFingerprint() async {
    try {
      final data = await rootBundle.load(syntheticProbeAsset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (!mounted) return;
      setState(() => _fingerprint = fingerprintBytes(bytes));
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = '测试 PDF 没有载入');
    }
  }

  PdfViewport _viewport() {
    final zoom = _controller.zoomLevel;
    final offset = _controller.scrollOffset;
    return PdfViewport(
      zoom: zoom,
      scrollX: offset.dx,
      scrollY: offset.dy,
      width: _screen.width,
      height: _screen.height,
      orientation: _screen.width > _screen.height
          ? PdfOrientation.landscape
          : PdfOrientation.portrait,
    );
  }

  void _onSelection(PdfTextSelectionChangedDetails details) {
    if (!mounted) return;
    final snapshot = snapshotPublicSelection(
      selectedText: details.selectedText,
      globalSelectedRegion: details.globalSelectedRegion,
      readControllerPageNumber: () => _controller.pageNumber,
      readLinesNow: () =>
          _viewerKey.currentState?.getSelectedTextLines() ??
          const <PdfTextLine>[],
      pageSizesByReportedPage: _pageSizes,
      fileHash: _fingerprint,
    );
    _session.onCallback(snapshot, viewportNow: _viewport());
    _session.applyPending();
  }

  void _onLoaded(PdfDocumentLoadedDetails details) {
    final document = details.document;
    final next = <int, Size>{};
    for (var index = 0; index < document.pages.count; index += 1) {
      next[index + 1] = document.pages[index].size;
    }
    setState(() {
      _pageSizes
        ..clear()
        ..addAll(next);
    });
  }

  void _leave() {
    final viewport = _viewport();
    if (!viewport.isLegal) {
      setState(() => _readback = '当前视野不是有限正值，没有生成恢复计划');
      return;
    }
    _session.leave(viewport);
    setState(() => _readback = null);
  }

  void _reopenTrajectory() {
    final record = _session.leaveRecord;
    if (record == null) return;
    final plan = planRestore(record);
    if (plan == null) {
      setState(() => _readback = '没有有效恢复计划');
      return;
    }
    _controller.zoomLevel = plan.initialZoomLevel;
    _controller.jumpTo(
      xOffset: plan.initialScrollX,
      yOffset: plan.initialScrollY,
    );
    final read = _viewport();
    final observation = ReadbackObservation(
      zoom: read.zoom,
      scrollX: read.scrollX,
      scrollY: read.scrollY,
      width: read.width,
      height: read.height,
      orientation: read.orientation,
      sentenceVisible: null,
      highlightOnGlyphs: null,
      cardOccludesSentence: null,
      stableFrameCount: 0,
      source: ObservationSource.syntheticFixture,
      targetFileHash: record.anchor?.fileHash,
      targetPageNumber: record.anchor?.pageNumber,
      leaveSelectionGeneration: record.selectionGeneration,
    );
    _session.reopen(record, observation: observation);
    final verdict = _session.reopenVerdict;
    setState(() {
      _readback =
          '重开读回 zoom ${read.zoom} x ${read.scrollX} y ${read.scrollY}'
          '${verdict == null ? '' : '，${restoreVerdictLabel(verdict)}'}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4EE),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardMax = math.min(188.0, constraints.maxHeight * 0.34);
            return Column(
              children: [
                Expanded(child: _viewer()),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: cardMax),
                  child: _card(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _viewer() {
    if (_loadError != null) {
      return Center(child: Text(_loadError!));
    }
    return SfPdfViewer.asset(
      syntheticProbeAsset,
      key: _viewerKey,
      controller: _controller,
      enableTextSelection: true,
      canShowTextSelectionMenu: false,
      onTextSelectionChanged: _onSelection,
      onDocumentLoaded: _onLoaded,
    );
  }

  Widget _card() {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        final decision = _session.decision;
        final leave = _session.leaveRecord;
        final verdict = _session.reopenVerdict;
        return Material(
          color: const Color(0xFFFFFCF8),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            children:
                const [
                  Text('离线定位状态，不是生成解释'),
                  SizedBox(height: 4),
                  Text('合成测试 PDF。公开选区接口不能证明所在页，这里只显示拒绝原因。'),
                ].followedBy([
                  const SizedBox(height: 6),
                  Text(
                    _fingerprint == null ? '正在计算本地指纹' : '本地指纹 $_fingerprint',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    decision is LocateRejected
                        ? locateFailureLabel(decision.failure)
                        : '尚未形成可提交锚点',
                    key: const Key('pdf-observation-status'),
                  ),
                  Text('控制器当前页观察值 ${_controller.pageNumber}，不是页证据'),
                  if (leave != null)
                    Text(
                      '离开时 zoom ${leave.viewport.zoom} '
                      'x ${leave.viewport.scrollX} y ${leave.viewport.scrollY}',
                    ),
                  if (verdict != null) Text(restoreVerdictLabel(verdict)),
                  if (_readback != null) Text(_readback!),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        key: const Key('pdf-observation-leave'),
                        onPressed: _leave,
                        child: const Text('记录离开'),
                      ),
                      TextButton(
                        key: const Key('pdf-observation-reopen'),
                        onPressed: _reopenTrajectory,
                        child: const Text('重开轨迹'),
                      ),
                      TextButton(
                        onPressed: _session.dismissAnchor,
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ]).toList(),
          ),
        );
      },
    );
  }
}

String fingerprintBytes(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

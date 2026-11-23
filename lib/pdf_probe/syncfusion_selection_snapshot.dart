import 'dart:ui';

import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'pdf_probe_models.dart';

/// Copies a Syncfusion callback into a probe snapshot at the moment of the call.
///
/// The closures are invoked synchronously, before this function returns. The
/// evidence kind is always [PageEvidenceKind.publicCurrentPageGetter]. The
/// production PDF page does not call this function.
PdfSelectionSnapshot snapshotPublicSelection({
  required String? selectedText,
  required Rect? globalSelectedRegion,
  required int Function() readControllerPageNumber,
  required List<PdfTextLine> Function() readLinesNow,
  required Map<int, Size> pageSizesByReportedPage,
  String? fileHash,
}) {
  final controllerPageNumber = readControllerPageNumber();
  final lines = List<PdfTextLine>.of(readLinesNow());
  return PdfSelectionSnapshot(
    selectedText: selectedText,
    globalSelectedRegion: globalSelectedRegion,
    controllerPageNumber: controllerPageNumber,
    fileHash: fileHash,
    evidence: PageEvidenceKind.publicCurrentPageGetter,
    lines: List<PdfLineSnapshot>.unmodifiable([
      for (final line in lines)
        PdfLineSnapshot(
          pageNumber: line.pageNumber,
          text: line.text,
          bounds: line.bounds,
          pageSize: pageSizesByReportedPage[line.pageNumber],
        ),
    ]),
  );
}

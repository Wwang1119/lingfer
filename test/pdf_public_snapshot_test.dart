import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingfer/pdf_probe/pdf_probe_models.dart';
import 'package:lingfer/pdf_probe/syncfusion_selection_snapshot.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

void main() {
  test(
    'the public snapshot copies lines immediately and cannot mint fixture evidence',
    () {
      var reads = 0;
      final snapshot = snapshotPublicSelection(
        selectedText: 'Hello',
        globalSelectedRegion: const Rect.fromLTWH(0, 0, 8, 8),
        readControllerPageNumber: () => 1,
        readLinesNow: () {
          reads += 1;
          return [PdfTextLine(const Rect.fromLTWH(1, 2, 3, 4), 'Hello', 2)];
        },
        pageSizesByReportedPage: const {2: Size(10, 20)},
        fileHash: 'h',
      );
      expect(reads, 1);
      expect(snapshot.evidence, PageEvidenceKind.publicCurrentPageGetter);
      expect(snapshot.controllerPageNumber, 1);
      expect(snapshot.lines.single.pageNumber, 2);
      expect(snapshot.lines.single.text, 'Hello');
      expect(snapshot.lines.single.pageSize, const Size(10, 20));
    },
  );
}

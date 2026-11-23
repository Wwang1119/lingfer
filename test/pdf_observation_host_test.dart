import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingfer/pdf_probe/pdf_observation_host.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

void main() {
  testWidgets('observation host mounts the synthetic PDF and does not claim restore', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const PdfObservationApp());
    await tester.pump();

    expect(find.text('离线定位状态，不是生成解释'), findsOneWidget);
    expect(find.text('原句已恢复'), findsNothing);
    expect(find.byType(SfPdfViewer), findsOneWidget);
    expect(find.byKey(const Key('pdf-observation-status')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}

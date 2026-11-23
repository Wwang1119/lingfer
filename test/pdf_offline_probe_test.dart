import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingfer/pdf_probe/pdf_locate.dart';
import 'package:lingfer/pdf_probe/pdf_offline_probe_view.dart';
import 'package:lingfer/pdf_probe/pdf_probe_models.dart';
import 'package:lingfer/pdf_probe/pdf_probe_session.dart';
import 'package:lingfer/pdf_probe/pdf_restore.dart';
import 'package:lingfer/pdf_probe/pdf_text_norm.dart';

const _page = Size(200, 400);

PdfLineSnapshot _line(
  String text,
  Rect bounds, {
  int page = 2,
  Size? pageSize = _page,
}) {
  return PdfLineSnapshot(
    pageNumber: page,
    text: text,
    bounds: bounds,
    pageSize: pageSize,
  );
}

PdfSelectionSnapshot _snapshot({
  required String? text,
  required List<PdfLineSnapshot> lines,
  PageEvidenceKind evidence = PageEvidenceKind.externalFixture,
  int controllerPageNumber = 1,
  String? fileHash = 'hash-h',
}) {
  return PdfSelectionSnapshot(
    selectedText: text,
    globalSelectedRegion: const Rect.fromLTWH(0, 0, 10, 10),
    controllerPageNumber: controllerPageNumber,
    lines: lines,
    evidence: evidence,
    fileHash: fileHash,
  );
}

PdfSelectionSnapshot _singleColumn({
  required String text,
  PageEvidenceKind evidence = PageEvidenceKind.externalFixture,
  int linePage = 2,
  int controllerPage = 1,
}) {
  final parts = text.split('\n');
  return _snapshot(
    text: text,
    evidence: evidence,
    controllerPageNumber: controllerPage,
    lines: [
      for (var i = 0; i < parts.length; i += 1)
        _line(
          parts[i],
          Rect.fromLTWH(10, 20.0 + (i * 24), 120, 12),
          page: linePage,
        ),
    ],
  );
}

void main() {
  group('text comparison upper bound', () {
    test('unifies newlines and trims only whole-string ASCII space and LF', () {
      expect(
        selectionTextsEqual('  Hello\r\nworld  \n', const ['Hello', 'world']),
        isTrue,
      );
      expect(selectionTextsEqual('Hello', const ['Hello']), isTrue);
    });

    test('does not treat other differences as equal', () {
      final ledger = <String>[];
      void reject(String id, String callback, List<String> lines) {
        expect(selectionTextsEqual(callback, lines), isFalse, reason: id);
        ledger.add(id);
      }

      reject('unicode-minus', '−5', const ['5']);
      reject('unit-space', '10 m', const ['10 mm']);
      reject('hyphen-word', 'co-op', const ['coop']);
      reject('ligature', 'ﬁ', const ['fi']);
      reject('nfc', 'e\u0301', const ['é']);
      reject('internal-space', '10  m', const ['10 m']);
      reject('leading-nbsp', '\u00A0Hello', const ['Hello']);
      reject('trailing-nbsp', 'Hello\u00A0', const ['Hello']);
      reject('leading-tab', '\tHello', const ['Hello']);
      expect(ledger, [
        'unicode-minus',
        'unit-space',
        'hyphen-word',
        'ligature',
        'nfc',
        'internal-space',
        'leading-nbsp',
        'trailing-nbsp',
        'leading-tab',
      ]);
    });
  });

  group('locate', () {
    test('current page plus identical text is not an independent page', () {
      final snapshot = _singleColumn(
        text: 'Same sentence',
        evidence: PageEvidenceKind.publicCurrentPageGetter,
        linePage: 1,
        controllerPage: 1,
      );
      expect(snapshot.lines.single.pageNumber, snapshot.controllerPageNumber);
      expect(
        selectionTextsEqual(
          snapshot.selectedText!,
          snapshot.lines.map((line) => line.text),
        ),
        isTrue,
      );
      final decision = locateSelection(snapshot);
      expect(decision, isA<LocateRejected>());
      expect(
        (decision as LocateRejected).failure,
        LocateFailure.pageIdentityUnproven,
      );
    });

    test(
      'empty lines, bad bounds, cross page, and column-like boxes fail closed',
      () {
        expect(
          (locateSelection(_snapshot(text: 'A', lines: const []))
                  as LocateRejected)
              .failure,
          LocateFailure.noLines,
        );
        expect(
          (locateSelection(
                    _snapshot(
                      text: 'A',
                      lines: [_line('', const Rect.fromLTWH(10, 20, 40, 12))],
                    ),
                  )
                  as LocateRejected)
              .failure,
          LocateFailure.emptyLineText,
        );
        expect(
          (locateSelection(
                    _snapshot(
                      text: 'A',
                      lines: [_line('A', const Rect.fromLTWH(10, 20, 0, 12))],
                    ),
                  )
                  as LocateRejected)
              .failure,
          LocateFailure.badBounds,
        );
        expect(
          (locateSelection(
                    _snapshot(
                      text: 'A\nB',
                      lines: [
                        _line(
                          'A',
                          const Rect.fromLTWH(10, 20, 40, 12),
                          page: 1,
                        ),
                        _line(
                          'B',
                          const Rect.fromLTWH(10, 40, 40, 12),
                          page: 2,
                        ),
                      ],
                    ),
                  )
                  as LocateRejected)
              .failure,
          LocateFailure.crossPage,
        );
        expect(
          (locateSelection(
                    _snapshot(
                      text: 'Left\nRight',
                      lines: [
                        _line('Left', const Rect.fromLTWH(10, 20, 40, 12)),
                        _line('Right', const Rect.fromLTWH(120, 20, 40, 12)),
                      ],
                    ),
                  )
                  as LocateRejected)
              .failure,
          LocateFailure.orderAmbiguous,
        );
      },
    );

    test('a fixture page can commit when geometry and text agree', () {
      final decision = locateSelection(_singleColumn(text: 'Second sentence'));
      expect(decision, isA<LocateCommitted>());
      final anchor = (decision as LocateCommitted).anchor;
      expect(anchor.pageNumber, 2);
      expect(anchor.fileHash, 'hash-h');
      expect(anchor.lines.single.text, 'Second sentence');
    });
  });

  group('session stand-in, not a Syncfusion controller', () {
    late PdfProbeSession session;
    var viewport = const PdfViewport(
      zoom: 1,
      scrollX: 0,
      scrollY: 0,
      width: 400,
      height: 800,
      orientation: PdfOrientation.portrait,
    );

    setUp(() {
      session = PdfProbeSession();
      viewport = const PdfViewport(
        zoom: 1,
        scrollX: 0,
        scrollY: 0,
        width: 400,
        height: 800,
        orientation: PdfOrientation.portrait,
      );
    });

    test('the callback copy is fixed before a later list edit', () {
      final lines = [_line('Hello', const Rect.fromLTWH(10, 20, 80, 12))];
      session.onCallback(
        _snapshot(text: 'Hello', lines: lines),
        viewportNow: viewport,
      );
      lines[0] = _line('Changed', const Rect.fromLTWH(10, 20, 80, 12));
      session.applyPending();
      final anchor = session.anchor;
      expect(anchor, isNotNull);
      expect(anchor!.lines.single.text, 'Hello');
      expect(PdfProbeSession.outboundRequestCount, 0);
    });

    test('an untagged clear does not drop a pending or committed anchor', () {
      session.onCallback(_singleColumn(text: 'Keep me'), viewportNow: viewport);
      session.onCallback(
        _snapshot(text: null, lines: const []),
        viewportNow: viewport,
      );
      session.applyPending();
      expect(session.nativeCleared, isTrue);
      expect(session.anchor?.lines.single.text, 'Keep me');
      expect(session.annotationApplications, 1);

      session.onCallback(
        _snapshot(text: '', lines: const []),
        viewportNow: viewport,
      );
      expect(session.anchor?.lines.single.text, 'Keep me');
      expect(session.annotation, isNotNull);
    });

    test('a new unproven callback removes the previous anchor', () {
      session.onCallback(_singleColumn(text: 'Keep me'), viewportNow: viewport);
      session.applyPending();
      session.onCallback(
        _singleColumn(
          text: 'Same sentence',
          evidence: PageEvidenceKind.publicCurrentPageGetter,
          linePage: 1,
          controllerPage: 1,
        ),
        viewportNow: viewport,
      );
      session.applyPending();
      expect(session.anchor, isNull);
      expect(session.annotation, isNull);
      final decision = session.decision;
      expect(decision, isA<LocateRejected>());
      expect(
        (decision as LocateRejected).failure,
        LocateFailure.pageIdentityUnproven,
      );
    });

    test(
      'leave stores the viewport at leave, and restore does not use it as a pass',
      () {
        session.onCallback(
          _singleColumn(text: 'Second sentence'),
          viewportNow: viewport,
        );
        session.applyPending();
        viewport = const PdfViewport(
          zoom: 2.5,
          scrollX: 40,
          scrollY: 80,
          width: 400,
          height: 800,
          orientation: PdfOrientation.portrait,
        );
        final record = session.leave(viewport);
        expect(record.viewport.zoom, 2.5);
        expect(record.viewport.scrollX, 40);
        expect(session.viewportAtSelection?.zoom, 1);

        final plan = planRestore(record);
        expect(plan.initialZoomLevel, 2.5);
        expect(plan.initialScrollX, 40);
        expect(plan.initialScrollY, 80);
        expect(plan.initialPageNumber, 1);
        expect(plan.usePageStorageKey, isFalse);

        final unknown = ReadbackObservation.unknownMatchingGeometry(record);
        expect(classifyRestore(record, unknown), RestoreVerdict.unverified);
        expect(
          classifyRestore(
            record,
            ReadbackObservation(
              zoom: record.viewport.zoom,
              scrollX: record.viewport.scrollX,
              scrollY: record.viewport.scrollY,
              width: record.viewport.width,
              height: record.viewport.height,
              orientation: record.viewport.orientation,
              sentenceVisible: null,
              highlightOnGlyphs: null,
              cardOccludesSentence: null,
              stableFrameCount: 3,
            ),
          ),
          RestoreVerdict.unverified,
        );
      },
    );

    test(
      'proposed numeric slack and geometry changes are not selectionRestored',
      () {
        final record = PdfLeaveRecord(
          viewport: viewport,
          anchor: const PdfAnchor(fileHash: 'hash-h', pageNumber: 2, lines: []),
          annotation: null,
          failure: null,
        );
        final closeButNotExact = ReadbackObservation(
          zoom: viewport.zoom + 0.005,
          scrollX: viewport.scrollX,
          scrollY: viewport.scrollY,
          width: viewport.width,
          height: viewport.height,
          orientation: viewport.orientation,
          sentenceVisible: true,
          highlightOnGlyphs: true,
          cardOccludesSentence: false,
          stableFrameCount: 3,
        );
        expect(
          withinProposedUncalibratedTolerance(
            leave: viewport,
            observation: closeButNotExact,
          ),
          isTrue,
        );
        expect(
          classifyRestore(record, closeButNotExact),
          RestoreVerdict.failed,
        );

        final rotated = ReadbackObservation(
          zoom: viewport.zoom,
          scrollX: viewport.scrollX,
          scrollY: viewport.scrollY,
          width: 800,
          height: 400,
          orientation: PdfOrientation.landscape,
          sentenceVisible: true,
          highlightOnGlyphs: true,
          cardOccludesSentence: false,
          stableFrameCount: 3,
        );
        expect(classifyRestore(record, rotated), RestoreVerdict.unverified);
      },
    );

    test(
      'injected gates can reach selectionRestored only inside this test',
      () {
        session.onCallback(
          _singleColumn(text: 'Second sentence'),
          viewportNow: viewport,
        );
        session.applyPending();
        final record = session.leave(viewport);
        final injected = ReadbackObservation(
          zoom: viewport.zoom,
          scrollX: viewport.scrollX,
          scrollY: viewport.scrollY,
          width: viewport.width,
          height: viewport.height,
          orientation: viewport.orientation,
          sentenceVisible: true,
          highlightOnGlyphs: true,
          cardOccludesSentence: false,
          stableFrameCount: 1,
        );
        expect(
          classifyRestore(record, injected),
          RestoreVerdict.selectionRestored,
        );
      },
    );
  });

  testWidgets(
    'probe card stays outside the page slot and does not show an unproven sentence',
    (tester) async {
      final session = PdfProbeSession();
      var viewport = PdfViewport.identity;
      await tester.pumpWidget(
        MaterialApp(
          home: PdfOfflineProbeView(
            session: session,
            readViewport: () => viewport,
          ),
        ),
      );

      session.onCallback(
        _singleColumn(
          text: 'ALPHA-SENTENCE',
          evidence: PageEvidenceKind.publicCurrentPageGetter,
          linePage: 1,
          controllerPage: 1,
        ),
        viewportNow: viewport,
      );
      session.applyPending();
      await tester.pump();

      expect(find.text('未能确认选区所在页'), findsOneWidget);
      expect(find.text('ALPHA-SENTENCE'), findsNothing);
      expect(find.text('离线占位，未请求模型'), findsOneWidget);
      expect(find.text('原句已恢复'), findsNothing);

      final page = tester.getRect(find.byKey(const Key('pdf-probe-page-slot')));
      final card = tester.getRect(find.byKey(const Key('pdf-probe-card')));
      expect(page.overlaps(card), isFalse);

      viewport = const PdfViewport(
        zoom: 2.5,
        scrollX: 40,
        scrollY: 80,
        width: 400,
        height: 800,
        orientation: PdfOrientation.portrait,
      );
      await tester.tap(find.byKey(const Key('pdf-probe-leave')));
      await tester.pump();
      expect(find.text('离开时 zoom 2.5 x 40.0 y 80.0'), findsOneWidget);

      final reopened = PdfProbeSession();
      reopened.reopen(session.leaveRecord!);
      await tester.pumpWidget(
        MaterialApp(
          home: PdfOfflineProbeView(
            session: reopened,
            readViewport: () => viewport,
          ),
        ),
      );
      expect(find.text('回位未验证'), findsOneWidget);
      expect(find.text('原句已恢复'), findsNothing);
      expect(reopened.annotationApplications, 0);
    },
  );
}

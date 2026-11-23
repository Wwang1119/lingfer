import 'dart:io';

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

PdfSelectionSnapshot _column(
  String text, {
  PageEvidenceKind evidence = PageEvidenceKind.externalFixture,
  int linePage = 2,
  int controllerPage = 1,
  double firstTop = 20,
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
          Rect.fromLTWH(10, firstTop + (i * 24), 120, 12),
          page: linePage,
        ),
    ],
  );
}

class _RecordingHttpOverrides extends HttpOverrides {
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients += 1;
    return super.createHttpClient(context);
  }
}

void main() {
  group('text comparison upper bound', () {
    test('unifies newlines and trims only whole-string ASCII space and LF', () {
      expect(
        selectionTextsEqual('  Hello\r\nworld  \n', const ['Hello', 'world']),
        isTrue,
      );
      expect(
        selectionTextsEqual('Hello\nworld', const [' Hello', 'world ']),
        isTrue,
      );
      expect(
        selectionTextsEqual('Hello\nworld', const ['Hello ', 'world']),
        isFalse,
      );
    });

    test('does not treat TAB, NBSP, or other differences as equal', () {
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
      reject('ideographic-space', '\u3000Hello', const ['Hello']);
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
        'ideographic-space',
      ]);
    });
  });

  group('locate', () {
    test('current page plus identical text is not an independent page', () {
      final snapshot = _column(
        'Same sentence',
        evidence: PageEvidenceKind.publicCurrentPageGetter,
        linePage: 1,
        controllerPage: 1,
      );
      final decision = locateSelection(snapshot);
      expect(
        (decision as LocateRejected).failure,
        LocateFailure.pageIdentityUnproven,
      );
    });

    test('blank text cannot commit an anchor', () {
      final decision = locateSelection(
        _snapshot(
          text: '   \n',
          lines: [_line('   ', const Rect.fromLTWH(10, 20, 40, 12))],
        ),
      );
      expect((decision as LocateRejected).failure, LocateFailure.emptyLineText);
    });

    test(
      'reversed unrotated lines, infinite page size, and mismatched sizes fail',
      () {
        expect(
          (locateSelection(
                    _snapshot(
                      text: 'Lower\nUpper',
                      lines: [
                        _line('Lower', const Rect.fromLTWH(10, 100, 80, 12)),
                        _line('Upper', const Rect.fromLTWH(10, 20, 80, 12)),
                      ],
                    ),
                  )
                  as LocateRejected)
              .failure,
          LocateFailure.orderAmbiguous,
        );
        expect(
          (locateSelection(
                    _snapshot(
                      text: 'A',
                      lines: [
                        _line(
                          'A',
                          const Rect.fromLTWH(10, 20, 40, 12),
                          pageSize: const Size(double.infinity, 400),
                        ),
                      ],
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
                          const Rect.fromLTWH(10, 20, 80, 12),
                          pageSize: const Size(200, 400),
                        ),
                        _line(
                          'B',
                          const Rect.fromLTWH(10, 44, 80, 12),
                          pageSize: const Size(180, 400),
                        ),
                      ],
                    ),
                  )
                  as LocateRejected)
              .failure,
          LocateFailure.pageSizeInconsistent,
        );
      },
    );

    test('touching lines in downward order can commit from a fixture', () {
      final decision = locateSelection(
        _snapshot(
          text: 'One\nTwo',
          lines: [
            _line('One', const Rect.fromLTWH(10, 20, 80, 12)),
            _line('Two', const Rect.fromLTWH(10, 32, 80, 12)),
          ],
        ),
      );
      expect(decision, isA<LocateCommitted>());
    });
  });

  group('session', () {
    late PdfProbeSession session;
    var viewport = PdfViewport.identity;

    setUp(() {
      session = PdfProbeSession();
      viewport = PdfViewport.identity;
    });

    test(
      'a copied snapshot is stable, and a blank clear does not drop it after commit',
      () {
        session.onCallback(_column('Hello'), viewportNow: viewport);
        session.applyPending();
        expect(session.anchor?.lines.single.text, 'Hello');
        expect(session.annotationApplications, 1);

        session.onCallback(
          _snapshot(text: '  \r\n ', lines: const []),
          viewportNow: viewport,
        );
        session.applyPending();
        expect(session.anchor?.lines.single.text, 'Hello');
        expect(session.annotationApplications, 1);
      },
    );

    test('an undecided snapshot is cancelled by an untagged clear', () {
      session.onCallback(_column('Pending'), viewportNow: viewport);
      session.onCallback(
        _snapshot(text: null, lines: const []),
        viewportNow: viewport,
      );
      session.applyPending();
      expect(session.anchor, isNull);
      expect(session.nativeCleared, isTrue);
    });

    test(
      'TAB is not a clear and a failed new attempt removes the old anchor',
      () {
        session.onCallback(_column('Hello'), viewportNow: viewport);
        session.applyPending();
        session.onCallback(
          _snapshot(text: '\t', lines: const []),
          viewportNow: viewport,
        );
        session.applyPending();
        expect(session.anchor, isNull);
        expect(
          (session.decision as LocateRejected).failure,
          LocateFailure.noLines,
        );
      },
    );

    test(
      'pending leave does not keep the old anchor, and the old record cannot reopen',
      () {
        session.onCallback(_column('Anchor A'), viewportNow: viewport);
        session.applyPending();
        final first = session.leave(viewport);
        expect(first.anchor?.lines.single.text, 'Anchor A');
        expect(planRestore(first)?.initialPageNumber, 1);
        expect(planRestore(first)?.initialScrollX, 0);

        session.onCallback(
          _column(
            'Same sentence',
            evidence: PageEvidenceKind.publicCurrentPageGetter,
            linePage: 1,
            controllerPage: 1,
          ),
          viewportNow: viewport,
        );
        final pendingLeave = session.leave(viewport);
        expect(pendingLeave.pendingUnsettled, isTrue);
        expect(pendingLeave.anchor, isNull);
        expect(planRestore(pendingLeave), isNull);

        session.applyPending();
        expect(session.reopenVerdict, isNull);
        expect(session.reopen(first), isFalse);
        expect(session.anchor, isNull);
      },
    );

    test('dismiss blocks a late reopen', () {
      session.onCallback(_column('Hello'), viewportNow: viewport);
      session.applyPending();
      final record = session.leave(viewport);
      session.dismissAnchor();
      expect(session.anchor, isNull);
      expect(session.reopen(record), isFalse);
      session.applyPending();
      expect(session.anchor, isNull);
    });

    test(
      'exact fixture numbers are not a real restore, and slack stays failed',
      () {
        session.onCallback(_column('Second sentence'), viewportNow: viewport);
        session.applyPending();
        final record = session.leave(viewport);
        final exact = ReadbackObservation(
          zoom: viewport.zoom,
          scrollX: 0,
          scrollY: 0,
          width: viewport.width,
          height: viewport.height,
          orientation: viewport.orientation,
          sentenceVisible: true,
          highlightOnGlyphs: true,
          cardOccludesSentence: false,
          stableFrameCount: 3,
          source: ObservationSource.deviceObserved,
          targetFileHash: 'hash-h',
          targetPageNumber: 2,
          leaveSelectionGeneration: record.selectionGeneration,
        );
        expect(
          classifyRestore(record, exact),
          RestoreVerdict.fixtureConditionsMet,
        );
        expect(
          classifyRestore(record, exact),
          isNot(RestoreVerdict.selectionRestored),
        );

        final slack = ReadbackObservation(
          zoom: viewport.zoom + 0.005,
          scrollX: viewport.scrollX + 0.5,
          scrollY: viewport.scrollY,
          width: viewport.width,
          height: viewport.height,
          orientation: viewport.orientation,
          sentenceVisible: true,
          highlightOnGlyphs: true,
          cardOccludesSentence: false,
          stableFrameCount: 3,
          source: ObservationSource.syntheticFixture,
          targetFileHash: 'hash-h',
          targetPageNumber: 2,
          leaveSelectionGeneration: record.selectionGeneration,
        );
        expect(
          withinProposedUncalibratedTolerance(
            leave: viewport,
            observation: slack,
          ),
          isTrue,
        );
        expect(classifyRestore(record, slack), RestoreVerdict.failed);

        final wider = ReadbackObservation(
          zoom: viewport.zoom,
          scrollX: viewport.scrollX,
          scrollY: viewport.scrollY,
          width: viewport.width + 20,
          height: viewport.height,
          orientation: viewport.orientation,
          sentenceVisible: true,
          highlightOnGlyphs: true,
          cardOccludesSentence: false,
          stableFrameCount: 1,
          source: ObservationSource.syntheticFixture,
          targetFileHash: 'hash-h',
          targetPageNumber: 2,
          leaveSelectionGeneration: record.selectionGeneration,
        );
        expect(classifyRestore(record, wider), RestoreVerdict.unverified);

        final occluded = ReadbackObservation(
          zoom: viewport.zoom,
          scrollX: viewport.scrollX,
          scrollY: viewport.scrollY,
          width: viewport.width,
          height: viewport.height,
          orientation: viewport.orientation,
          sentenceVisible: null,
          highlightOnGlyphs: null,
          cardOccludesSentence: true,
          stableFrameCount: 1,
          source: ObservationSource.syntheticFixture,
          targetFileHash: 'hash-h',
          targetPageNumber: 2,
          leaveSelectionGeneration: record.selectionGeneration,
        );
        expect(classifyRestore(record, occluded), RestoreVerdict.failed);

        final illegal = const PdfViewport(
          zoom: double.nan,
          scrollX: 0,
          scrollY: 0,
          width: 400,
          height: 800,
          orientation: PdfOrientation.portrait,
        );
        final badLeave = session.leave(illegal);
        expect(planRestore(badLeave), isNull);
        expect(badLeave.viewport.isLegal, isFalse);
      },
    );
  });

  testWidgets('the probe does not present fixture success or issue HTTP', (
    tester,
  ) async {
    final http = _RecordingHttpOverrides();
    await HttpOverrides.runZoned(() async {
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
        _column(
          'ALPHA-SENTENCE',
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
      expect(find.text('原句已恢复'), findsNothing);

      session.onCallback(_column('Visible line'), viewportNow: viewport);
      session.applyPending();
      viewport = const PdfViewport(
        zoom: 2.5,
        scrollX: 0,
        scrollY: 80,
        width: 400,
        height: 800,
        orientation: PdfOrientation.portrait,
      );
      await tester.tap(find.byKey(const Key('pdf-probe-leave')));
      await tester.pump();
      final reopened = PdfProbeSession()..reopen(session.leaveRecord!);
      await tester.pumpWidget(
        MaterialApp(
          home: PdfOfflineProbeView(
            session: reopened,
            readViewport: () => viewport,
          ),
        ),
      );
      expect(find.text('原句已恢复'), findsNothing);
      expect(find.text('回位未验证'), findsOneWidget);
      expect(http.clients, 0);
    }, createHttpClient: http.createHttpClient);
  });
}

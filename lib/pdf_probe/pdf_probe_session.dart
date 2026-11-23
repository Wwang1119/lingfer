import 'package:flutter/foundation.dart';

import 'pdf_locate.dart';
import 'pdf_probe_models.dart';
import 'pdf_restore.dart';

/// Offline selection session.
///
/// An untagged null callback does not say whether the SDK or the user cleared
/// the native selection. It never removes a committed anchor. A later non-empty
/// callback is a new attempt and can replace that anchor when it fails.
class PdfProbeSession extends ChangeNotifier {
  PdfSelectionSnapshot? frozenSnapshot;
  int snapshotSeq = 0;
  int _appliedSeq = 0;
  int _annotationGeneration = 0;
  int annotationApplications = 0;

  LocateDecision? decision;
  PdfAnchor? anchor;
  MemoryAnnotation? annotation;
  bool nativeCleared = false;
  PdfViewport? viewportAtSelection;
  PdfLeaveRecord? leaveRecord;
  RestoreVerdict? reopenVerdict;

  static const int outboundRequestCount = 0;

  void onCallback(
    PdfSelectionSnapshot incoming, {
    required PdfViewport viewportNow,
  }) {
    if (incoming.isUntaggedClear) {
      nativeCleared = true;
      notifyListeners();
      return;
    }
    snapshotSeq += 1;
    frozenSnapshot = incoming.copy();
    viewportAtSelection = viewportNow;
    nativeCleared = false;
    notifyListeners();
  }

  void applyPending() {
    final snapshot = frozenSnapshot;
    if (snapshot == null || snapshot.isUntaggedClear) return;
    if (_appliedSeq == snapshotSeq) return;
    _appliedSeq = snapshotSeq;
    final next = locateSelection(snapshot);
    decision = next;
    if (next is LocateCommitted) {
      anchor = next.anchor;
      _annotationGeneration += 1;
      annotation = MemoryAnnotation(
        generation: _annotationGeneration,
        pageNumber: next.anchor.pageNumber,
        lineBounds: List.unmodifiable(
          next.anchor.lines.map((line) => line.bounds),
        ),
      );
      annotationApplications = 1;
    } else {
      anchor = null;
      annotation = null;
      annotationApplications = 0;
    }
    notifyListeners();
  }

  PdfLeaveRecord leave(PdfViewport viewportNow) {
    final current = decision;
    final record = PdfLeaveRecord(
      viewport: viewportNow,
      anchor: anchor,
      annotation: annotation,
      failure: current is LocateRejected ? current.failure : null,
    );
    leaveRecord = record;
    notifyListeners();
    return record;
  }

  /// In-memory reopen. [observation] defaults to unknown visuals, so the
  /// verdict stays unverified. The annotation is counted once.
  void reopen(PdfLeaveRecord record, {ReadbackObservation? observation}) {
    final seen =
        observation ?? ReadbackObservation.unknownMatchingGeometry(record);
    reopenVerdict = classifyRestore(record, seen);
    leaveRecord = record;
    anchor = record.anchor;
    annotation = record.annotation;
    decision = record.failure == null
        ? (record.anchor == null ? null : LocateCommitted(record.anchor!))
        : LocateRejected(record.failure!);
    annotationApplications = record.annotation == null ? 0 : 1;
    notifyListeners();
  }
}

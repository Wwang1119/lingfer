import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'pdf_locate.dart';
import 'pdf_probe_models.dart';
import 'pdf_restore.dart';

/// Offline selection session.
///
/// An untagged clear has no SDK source label. It drops an undecided snapshot
/// and does not remove a committed anchor. A later non-empty callback is a
/// new attempt. Explicit [dismissAnchor] is the user close.
class PdfProbeSession extends ChangeNotifier {
  PdfSelectionSnapshot? frozenSnapshot;
  int snapshotSeq = 0;
  int _appliedSeq = 0;
  int selectionGeneration = 0;
  int minValidSelectionGeneration = 0;
  int _annotationGeneration = 0;
  int _dispatchedAnnotationGeneration = 0;
  int annotationApplications = 0;

  LocateDecision? decision;
  PdfAnchor? anchor;
  MemoryAnnotation? annotation;
  bool nativeCleared = false;
  PdfViewport? viewportAtSelection;
  PdfLeaveRecord? leaveRecord;
  RestoreVerdict? reopenVerdict;

  void onCallback(
    PdfSelectionSnapshot incoming, {
    required PdfViewport viewportNow,
  }) {
    if (incoming.isUntaggedClear) {
      nativeCleared = true;
      if (snapshotSeq > _appliedSeq) {
        frozenSnapshot = null;
        _appliedSeq = snapshotSeq;
      }
      notifyListeners();
      return;
    }
    selectionGeneration += 1;
    minValidSelectionGeneration = selectionGeneration;
    snapshotSeq += 1;
    frozenSnapshot = incoming.copy();
    viewportAtSelection = viewportNow;
    nativeCleared = false;
    reopenVerdict = null;
    notifyListeners();
  }

  void applyPending() {
    if (snapshotSeq == 0 || _appliedSeq == snapshotSeq) return;
    final snapshot = frozenSnapshot;
    _appliedSeq = snapshotSeq;
    reopenVerdict = null;
    if (snapshot == null || snapshot.isUntaggedClear) {
      notifyListeners();
      return;
    }
    final next = locateSelection(snapshot);
    decision = next;
    if (next is LocateCommitted) {
      anchor = next.anchor;
      _annotationGeneration += 1;
      _dispatchAnnotation(
        MemoryAnnotation(
          generation: _annotationGeneration,
          pageNumber: next.anchor.pageNumber,
          lineBounds: List<Rect>.unmodifiable(
            next.anchor.lines.map((line) => line.bounds),
          ),
        ),
      );
    } else {
      anchor = null;
      annotation = null;
    }
    notifyListeners();
  }

  PdfLeaveRecord leave(PdfViewport viewportNow) {
    final current = decision;
    final pending = snapshotSeq > _appliedSeq;
    final record = PdfLeaveRecord(
      selectionGeneration: selectionGeneration,
      viewport: viewportNow,
      anchor: pending ? null : anchor,
      annotation: pending ? null : annotation,
      failure: pending
          ? null
          : (current is LocateRejected ? current.failure : null),
      pendingUnsettled: pending,
    );
    leaveRecord = record;
    notifyListeners();
    return record;
  }

  /// Returns false when [record] is older than the current attempt or was
  /// saved while a callback was still undecided. Neither case installs state.
  bool reopen(PdfLeaveRecord record, {ReadbackObservation? observation}) {
    if (record.pendingUnsettled ||
        record.selectionGeneration < minValidSelectionGeneration) {
      return false;
    }
    frozenSnapshot = null;
    _appliedSeq = snapshotSeq;
    nativeCleared = false;
    viewportAtSelection = null;
    final seen =
        observation ?? ReadbackObservation.unknownMatchingGeometry(record);
    reopenVerdict = classifyRestore(record, seen);
    leaveRecord = record;
    anchor = record.anchor;
    decision = record.failure == null
        ? (record.anchor == null ? null : LocateCommitted(record.anchor!))
        : LocateRejected(record.failure!);
    if (record.annotation == null) {
      annotation = null;
    } else {
      _dispatchAnnotation(record.annotation!);
    }
    notifyListeners();
    return true;
  }

  void dismissAnchor() {
    selectionGeneration += 1;
    minValidSelectionGeneration = selectionGeneration;
    frozenSnapshot = null;
    _appliedSeq = snapshotSeq;
    anchor = null;
    annotation = null;
    decision = null;
    reopenVerdict = null;
    nativeCleared = false;
    viewportAtSelection = null;
    notifyListeners();
  }

  void _dispatchAnnotation(MemoryAnnotation next) {
    annotation = next;
    if (next.generation <= _dispatchedAnnotationGeneration) return;
    _dispatchedAnnotationGeneration = next.generation;
    annotationApplications += 1;
  }
}

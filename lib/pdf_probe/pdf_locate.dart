import 'dart:ui';

import 'pdf_probe_models.dart';
import 'pdf_text_norm.dart';

LocateDecision locateSelection(PdfSelectionSnapshot snapshot) {
  final lines = snapshot.lines;
  if (lines.isEmpty) return const LocateRejected(LocateFailure.noLines);
  if (lines.any((line) => line.text.isEmpty)) {
    return const LocateRejected(LocateFailure.emptyLineText);
  }
  if (lines.any((line) => line.pageNumber < 1)) {
    return const LocateRejected(LocateFailure.invalidPage);
  }
  final page = lines.first.pageNumber;
  if (lines.any((line) => line.pageNumber != page)) {
    return const LocateRejected(LocateFailure.crossPage);
  }
  if (lines.any((line) => !_finitePositive(line.bounds))) {
    return const LocateRejected(LocateFailure.badBounds);
  }
  if (lines.any((line) => line.pageSize == null)) {
    return const LocateRejected(LocateFailure.pageSizeUnavailable);
  }
  if (lines.any((line) => !_insidePage(line.bounds, line.pageSize!))) {
    return const LocateRejected(LocateFailure.boundsOutsidePage);
  }
  if (_orderUnproven(lines)) {
    return const LocateRejected(LocateFailure.orderAmbiguous);
  }
  final callback = snapshot.selectedText;
  if (callback == null ||
      !selectionTextsEqual(callback, lines.map((line) => line.text))) {
    return const LocateRejected(LocateFailure.textMismatch);
  }
  if (snapshot.evidence != PageEvidenceKind.externalFixture) {
    return const LocateRejected(LocateFailure.pageIdentityUnproven);
  }
  final hash = snapshot.fileHash;
  if (hash == null || hash.isEmpty) {
    return const LocateRejected(LocateFailure.fileHashMissing);
  }
  return LocateCommitted(
    PdfAnchor(
      fileHash: hash,
      pageNumber: page,
      lines: List<PdfLineSnapshot>.unmodifiable(lines),
    ),
  );
}

bool _finitePositive(Rect bounds) {
  return bounds.left.isFinite &&
      bounds.top.isFinite &&
      bounds.right.isFinite &&
      bounds.bottom.isFinite &&
      bounds.width > 0 &&
      bounds.height > 0;
}

bool _insidePage(Rect bounds, Size pageSize) {
  if (!(pageSize.width > 0) || !(pageSize.height > 0)) return false;
  return bounds.left >= 0 &&
      bounds.top >= 0 &&
      bounds.right <= pageSize.width &&
      bounds.bottom <= pageSize.height;
}

/// Overlapping boxes, or horizontally disjoint boxes, do not have a reading
/// order this probe can prove. The check does not reorder lines and is not a
/// column detector.
bool _orderUnproven(List<PdfLineSnapshot> lines) {
  for (var i = 0; i < lines.length; i += 1) {
    for (var j = i + 1; j < lines.length; j += 1) {
      final a = lines[i].bounds;
      final b = lines[j].bounds;
      if (_positiveIntersection(a, b) || _horizontallyDisjoint(a, b)) {
        return true;
      }
    }
  }
  return false;
}

bool _positiveIntersection(Rect a, Rect b) {
  final width = _overlap(a.left, a.right, b.left, b.right);
  final height = _overlap(a.top, a.bottom, b.top, b.bottom);
  return width > 0 && height > 0;
}

double _overlap(double a0, double a1, double b0, double b1) {
  final start = a0 > b0 ? a0 : b0;
  final end = a1 < b1 ? a1 : b1;
  return end - start;
}

bool _horizontallyDisjoint(Rect a, Rect b) {
  return a.right <= b.left || b.right <= a.left;
}

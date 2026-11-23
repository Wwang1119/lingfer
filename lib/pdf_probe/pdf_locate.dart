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
  if (lines.any((line) => !_usablePageSize(line.pageSize!))) {
    return const LocateRejected(LocateFailure.badBounds);
  }
  final pageSize = lines.first.pageSize!;
  if (lines.any((line) => line.pageSize != pageSize)) {
    return const LocateRejected(LocateFailure.pageSizeInconsistent);
  }
  if (lines.any((line) => !_insidePage(line.bounds, pageSize))) {
    return const LocateRejected(LocateFailure.boundsOutsidePage);
  }
  if (_orderUnproven(lines)) {
    return const LocateRejected(LocateFailure.orderAmbiguous);
  }
  final callback = snapshot.selectedText ?? '';
  final joined = joinCapturedLines(lines.map((line) => line.text));
  if (normalizeSelectionText(callback).isEmpty ||
      normalizeSelectionText(joined).isEmpty) {
    return const LocateRejected(LocateFailure.emptyLineText);
  }
  if (!selectionTextsEqual(callback, lines.map((line) => line.text))) {
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
      evidence: snapshot.evidence,
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

bool _usablePageSize(Size pageSize) {
  return pageSize.width.isFinite &&
      pageSize.height.isFinite &&
      pageSize.width > 0 &&
      pageSize.height > 0;
}

bool _insidePage(Rect bounds, Size pageSize) {
  return bounds.left >= 0 &&
      bounds.top >= 0 &&
      bounds.right <= pageSize.width &&
      bounds.bottom <= pageSize.height;
}

/// Order this probe will accept, and only inside that boundary.
///
/// For unrotated horizontal text in top-origin page coordinates, capture
/// order must run downward: an earlier box cannot sit below a later one.
/// Overlap and horizontally disjoint boxes are also rejected. Nothing here
/// reorders lines or claims a multi-column reading order.
bool _orderUnproven(List<PdfLineSnapshot> lines) {
  for (var i = 0; i < lines.length; i += 1) {
    for (var j = i + 1; j < lines.length; j += 1) {
      final a = lines[i].bounds;
      final b = lines[j].bounds;
      final reversed = a.bottom > b.top;
      if (_positiveIntersection(a, b) ||
          _horizontallyDisjoint(a, b) ||
          reversed) {
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

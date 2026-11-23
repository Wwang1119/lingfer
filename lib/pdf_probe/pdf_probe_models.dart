import 'dart:ui';

/// Where a page number on a captured line came from.
///
/// [publicCurrentPageGetter] is the public `getSelectedTextLines` result.
/// That getter reads the canvas of `controller.pageNumber`, so a matching
/// page number is not independent proof of the gesture's page.
/// [externalFixture] is written by a test as its own ground truth. The
/// Syncfusion adapter is not allowed to produce it.
enum PageEvidenceKind { publicCurrentPageGetter, externalFixture }

enum PdfOrientation { portrait, landscape }

class PdfViewport {
  const PdfViewport({
    required this.zoom,
    required this.scrollX,
    required this.scrollY,
    required this.width,
    required this.height,
    required this.orientation,
  });

  final double zoom;
  final double scrollX;
  final double scrollY;
  final double width;
  final double height;
  final PdfOrientation orientation;

  static const identity = PdfViewport(
    zoom: 1,
    scrollX: 0,
    scrollY: 0,
    width: 400,
    height: 800,
    orientation: PdfOrientation.portrait,
  );
}

class PdfLineSnapshot {
  const PdfLineSnapshot({
    required this.pageNumber,
    required this.text,
    required this.bounds,
    required this.pageSize,
  });

  final int pageNumber;
  final String text;
  final Rect bounds;
  final Size? pageSize;
}

class PdfSelectionSnapshot {
  const PdfSelectionSnapshot({
    required this.selectedText,
    required this.globalSelectedRegion,
    required this.controllerPageNumber,
    required this.lines,
    required this.evidence,
    required this.fileHash,
  });

  final String? selectedText;
  final Rect? globalSelectedRegion;
  final int? controllerPageNumber;
  final List<PdfLineSnapshot> lines;
  final PageEvidenceKind evidence;
  final String? fileHash;

  bool get isUntaggedClear => selectedText == null || selectedText!.isEmpty;

  PdfSelectionSnapshot copy() {
    return PdfSelectionSnapshot(
      selectedText: selectedText,
      globalSelectedRegion: globalSelectedRegion,
      controllerPageNumber: controllerPageNumber,
      lines: List<PdfLineSnapshot>.unmodifiable(lines),
      evidence: evidence,
      fileHash: fileHash,
    );
  }
}

enum LocateFailure {
  noLines,
  emptyLineText,
  invalidPage,
  crossPage,
  badBounds,
  pageSizeUnavailable,
  boundsOutsidePage,
  orderAmbiguous,
  textMismatch,
  fileHashMissing,
  pageIdentityUnproven,
}

class PdfAnchor {
  const PdfAnchor({
    required this.fileHash,
    required this.pageNumber,
    required this.lines,
  });

  final String fileHash;
  final int pageNumber;
  final List<PdfLineSnapshot> lines;
}

class MemoryAnnotation {
  const MemoryAnnotation({
    required this.generation,
    required this.pageNumber,
    required this.lineBounds,
  });

  final int generation;
  final int pageNumber;
  final List<Rect> lineBounds;
}

sealed class LocateDecision {
  const LocateDecision();
}

class LocateRejected extends LocateDecision {
  const LocateRejected(this.failure);

  final LocateFailure failure;
}

class LocateCommitted extends LocateDecision {
  const LocateCommitted(this.anchor);

  final PdfAnchor anchor;
}

class PdfRestorePlan {
  const PdfRestorePlan({
    required this.initialZoomLevel,
    required this.initialScrollX,
    required this.initialScrollY,
    required this.initialPageNumber,
    required this.usePageStorageKey,
  });

  final double initialZoomLevel;
  final double initialScrollX;
  final double initialScrollY;
  final int initialPageNumber;
  final bool usePageStorageKey;
}

class PdfLeaveRecord {
  const PdfLeaveRecord({
    required this.viewport,
    required this.anchor,
    required this.annotation,
    required this.failure,
  });

  final PdfViewport viewport;
  final PdfAnchor? anchor;
  final MemoryAnnotation? annotation;
  final LocateFailure? failure;
}

/// Observations supplied by a caller. Null visual fields mean they were not
/// observed. This probe never fills them from a device.
class ReadbackObservation {
  const ReadbackObservation({
    required this.zoom,
    required this.scrollX,
    required this.scrollY,
    required this.width,
    required this.height,
    required this.orientation,
    required this.sentenceVisible,
    required this.highlightOnGlyphs,
    required this.cardOccludesSentence,
    required this.stableFrameCount,
  });

  final double zoom;
  final double scrollX;
  final double scrollY;
  final double width;
  final double height;
  final PdfOrientation orientation;
  final bool? sentenceVisible;
  final bool? highlightOnGlyphs;
  final bool? cardOccludesSentence;
  final int stableFrameCount;

  factory ReadbackObservation.unknownMatchingGeometry(PdfLeaveRecord record) {
    final viewport = record.viewport;
    return ReadbackObservation(
      zoom: viewport.zoom,
      scrollX: viewport.scrollX,
      scrollY: viewport.scrollY,
      width: viewport.width,
      height: viewport.height,
      orientation: viewport.orientation,
      sentenceVisible: null,
      highlightOnGlyphs: null,
      cardOccludesSentence: null,
      stableFrameCount: 0,
    );
  }
}

enum RestoreVerdict { selectionRestored, unverified, failed }

/// Proposed only. [classifyRestore] does not treat these deltas as a pass.
const double kProposedUncalibratedZoomDelta = 0.01;
const double kProposedUncalibratedScrollDelta = 1.0;

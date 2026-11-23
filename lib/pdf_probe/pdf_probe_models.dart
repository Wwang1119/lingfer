import 'dart:ui';

import 'pdf_text_norm.dart';

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

  /// Scroll may be zero. Zoom and both viewport axes must be finite and positive.
  bool get isLegal {
    return zoom.isFinite &&
        zoom > 0 &&
        width.isFinite &&
        width > 0 &&
        height.isFinite &&
        height > 0 &&
        scrollX.isFinite &&
        scrollY.isFinite;
  }

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

  /// Blank after the frozen comparison rule, or a null callback.
  ///
  /// TAB and NBSP survive that rule, so they are not treated as a clear.
  bool get isUntaggedClear {
    final text = selectedText;
    if (text == null) return true;
    return normalizeSelectionText(text).isEmpty;
  }

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
  pageSizeInconsistent,
}

class PdfAnchor {
  const PdfAnchor({
    required this.fileHash,
    required this.pageNumber,
    required this.lines,
    required this.evidence,
  });

  final String fileHash;
  final int pageNumber;
  final List<PdfLineSnapshot> lines;
  final PageEvidenceKind evidence;
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
    required this.selectionGeneration,
    required this.viewport,
    required this.anchor,
    required this.annotation,
    required this.failure,
    required this.pendingUnsettled,
  });

  final int selectionGeneration;
  final PdfViewport viewport;
  final PdfAnchor? anchor;
  final MemoryAnnotation? annotation;
  final LocateFailure? failure;

  /// The leave happened before the current callback was decided.
  /// Its viewport must not be paired with an older anchor.
  final bool pendingUnsettled;
}

enum ObservationSource { syntheticFixture, deviceObserved }

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
    required this.source,
    required this.targetFileHash,
    required this.targetPageNumber,
    required this.leaveSelectionGeneration,
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

  /// A caller-supplied count. One or three does not prove stability.
  final int stableFrameCount;
  final ObservationSource source;
  final String? targetFileHash;
  final int? targetPageNumber;
  final int? leaveSelectionGeneration;

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
      source: ObservationSource.syntheticFixture,
      targetFileHash: record.anchor?.fileHash,
      targetPageNumber: record.anchor?.pageNumber,
      leaveSelectionGeneration: record.selectionGeneration,
    );
  }
}

enum RestoreVerdict {
  selectionRestored,
  fixtureConditionsMet,
  unverified,
  failed,
}

/// Proposed only. [classifyRestore] does not treat these deltas as a pass.
const double kProposedUncalibratedZoomDelta = 0.01;
const double kProposedUncalibratedScrollDelta = 1.0;

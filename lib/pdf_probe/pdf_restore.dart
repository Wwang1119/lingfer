import 'pdf_probe_models.dart';

PdfRestorePlan? planRestore(PdfLeaveRecord record) {
  if (!record.viewport.isLegal || record.pendingUnsettled) return null;
  return PdfRestorePlan(
    initialZoomLevel: record.viewport.zoom,
    initialScrollX: record.viewport.scrollX,
    initialScrollY: record.viewport.scrollY,
    initialPageNumber: 1,
    usePageStorageKey: false,
  );
}

bool withinProposedUncalibratedTolerance({
  required PdfViewport leave,
  required ReadbackObservation observation,
}) {
  final zoomGap = (observation.zoom - leave.zoom).abs();
  final xGap = (observation.scrollX - leave.scrollX).abs();
  final yGap = (observation.scrollY - leave.scrollY).abs();
  return zoomGap <= kProposedUncalibratedZoomDelta &&
      xGap <= kProposedUncalibratedScrollDelta &&
      yGap <= kProposedUncalibratedScrollDelta;
}

bool geometryChanged(PdfViewport leave, ReadbackObservation observation) {
  return observation.width != leave.width ||
      observation.height != leave.height ||
      observation.orientation != leave.orientation;
}

bool _numbersMatchLeave(PdfViewport leave, ReadbackObservation observation) {
  return observation.zoom == leave.zoom &&
      observation.scrollX == leave.scrollX &&
      observation.scrollY == leave.scrollY;
}

bool _observationLegal(ReadbackObservation observation) {
  return observation.zoom.isFinite &&
      observation.zoom > 0 &&
      observation.width.isFinite &&
      observation.width > 0 &&
      observation.height.isFinite &&
      observation.height > 0 &&
      observation.scrollX.isFinite &&
      observation.scrollY.isFinite;
}

bool _annotationMatches(PdfAnchor anchor, MemoryAnnotation annotation) {
  if (annotation.pageNumber != anchor.pageNumber) return false;
  if (annotation.lineBounds.length != anchor.lines.length) return false;
  for (var i = 0; i < anchor.lines.length; i += 1) {
    if (annotation.lineBounds[i] != anchor.lines[i].bounds) return false;
  }
  return true;
}

bool _observedFailure(ReadbackObservation observation) {
  return observation.sentenceVisible == false ||
      observation.highlightOnGlyphs == false ||
      observation.cardOccludesSentence == true;
}

/// Exact numbers are necessary and not sufficient. [stableFrameCount] is not
/// a pass threshold: zero blocks the success-like results, and three does not
/// create one. Synthetic observations cannot return [RestoreVerdict.selectionRestored].
RestoreVerdict classifyRestore(
  PdfLeaveRecord record,
  ReadbackObservation observation,
) {
  if (!record.viewport.isLegal || !_observationLegal(observation)) {
    return RestoreVerdict.failed;
  }
  if (_observedFailure(observation)) return RestoreVerdict.failed;
  if (geometryChanged(record.viewport, observation)) {
    return RestoreVerdict.unverified;
  }
  final sentence = observation.sentenceVisible;
  final glyphs = observation.highlightOnGlyphs;
  final occludes = observation.cardOccludesSentence;
  if (sentence == null || glyphs == null || occludes == null) {
    return RestoreVerdict.unverified;
  }
  final anchor = record.anchor;
  final annotation = record.annotation;
  final numbersMatch = _numbersMatchLeave(record.viewport, observation);
  final bound =
      anchor != null &&
      observation.targetFileHash == anchor.fileHash &&
      observation.targetPageNumber == anchor.pageNumber &&
      observation.leaveSelectionGeneration == record.selectionGeneration;
  final ready =
      numbersMatch &&
      sentence &&
      glyphs &&
      !occludes &&
      record.failure == null &&
      !record.pendingUnsettled &&
      anchor != null &&
      anchor.fileHash.isNotEmpty &&
      anchor.pageNumber >= 1 &&
      anchor.lines.isNotEmpty &&
      annotation != null &&
      _annotationMatches(anchor, annotation) &&
      bound &&
      observation.stableFrameCount >= 1;
  if (!ready || anchor.evidence != PageEvidenceKind.externalFixture) {
    return RestoreVerdict.failed;
  }
  // A fixture anchor has no independent device page proof. The strongest
  // result is the fixture predicate, including when the caller marks the
  // observation as device-observed. selectionRestored is not issued here.
  return RestoreVerdict.fixtureConditionsMet;
}

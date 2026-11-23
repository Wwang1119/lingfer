import 'pdf_probe_models.dart';

PdfRestorePlan planRestore(PdfLeaveRecord record) {
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

/// Three stable frames are ignored on purpose. A numeric match is not a pass.
RestoreVerdict classifyRestore(
  PdfLeaveRecord record,
  ReadbackObservation observation,
) {
  if (geometryChanged(record.viewport, observation)) {
    return RestoreVerdict.unverified;
  }
  final sentence = observation.sentenceVisible;
  final glyphs = observation.highlightOnGlyphs;
  final occludes = observation.cardOccludesSentence;
  if (sentence == null || glyphs == null || occludes == null) {
    return RestoreVerdict.unverified;
  }
  final numbersMatch = _numbersMatchLeave(record.viewport, observation);
  final anchor = record.anchor;
  if (numbersMatch &&
      sentence &&
      glyphs &&
      !occludes &&
      anchor != null &&
      anchor.lines.isNotEmpty) {
    return RestoreVerdict.selectionRestored;
  }
  return RestoreVerdict.failed;
}

/// An inserted gloss range, with offsets measured in UTF-16 code units.
class ReaderAnnotationSpan {
  const ReaderAnnotationSpan({
    required this.sourceOffset,
    required this.renderedStart,
    required this.renderedEnd,
  });

  final int sourceOffset;
  final int renderedStart;
  final int renderedEnd;
}

/// Maps reading positions through spans emitted in order by onAnnotation.
/// Original parentheses are prose and never appear in this list.
class ReaderTextAnchor {
  const ReaderTextAnchor._();

  static int sourceOffset(
    int renderedOffset,
    List<ReaderAnnotationSpan> spans,
  ) {
    var insertedLength = 0;
    for (final span in spans) {
      if (renderedOffset < span.renderedStart) break;
      if (renderedOffset < span.renderedEnd) return span.sourceOffset;
      insertedLength += span.renderedEnd - span.renderedStart;
    }
    final offset = renderedOffset - insertedLength;
    return offset < 0 ? 0 : offset;
  }

  static int renderedOffset(
    int sourceOffset,
    List<ReaderAnnotationSpan> spans,
  ) {
    var insertedLength = 0;
    for (final span in spans) {
      // A word-end anchor intentionally lands before its new gloss, keeping
      // that source location stable when annotations appear or change length.
      if (span.sourceOffset >= sourceOffset) break;
      insertedLength += span.renderedEnd - span.renderedStart;
    }
    final offset = sourceOffset + insertedLength;
    return offset < 0 ? 0 : offset;
  }
}

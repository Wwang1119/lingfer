/// Selection text comparison for the offline probe.
///
/// The whole string is normalized in two steps only: CR and CRLF become LF,
/// then only leading and trailing U+0020 and U+000A are removed. This is an
/// upper bound. It does not trim other Unicode whitespace, apply NFC, or
/// collapse spaces inside the string.
library;

String unifyNewlines(String value) {
  return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

String trimAsciiSpaceAndLineFeed(String value) {
  var start = 0;
  var end = value.length;
  while (start < end) {
    final unit = value.codeUnitAt(start);
    if (unit != 0x20 && unit != 0x0A) break;
    start += 1;
  }
  while (end > start) {
    final unit = value.codeUnitAt(end - 1);
    if (unit != 0x20 && unit != 0x0A) break;
    end -= 1;
  }
  return value.substring(start, end);
}

String normalizeSelectionText(String value) {
  return trimAsciiSpaceAndLineFeed(unifyNewlines(value));
}

String joinCapturedLines(Iterable<String> lines) {
  return lines.join('\n');
}

bool selectionTextsEqual(String callbackText, Iterable<String> lineTexts) {
  final left = normalizeSelectionText(callbackText);
  final right = normalizeSelectionText(joinCapturedLines(lineTexts));
  return left == right;
}

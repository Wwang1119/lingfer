import Foundation

/// A short, locally derived excerpt that always keeps the selected surface form.
/// String indices are used for clipping; Foundation ranges remain UTF-16 ranges.
struct LivePreviewExcerpt {
  let text: String
  let highlight: NSRange?

  static func sentence(source: String, surface: String, range: NSRange?) -> String? {
    guard !surface.isEmpty else{return nil}
    let valid=range.flatMap{Range($0,in:source)}.flatMap { value -> Range<String.Index>? in
      String(source[value]).caseInsensitiveCompare(surface) == .orderedSame ? value : nil
    }
    guard let match=valid ?? source.range(of:surface,options:.caseInsensitive) else{return nil}
    var start=match.lowerBound
    var end=match.upperBound
    for _ in 0..<240 where start>source.startIndex {
      let previous=source.index(before:start)
      if ".!?;。！？；".contains(source[previous]) {break}
      if source[previous]=="\n",previous>source.startIndex,source[source.index(before:previous)]=="\n" {break}
      start=previous
    }
    for _ in 0..<300 where end<source.endIndex {
      let character=source[end]
      if character=="\n",source.index(after:end)<source.endIndex,source[source.index(after:end)]=="\n" {break}
      end=source.index(after:end)
      if ".!?;。！？；".contains(character) {break}
    }
    return String(source[start..<end]).trimmingCharacters(in:.whitespacesAndNewlines)
  }

  static func make(context: String, surface: String, limit: Int = 130) -> Self {
    let clean = context.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !surface.isEmpty, let match = clean.range(of: surface, options: .caseInsensitive) else {
      let prefix=String(clean.prefix(max(1,limit)))
      return Self(text:prefix+(prefix.count<clean.count ? "…" : ""),highlight:nil)
    }
    let budget = max(surface.count, limit, 1)
    let before = min(36, max(0, (budget - surface.count) / 3))
    var start = clean.index(match.lowerBound, offsetBy: -before, limitedBy: clean.startIndex) ?? clean.startIndex
    let end = clean.index(start, offsetBy: budget, limitedBy: clean.endIndex) ?? clean.endIndex
    if end == clean.endIndex {
      start = clean.index(end, offsetBy: -budget, limitedBy: clean.startIndex) ?? clean.startIndex
    }
    let value = (start > clean.startIndex ? "…" : "") + String(clean[start..<end]) + (end < clean.endIndex ? "…" : "")
    let highlighted = value.range(of: surface, options: .caseInsensitive).map { NSRange($0, in: value) }
    return Self(text: value, highlight: highlighted)
  }
}

/// Lossless text pages measured by the actual renderer. Both sides retain
/// their sentence-group identity; independent continuation counts never claim
/// that arbitrary substrings are literal word-for-word alignments.
enum LivePreviewPagination {
  static func chunks(_ text:String,fits:(String)->Bool)->[String] {
    guard !text.isEmpty else{return []}
    let characters=Array(text)
    var result:[String]=[];var start=0
    while start<characters.count {
      var low=start+1,high=characters.count,best=start+1
      while low<=high {
        let mid=low+(high-low)/2
        if fits(String(characters[start..<mid])) {best=mid;low=mid+1} else {high=mid-1}
      }
      if best<characters.count {
        let floor=start+max(1,(best-start)*2/3)
        if let boundary=(floor..<best).last(where:{characters[$0].isWhitespace || ".!?;。！？；".contains(characters[$0])}) {best=boundary+1}
      }
      result.append(String(characters[start..<best]));start=best
    }
    return result
  }
}

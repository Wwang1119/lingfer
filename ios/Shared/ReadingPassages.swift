import Foundation
import NaturalLanguage

/// OCR wraps are not paragraph boundaries. Group complete sentences before
/// requesting translation, preserving the existing segment JSON contract.
enum ReadingPassages {
  struct SourceChunk {
    let text:String
    let utf16Start:Int
  }
  /// Cover all accepted source text, including screens with many short OCR
  /// lines. Chunk indices remain valid in NSString/Vision's UTF-16 coordinates.
  static func sourceChunks(_ text:String,maximumCharacters:Int=600)->[SourceChunk] {
    guard !text.isEmpty else{return []}
    let maximum=max(1,maximumCharacters)
    var chunks:[SourceChunk]=[];var start=text.startIndex;var offset=0
    while start<text.endIndex {
      var end=text.index(start,offsetBy:maximum,limitedBy:text.endIndex) ?? text.endIndex
      if end<text.endIndex {
        let boundaryStart=text.index(start,offsetBy:maximum*4/5,limitedBy:end) ?? start
        if let split=text[boundaryStart..<end].lastIndex(where:{$0.isWhitespace}) {end=text.index(after:split)}
      }
      let part=String(text[start..<end]);chunks.append(SourceChunk(text:part,utf16Start:offset))
      offset += (part as NSString).length;start=end
    }
    return chunks
  }
  static func make(_ text:String, sentencesPerPart:Int = 3, limit:Int = 900)->[String] {
    var result:[String]=[]
    for block in text.components(separatedBy:"\n\n") {
      let clean=block.replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
      guard !clean.isEmpty else {continue}
      let tokenizer=NLTokenizer(unit:.sentence);tokenizer.string=clean
      var sentences:[String]=[]
      tokenizer.enumerateTokens(in:clean.startIndex..<clean.endIndex) { range,_ in
        sentences.append(String(clean[range]).trimmingCharacters(in:.whitespacesAndNewlines));return true
      }
      if sentences.isEmpty {sentences=[clean]}
      var group="";var count=0
      for sentence in sentences {
        if !group.isEmpty,(count>=sentencesPerPart || group.count+sentence.count>limit) {result.append(group);group="";count=0}
        if sentence.count>1400 {
          if !group.isEmpty {result.append(group);group="";count=0}
          result.append(contentsOf:chunks(sentence,units:1400))
        } else {group += (group.isEmpty ? "" : " ")+sentence;count += 1}
      }
      if !group.isEmpty {result.append(group)}
    }
    return result
  }

  /// Bounded, lossless display pages. CJK glyphs need approximately twice the
  /// horizontal space of Latin letters. Prefer sentence/word boundaries.
  static func chunks(_ text:String,units:Int = 300)->[String] {
    guard !text.isEmpty else{return []}
    var result:[String]=[];var start=text.startIndex
    while start<text.endIndex {
      var end=start;var used=0;var boundary:String.Index?
      while end<text.endIndex {
        let character=text[end];let cost=character.unicodeScalars.allSatisfy{$0.isASCII} ? 1 : 2
        if used+cost>max(2,units) {break}
        used += cost;end=text.index(after:end)
        if character.isWhitespace || ".!?;。！？；".contains(character) {boundary=end}
      }
      if end<text.endIndex,let boundary,boundary>start,text.distance(from:start,to:boundary)>max(1,text.distance(from:start,to:end)/2) {end=boundary}
      if end==start {end=text.index(after:start)}
      result.append(String(text[start..<end]));start=end
    }
    return result
  }
}

import Foundation

struct ShareWord: Identifiable, Codable {
  let word: String
  let surface: String
  let translation: String
  let tags: [String]
  let context: String
  var sourceLanguage: String? = nil
  var targetLanguage: String? = nil
  var sourceStart: Int? = nil
  var sourceEnd: Int? = nil
  var annotation: String? = nil
  var shortTranslation: String {
    if let annotation, !annotation.isEmpty { return annotation }
    let first = translation.components(separatedBy: "\n").first ?? translation
    return first.replacingOccurrences(of: "^[a-zA-Z./ ,]+\\.\\s*", with: "", options: .regularExpression).components(separatedBy: CharacterSet(charactersIn: ",，;；")).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? first
  }
  var id: String { sourceLanguage == nil || sourceLanguage == "en" || targetLanguage == "en" ? word : "\(sourceLanguage ?? "auto"):\(targetLanguage ?? "zh"):\(word)" }
}

final class OfflineLexicon {
  struct Entry: Decodable { let translation: String; let tags: [String] }
  struct Document: Decodable { let entries: [String: Entry] }
  let entries: [String: Entry]
  private let english = try! NSRegularExpression(pattern: "[A-Za-z]+")

  private func boundary(_ source: NSString, _ at: Int) -> Bool {
    let value = source.substring(with: NSRange(location: at, length: 1))
    if ".!?;。！？；".contains(value) { return true }
    if value != "\n" { return false }
    if at == 0 || at + 1 == source.length || source.character(at: at - 1) == 10 || source.character(at: at + 1) == 10 { return true }
    var left = at
    var right = at + 1
    while left > 0 && source.character(at: left - 1) != 10 { left -= 1 }
    while right < source.length && source.character(at: right) != 10 { right += 1 }
    let previous = source.substring(with: NSRange(location: left, length: at - left)).trimmingCharacters(in: .whitespacesAndNewlines)
    let next = source.substring(with: NSRange(location: at + 1, length: right - at - 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    return previous.count < 35 || english.numberOfMatches(in: previous, range: NSRange(location: 0, length: (previous as NSString).length)) < 5 || english.numberOfMatches(in: next, range: NSRange(location: 0, length: (next as NSString).length)) < 2 || next == next.uppercased()
  }

  init(data: Data) throws { entries = try JSONDecoder().decode(Document.self, from: data).entries }

  static func load() throws -> OfflineLexicon {
    guard let url = Bundle.main.url(forResource: "vocabulary", withExtension: "json") else {
      throw NSError(domain: "Lingfer", code: 1, userInfo: [NSLocalizedDescriptionKey: "阅读词表未加载完成。"])
    }
    return try OfflineLexicon(data: Data(contentsOf: url))
  }

  func lemma(_ value: String) -> String? {
    let word = value.lowercased().replacingOccurrences(of: "’", with: "'")
    if entries[word] != nil { return word }
    var candidates: [String] = []
    if word.hasSuffix("'s") { candidates.append(String(word.dropLast(2))) }
    if word.hasSuffix("ies") && word.count > 4 { candidates.append(String(word.dropLast(3)) + "y") }
    if word.hasSuffix("es") { candidates.append(String(word.dropLast(2))) }
    if word.hasSuffix("s") && !word.hasSuffix("ss") { candidates.append(String(word.dropLast())) }
    for suffix in ["ing", "ed"] where word.hasSuffix(suffix) && word.count >= suffix.count + 3 {
      let stem = String(word.dropLast(suffix.count))
      candidates += [stem, stem + "e"]
      if stem.count > 2 && stem.last == stem.dropLast().last { candidates.append(String(stem.dropLast())) }
      if suffix == "ed" && stem.hasSuffix("i") { candidates.append(String(stem.dropLast()) + "y") }
    }
    return candidates.first { entries[$0] != nil }
  }

  func eligible(_ word: String, level: String) -> Bool {
    guard let key = lemma(word), let entry = entries[key] else { return false }
    let tag = ["zhongkao":"zk", "gaokao":"gk", "cet4":"cet4", "cet6":"cet6", "kaoyan":"ky", "ielts":"ielts", "toefl":"toefl"][level] ?? "cet4"
    return entry.tags.contains(tag) && (tag == "zk" || !entry.tags.contains("zk")) && (["zk", "gk"].contains(tag) || !entry.tags.contains("gk"))
  }

  func extract(_ text: String, level: String, known: Set<String>) -> [ShareWord] {
    let tag = ["zhongkao": "zk", "gaokao": "gk", "cet4": "cet4", "cet6": "cet6", "kaoyan": "ky", "ielts": "ielts", "toefl": "toefl"][level] ?? "cet4"
    guard let regex = try? NSRegularExpression(pattern: "[A-Za-z]+(?:['’-][A-Za-z]+)*") else { return [] }
    let source = text as NSString
    var seen = Set<String>()
    var result: [ShareWord] = []
    for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
      let surface = source.substring(with: match.range)
      guard let word = lemma(surface), let entry = entries[word], !known.contains(word), !seen.contains(word), entry.tags.contains(tag) else { continue }
      if tag != "zk" && entry.tags.contains("zk") { continue }
      if !["zk", "gk"].contains(tag) && entry.tags.contains("gk") { continue }
      seen.insert(word)
      var left = match.range.location
      var right = NSMaxRange(match.range)
      while left > 0 && match.range.location - left < 180 {
        if boundary(source, left - 1) { break }
        left -= 1
      }
      while right < source.length && right - NSMaxRange(match.range) < 220 {
        if boundary(source, right) { break }
        right += 1
      }
      if right < source.length && boundary(source, right) { right += 1 }
      result.append(ShareWord(word: word, surface: surface, translation: entry.translation, tags: entry.tags, context: source.substring(with: NSRange(location: left, length: right - left)).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s*\\n\\s*", with: " ", options: .regularExpression)))
      result[result.count-1].sourceLanguage = "en"
      result[result.count-1].targetLanguage = "zh"
      result[result.count-1].sourceStart = match.range.location
      result[result.count-1].sourceEnd = NSMaxRange(match.range)
      if result.count >= 24 { break }
    }
    return result
  }
}

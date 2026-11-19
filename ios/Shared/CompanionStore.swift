import Foundation

enum CompanionAIConsentRule {
  static let currentVersion=1
  static func decided(_ values:[String:Any])->Bool {values["aiConsentVersion"] as? Int == currentVersion}
  static func allowed(_ values:[String:Any])->Bool {decided(values) && values["aiConsentAllowed"] as? Bool == true}
}

/// Coordinated files make an extension's latest write visible immediately in
/// the main process, without depending on a per-process preferences cache.
final class CompanionPreferences {
  private let legacy = UserDefaults(suiteName: CompanionStore.group) ?? .standard
  private let keys = ["level", "known", "saved", "lastText", "proxyUrl", "appSecret", "sourceLanguage", "targetLanguage", "generalDifficulty", "automatic", "readingMode", "lastTranslationSegments", "lastTranslatedText", "lastTranslationSource", "lastTranslationTarget", "lastDocumentUpdatedAt", "liveReadingHistoryV1", "aiConsentVersion", "aiConsentAllowed"]
  private var file: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CompanionStore.group)?
      .appendingPathComponent("reading-state.json")
  }

  private func decode(_ url: URL) -> [String: Any] {
    if let data = try? Data(contentsOf: url),
       let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return values }
    return keys.reduce(into: [:]) { result, key in result[key] = legacy.object(forKey: key) }
  }

  func snapshot() -> [String: Any] {
    guard let file else { return keys.reduce(into: [:]) { $0[$1] = UserDefaults.standard.object(forKey: $1) } }
    var values: [String: Any] = [:]
    var error: NSError?
    NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { values = self.decode($0) }
    return error == nil ? values : decode(file)
  }

  func string(forKey key: String) -> String? { snapshot()[key] as? String }
  func stringArray(forKey key: String) -> [String]? { snapshot()[key] as? [String] }

  @discardableResult
  func merge(_ changes: [String: Any], removing:[String] = []) -> Bool {
    var changes=changes
    if changes["lastText"] is String {changes["lastDocumentUpdatedAt"]=Date().timeIntervalSince1970}
    guard let file else {
      for key in removing {UserDefaults.standard.removeObject(forKey:key)}
      for (key, value) in changes { UserDefaults.standard.set(value, forKey: key) }
      return false
    }
    var written = false
    var error: NSError?
    NSFileCoordinator().coordinate(writingItemAt: file, options: .forMerging, error: &error) { url in
      do {
        var values = self.decode(url)
        for key in removing {values.removeValue(forKey:key)}
        values.merge(changes) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: values)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        written = true
      } catch { written = false }
    }
    return error == nil && written
  }

  @discardableResult
  func set(_ value: Any, forKey key: String) -> Bool { merge([key: value]) }
}

enum CompanionStore {
  static let group = "group.com.wang.yudu"
  static let defaults = CompanionPreferences()
  static let aiConsentVersion = CompanionAIConsentRule.currentVersion
  static let privacyPolicyURL=URL(string:"https://docs.qq.com/doc/DRnZUeGhsY2JraXJD")!
  static let aiConsentDisclosure="联网翻译、词汇筛选、文字整理和语境讲解会把对应 OCR 文字、原文选段、词语及上下文，通过腾讯云中转发送给 DeepSeek 处理。书内阅读、整页对照及随屏阅读启用这些功能后，内容变化时可能自动发送文字。屏幕图片和照片在本机识别，不随这些 AI 请求上传。\n\n文字可能包含个人信息，语渡不保证自动脱敏。腾讯云和 DeepSeek 的实际云端留存规则尚未核实，不承诺请求后立即删除或不留日志。\n\n你可以选择仅本机阅读，继续使用本地资料、已保存结果和可用的离线词义；允许或关闭联网 AI 均不影响你的收藏和阅读进度。可在设置中更改选择。"
  static var aiConsentDecided:Bool {CompanionAIConsentRule.decided(defaults.snapshot())}
  static var aiConsentAllowed:Bool {aiConsentState()["allowed"] as? Bool == true}
  static func aiConsentState()->[String:Any] {
    let values=defaults.snapshot()
    return ["version":values["aiConsentVersion"] as? Int ?? 0,"allowed":CompanionAIConsentRule.allowed(values)]
  }
  @discardableResult static func setAIConsent(allowed:Bool)->Bool {
    let written=defaults.merge(["aiConsentVersion":aiConsentVersion,"aiConsentAllowed":allowed])
    NotificationCenter.default.post(name:Notification.Name("lingferAIConsentChanged"),object:nil)
    return written
  }
  static var sharedAvailable: Bool {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
  }
  static func status() -> [String: Any] {
    let values = defaults.snapshot()
    var status:[String:Any] = [
      "supported": false, "running": false, "sharedAvailable": sharedAvailable,
      "aiConsentVersion":values["aiConsentVersion"] as? Int ?? 0,
      "aiConsentAllowed":CompanionAIConsentRule.allowed(values),
      "known": values["known"] as? [String] ?? [],
      "saved": values["saved"] as? String ?? "[]",
      "level": values["level"] as? String ?? "cet4",
      "lastText": values["lastText"] as? String ?? "",
      "sourceLanguage": values["sourceLanguage"] as? String ?? "auto",
      "targetLanguage": values["targetLanguage"] as? String ?? "zh",
      "readingMode": values["readingMode"] as? String ?? "learning",
      "generalDifficulty": values["generalDifficulty"] as? String ?? "intermediate",
      "automatic": values["automatic"] as? Bool ?? true
    ]
    if let history=CompanionLiveHistory.summary(in:values) {
      status["liveReadingHistory"]=history
      status["liveHistoryPageCount"]=history["pageCount"]
      status["lastDocumentUpdatedAt"]=values["lastDocumentUpdatedAt"] as? Double ?? 0
    }
    // A stopped reader also has a local last-page result. Returning it avoids
    // a redundant AI request when there is no newer accumulated live session.
    for key in ["lastHits","lastOptionsSignature","lastDetectedLanguage"] {
      if let value=values[key] {status[key]=value}
    }
    if values["readingMode"] as? String == "translation",
      values["lastTranslatedText"] as? String == values["lastText"] as? String,
      values["lastTranslationTarget"] as? String == (values["targetLanguage"] as? String ?? "zh"),
      (values["sourceLanguage"] as? String ?? "auto") == "auto" || values["sourceLanguage"] as? String == values["lastTranslationSource"] as? String,
      let raw=values["lastTranslationSegments"] as? String,let data=raw.data(using:.utf8),
      let parts=try? JSONSerialization.jsonObject(with:data) as? [[String:Any]],!parts.isEmpty {
      status["translationSegments"]=parts
      if parts.contains(where:{$0["translation"] is NSNull}) {status["translationError"]="尚有段落未完成，请重试。"}
    }
    return status
  }
}

/// A bounded local transcript of accepted screen results. This is separate from
/// the visible page model and the user's explicitly saved vocabulary book.
/// Plain JSON keeps existing App Group consumers and older app versions valid.
struct LiveReadingHistory {
  static let maximumPages=60
  static let maximumSourceCharacters=120000
  static let maximumBytes=2*1024*1024
  let sessionID:String
  let startedAt:Double
  private(set) var updatedAt:Double
  private(set) var pages:[[String:Any]]=[]
  private(set) var endedAt:Double?

  init(sessionID:String=UUID().uuidString,at:Double=Date().timeIntervalSince1970) {
    self.sessionID=sessionID;startedAt=at;updatedAt=at
  }
  init?(raw:String) {
    guard let data=raw.data(using:.utf8),data.count<=Self.maximumBytes,
      let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
      value["version"] as? Int==1,let id=value["sessionId"] as? String,
      let start=value["startedAt"] as? Double,let updated=value["updatedAt"] as? Double,
      let items=value["pages"] as? [[String:Any]],items.count<=Self.maximumPages,
      items.allSatisfy({$0["text"] is String && $0["optionsSignature"] is String && $0["id"] is String}) else {return nil}
    sessionID=id;startedAt=start;updatedAt=updated;pages=items;endedAt=value["endedAt"] as? Double
    guard pages.reduce(0,{$0+($1["text"] as? String ?? "").count})<=Self.maximumSourceCharacters else{return nil}
  }
  var json:[String:Any] {
    var value:[String:Any]=["version":1,"sessionId":sessionID,"startedAt":startedAt,"updatedAt":updatedAt,"pages":pages]
    if let endedAt {value["endedAt"]=endedAt};return value
  }
  var raw:String? {
    guard let data=try? JSONSerialization.data(withJSONObject:json),data.count<=Self.maximumBytes else{return nil}
    return String(data:data,encoding:.utf8)
  }
  mutating func finish(at:Double=Date().timeIntervalSince1970) {endedAt=at;updatedAt=max(updatedAt,at)}

  @discardableResult
  mutating func record(text:String,hits:[[String:Any]],parts:[[String:Any]],source:String,target:String,resolvedSource:String,resolvedTarget:String,mode:String,level:String,difficulty:String,resultsAreCurrent:Bool,pageKey:String?=nil,at:Double=Date().timeIntervalSince1970)->Bool {
    guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return false}
    let text=String(text.prefix(12000))
    let signature="\(source)|\(target)|\(level)|\(difficulty)\(mode == "translation" ? "|translation" : "")"
    let identity=Self.identity(signature+"|"+(pageKey ?? text.lowercased().filter{!$0.isWhitespace}))
    let old=pages.first{$0["id"] as? String==identity}
    let cleanHits=hits.prefix(48).filter{$0["word"] is String && $0["translation"] is String}
    let cleanParts=parts.prefix(120).filter{$0["source"] is String}
    var page:[String:Any]=["id":identity,"text":text,"optionsSignature":signature,"sourceLanguage":source,"targetLanguage":target,"resolvedSource":resolvedSource,"resolvedTarget":resolvedTarget,"readingMode":mode,"level":level,"generalDifficulty":difficulty,"updatedAt":at]
    // An in-flight new page may retain the previous visual card. It must never
    // be recorded as a result belonging to this source text.
    var retainedHits=old?["hits"] as? [[String:Any]] ?? []
    if resultsAreCurrent {
      for hit in cleanHits {
        retainedHits.removeAll{Self.wordIdentity($0)==Self.wordIdentity(hit)}
        retainedHits.append(hit)
      }
    }
    page["hits"]=retainedHits.map{Self.locatedHit($0,in:text)}
    if let pageKey {page["pageKey"]=pageKey}
    page["translationSegments"]=mode == "translation" ? Array(cleanParts) : []
    var candidate=pages.filter{$0["id"] as? String != identity};candidate.append(page)
    while candidate.count>1 {
      let characters=candidate.reduce(0,{$0+($1["text"] as? String ?? "").count})
      let bytes=(try? JSONSerialization.data(withJSONObject:candidate).count) ?? Int.max
      if candidate.count<=Self.maximumPages,characters<=Self.maximumSourceCharacters,bytes<=Self.maximumBytes-2048 {break}
      candidate.removeFirst()
    }
    guard let bytes=try? JSONSerialization.data(withJSONObject:candidate),bytes.count<=Self.maximumBytes-2048 else{return false}
    pages=candidate;updatedAt=at;return true
  }

  /// The latest direction/scope is shown together; all recorded page variants
  /// remain in the stored session, without mixing them into the live viewport.
  var summary:[String:Any]? {
    guard let last=pages.last,let signature=last["optionsSignature"] as? String else{return nil}
    let selected=pages.filter{$0["optionsSignature"] as? String==signature}
    var original="";var hits:[[String:Any]]=[];var parts:[[String:Any]]=[];var seen=Set<String>()
    for page in selected {
      let source=page["text"] as? String ?? ""
      if !original.isEmpty {original += "\n\n"}
      let offset=(original as NSString).length;original += source
      for var hit in page["hits"] as? [[String:Any]] ?? [] {
        let word=hit["word"] as? String ?? "";let key=Self.wordIdentity(hit)
        guard !word.isEmpty,seen.insert(key).inserted,hits.count<480 else{continue}
        if let start=hit["sourceStart"] as? Int,let end=hit["sourceEnd"] as? Int,start>=0,end>=start,end<=(source as NSString).length {
          hit["sourceStart"]=start+offset;hit["sourceEnd"]=end+offset
        } else {hit.removeValue(forKey:"sourceStart");hit.removeValue(forKey:"sourceEnd")}
        hits.append(hit)
      }
      for var part in page["translationSegments"] as? [[String:Any]] ?? [] {
        part["id"]="\(page["id"] as? String ?? "page"):\(part["id"] as? String ?? String(parts.count))";parts.append(part)
      }
    }
    var value:[String:Any]=["version":1,"sessionId":sessionID,"startedAt":startedAt,"updatedAt":updatedAt,"pageCount":selected.count,"retainedPageCount":pages.count,"text":original,"hits":hits,"translationSegments":parts,"optionsSignature":signature]
    for key in ["sourceLanguage","targetLanguage","resolvedSource","resolvedTarget","readingMode","level","generalDifficulty"] {value[key]=last[key]}
    return value
  }
  private static func identity(_ text:String)->String {
    var hash:UInt64=14695981039346656037
    for byte in text.utf8 {hash=(hash ^ UInt64(byte)) &* 1099511628211}
    return String(hash,radix:16)
  }
  private static func wordIdentity(_ hit:[String:Any])->String {
    let word=hit["word"] as? String ?? "";let from=hit["sourceLanguage"] as? String ?? "en";let to=hit["targetLanguage"] as? String ?? "zh"
    return from == "en" || to == "en" ? word : "\(from):\(to):\(word)"
  }
  private static func locatedHit(_ value:[String:Any],in text:String)->[String:Any] {
    var hit=value;let source=text as NSString;let surface=hit["surface"] as? String ?? hit["word"] as? String ?? ""
    guard !surface.isEmpty else{return hit}
    if let start=hit["sourceStart"] as? Int,let end=hit["sourceEnd"] as? Int,start>=0,end>=start,end<=source.length,
      source.substring(with:NSRange(location:start,length:end-start)).caseInsensitiveCompare(surface) == .orderedSame {return hit}
    hit.removeValue(forKey:"sourceStart");hit.removeValue(forKey:"sourceEnd")
    let context=hit["context"] as? String ?? ""
    var search=NSRange(location:0,length:source.length)
    if !context.isEmpty {
      let located=source.range(of:context,options:.caseInsensitive)
      if located.location != NSNotFound {search=located}
    }
    let found=source.range(of:surface,options:.caseInsensitive,range:search)
    guard found.location != NSNotFound else{return hit}
    let after=NSRange(location:NSMaxRange(found),length:NSMaxRange(search)-NSMaxRange(found))
    guard source.range(of:surface,options:.caseInsensitive,range:after).location==NSNotFound else{return hit}
    hit["sourceStart"]=found.location;hit["sourceEnd"]=NSMaxRange(found);return hit
  }
}

enum CompanionLiveHistory {
  static let key="liveReadingHistoryV1"
  private static var active:LiveReadingHistory?
  static func begin() {active=LiveReadingHistory()}
  static func record(text:String,hits:[[String:Any]],parts:[[String:Any]],source:String,target:String,resolvedSource:String,resolvedTarget:String,mode:String,level:String,difficulty:String,resultsAreCurrent:Bool,pageKey:String?=nil) {
    guard var history=active else{return}
    guard history.record(text:text,hits:hits,parts:parts,source:source,target:target,resolvedSource:resolvedSource,resolvedTarget:resolvedTarget,mode:mode,level:level,difficulty:difficulty,resultsAreCurrent:resultsAreCurrent,pageKey:pageKey) else{return}
    active=history
    if let raw=history.raw {CompanionStore.defaults.set(raw,forKey:key)}
  }
  static func finish() {
    if var history=active,!history.pages.isEmpty {history.finish();if let raw=history.raw {CompanionStore.defaults.set(raw,forKey:key)}}
    active=nil
  }
  static func summary(in values:[String:Any]?=nil)->[String:Any]? {
    guard let raw=(values ?? CompanionStore.defaults.snapshot())[key] as? String else{return nil}
    return LiveReadingHistory(raw:raw)?.summary
  }
}

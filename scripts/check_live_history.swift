import Foundation

@main
struct CheckLiveHistory {
  static func main() {
    var checks=0
    func check(_ value:@autoclosure()->Bool) {precondition(value());checks += 1}
    func hit(_ word:String,in text:String)->[String:Any] {
      let range=(text as NSString).range(of:word)
      return ["word":word,"surface":word,"translation":"测试释义","tags":["cet4"],"context":text,"sourceLanguage":"en","targetLanguage":"zh","sourceStart":range.location,"sourceEnd":NSMaxRange(range)]
    }
    @discardableResult
    func record(_ value:inout LiveReadingHistory,_ text:String,_ hits:[[String:Any]],key:String?=nil,parts:[[String:Any]]=[],mode:String="learning",current:Bool=true,at:Double=20)->Bool {
      value.record(text:text,hits:hits,parts:parts,source:"auto",target:"zh",resolvedSource:"en",resolvedTarget:"zh",mode:mode,level:"cet4",difficulty:"intermediate",resultsAreCurrent:current,pageKey:key,at:at)
    }
    var history=LiveReadingHistory(sessionID:"public-fixture",at:10)
    let first="📚 An essential argument.";let second="A reliable method."
    check(record(&history,first,[hit("essential",in:first)]))
    check(record(&history,second,[hit("reliable",in:second)],at:21))
    var summary=history.summary!
    check(summary["pageCount"] as? Int==2)
    check(summary["text"] as? String==first+"\n\n"+second)
    var hits=summary["hits"] as! [[String:Any]]
    check(hits.count==2)
    let globalStart=(first as NSString).length+2+(second as NSString).range(of:"reliable").location
    check(hits[1]["sourceStart"] as? Int==globalStart)
    check(record(&history,second,[hit("reliable",in:second)],at:22))
    check(history.pages.count==2)
    check((history.summary!["hits"] as! [[String:Any]]).count==2)
    history.finish(at:25)
    let decoded=LiveReadingHistory(raw:history.raw!)!
    check(decoded.sessionID==history.sessionID)
    check(decoded.endedAt==25)
    check(decoded.pages.count==2)
    check(LiveReadingHistory(raw:"broken")==nil)
    check(LiveReadingHistory(raw:"{\"version\":2}")==nil)

    var samePage=LiveReadingHistory()
    record(&samePage,first,[hit("essential",in:first)],key:"1:1")
    let revealed="Newly visible heading. "+first+" The reliable method follows."
    record(&samePage,revealed,[hit("reliable",in:revealed)],key:"1:1")
    check(samePage.pages.count==1)
    summary=samePage.summary!;hits=summary["hits"] as! [[String:Any]]
    check(hits.count==2)
    let old=hits.first{$0["word"] as? String=="essential"}!
    check(old["sourceStart"] as? Int==(revealed as NSString).range(of:"essential").location)
    record(&samePage,"An unseen new page.",[hit("essential",in:first)],key:"1:2",current:false)
    check((samePage.pages.last!["hits"] as! [[String:Any]]).isEmpty)
    check(samePage.pages.count==2)
    check((samePage.summary!["hits"] as! [[String:Any]]).count==2)

    var translation=LiveReadingHistory()
    record(&translation,first,[],key:"2:1",parts:[["id":"p0","source":first,"translation":NSNull()]],mode:"translation",current:false)
    record(&translation,first,[],key:"2:1",parts:[["id":"p0","source":first,"translation":"一个重要的论点。"]],mode:"translation")
    check(translation.pages.count==1)
    check((translation.summary!["translationSegments"] as! [[String:Any]]).first?["translation"] as? String=="一个重要的论点。")
    record(&translation,second,[],key:"2:2",parts:[["id":"p0","source":second,"translation":"可靠的方法。"]],mode:"translation")
    let parts=translation.summary!["translationSegments"] as! [[String:Any]]
    check(parts.count==2)
    check(parts[0]["id"] as? String != parts[1]["id"] as? String)
    record(&translation,first,[hit("essential",in:first)],key:"2:1",mode:"learning")
    check(translation.pages.count==3)
    check(translation.summary!["pageCount"] as? Int==1)
    check((translation.summary!["translationSegments"] as! [[String:Any]]).isEmpty)

    var bounded=LiveReadingHistory()
    for index in 0..<65 {record(&bounded,"Public page \(index).",[],key:"3:\(index)")}
    check(bounded.pages.count==60)
    check(bounded.pages.first?["text"] as? String=="Public page 5.")
    check((bounded.raw!.data(using:.utf8)!).count<=LiveReadingHistory.maximumBytes)
    var long=LiveReadingHistory()
    for index in 0..<30 {record(&long,String(repeating:"文",count:10000)+String(index),[],key:"4:\(index)")}
    check(long.pages.reduce(0,{$0+($1["text"] as! String).count})<=LiveReadingHistory.maximumSourceCharacters)
    check(!record(&long,"   ",[]))

    let manyLines=(0..<120).map{"第\($0)行正文包含需要学习的内容。"}.joined(separator:"\n")+"\n最后一行 substantial"
    let chunks=ReadingPassages.sourceChunks(manyLines)
    check(chunks.map{$0.text}.joined()==manyLines)
    check(chunks.last!.text.contains("substantial"))
    check(chunks.count<36)
    let unicode="e\u{301} 📚 👨‍👩‍👧‍👦 这是连续的原文。 reliable"
    let unicodeChunks=ReadingPassages.sourceChunks(unicode,maximumCharacters:4)
    check(unicodeChunks.map{$0.text}.joined()==unicode)
    for part in unicodeChunks {
      check((unicode as NSString).substring(with:NSRange(location:part.utf16Start,length:(part.text as NSString).length))==part.text)
    }
    let chinese="第一句话完整结束。第二句话继续说明。第三句话提供证据。第四句话说明结果。"
    check(ReadingPassages.make(chinese,sentencesPerPart:2,limit:240).count==2)
    check(ReadingPassages.make(chinese).count==2)
    print("\(checks) local history/source coverage checks passed")
  }
}

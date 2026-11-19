import Foundation

@main
struct CheckLivePreviewExcerpt {
  static func main() {
    let cases: [(String,String,Int)] = [
      (String(repeating:"A long sentence before the focus. ",count:20)+"Researchers MAINTAIN the original context.","maintain",130),
      (String(repeating:"阅读📖原文，",count:30)+"这里的关键术语是证据，后面继续解释。","证据",50),
      ("👩🏽‍🚀 Astronauts preserve the original context 🛰️.","preserve",35),
      ("  Researchers\n maintain\tconsistent practice.  ","maintain",50),
      ("Evidence is useful.","Evidence",0),
      ("This example ends with a distinction","distinction",12)
    ]
    for (context,surface,limit) in cases {
      let value=LivePreviewExcerpt.make(context:context,surface:surface,limit:limit)
      guard let highlight=value.highlight else{fatalError("Missing target: \(surface)")}
      let text=value.text as NSString
      precondition(NSMaxRange(highlight)<=text.length)
      precondition(text.substring(with:highlight).caseInsensitiveCompare(surface) == .orderedSame)
      precondition(!value.text.contains("\n") && !value.text.contains("\t"))
    }
    precondition(LivePreviewExcerpt.make(context:"",surface:"").text.isEmpty)
    precondition(LivePreviewExcerpt.make(context:"No matching surface",surface:"evidence").highlight == nil)
    precondition(LivePreviewExcerpt.make(context:"Plain original text",surface:"").highlight == nil)
    let source="A title.\nResearchers maintain\nthat consistent practice is more effective\nthan occasional effort.\nThe next sentence."
    let range=(source as NSString).range(of:"maintain")
    let sentence=LivePreviewExcerpt.sentence(source:source,surface:"maintain",range:range)
    precondition(sentence=="Researchers maintain\nthat consistent practice is more effective\nthan occasional effort.")
    precondition(LivePreviewExcerpt.sentence(source:"👩🏽‍🚀 这是原句。这里有证据，继续说明。下一句。",surface:"证据",range:nil)=="这里有证据，继续说明。")
    precondition(LivePreviewExcerpt.sentence(source:source,surface:"missing",range:NSRange(location:99999,length:4)) == nil)
    print("12 excerpt checks passed: target retention, Unicode, clipping and sentence reconstruction")
  }
}

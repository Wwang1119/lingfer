// Compile for iOS Simulator and run via simctl; uses the production UIKit pagination.
import Foundation
import UIKit
@main struct CheckIslandPages {
 static func main() {
  let samples=[String(repeating:"完整的语境译文保留每一句话，不因界面空间丢失内容。",count:12),String(repeating:"Complete sentences preserve context and the reader’s place. ",count:20),String(repeating:"🧑🏽‍🚀 café 科学，العربية，हिन्दी。\n",count:20)]
  var checked=0
  for text in samples {for size:CGFloat in [16,17,20,23] {
   let lines=size>19 ? 2 : 3
   let pages=ReadingActivityText.pages(text,size:size,lines:lines)
   precondition(pages.count>1 && pages.joined()==text)
   let font=UIFont.systemFont(ofSize:size)
   for page in pages {precondition(ReadingActivityText.height(page,font:font)<=ceil(font.lineHeight)*CGFloat(lines)+1);checked += 1}
  }}
  for text in [String(repeating:"W",count:48),String(repeating:"复杂语境",count:12),"electroencephalographically"] {
   let pages=ReadingActivityText.pages(text,size:19,lines:2,weight:.semibold)
   precondition(pages.joined()==text)
   let font=UIFont.systemFont(ofSize:19,weight:.semibold)
   for page in pages {precondition(ReadingActivityText.height(page,font:font)<=ceil(font.lineHeight)*2+1)}
  }
  let legacy="{\"paused\":false,\"mode\":\"learning\",\"count\":1,\"terms\":[],\"source\":\"\",\"translation\":\"\",\"status\":\"等待\",\"updatedAt\":0}"
  let old=try! JSONDecoder().decode(ReadingActivityAttributes.ContentState.self,from:Data(legacy.utf8))
  precondition(old.typeCategory==nil && old.detailTotal==nil && old.originalTerm==nil)
  let sample=ReadingActivityAttributes.ContentState.preview(paused:false,mode:"translation",count:12,terms:[(String(repeating:"📖",count:80),String(repeating:"📖",count:200))],source:String(repeating:"📖",count:150),translation:String(repeating:"📖",count:300),status:String(repeating:"📖",count:80),position:11,total:12,detailPosition:3,detailTotal:8,presentation:"island",typeCategory:UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,originalTerm:String(repeating:"📖",count:80))
  let bytes=try! JSONEncoder().encode(sample)
  precondition(bytes.count<4096)
  print("Real UIKit typography pagination verified:",checked,"pages; full Unicode text preserved; legacy state decoded; bounded payload bytes:",bytes.count)
 }
}

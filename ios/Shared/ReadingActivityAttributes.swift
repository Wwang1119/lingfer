import ActivityKit
import Foundation
import UIKit

@available(iOS 16.2, *)
struct ReadingActivityAttributes: ActivityAttributes {
  struct Term: Codable, Hashable {
    let source: String
    let meaning: String
  }
  struct ContentState: Codable, Hashable {
    let paused: Bool
    let mode: String
    let count: Int
    let terms: [Term]
    let source: String
    let translation: String
    let status: String
    var position: Int? = nil
    var total: Int? = nil
    var detailPosition:Int? = nil
    var detailTotal:Int? = nil
    var presentation:String? = nil
    var typeCategory:String? = nil
    var originalTerm:String? = nil
    let updatedAt: Date
  }
  let startedAt: Date
}

/// Keep the island payload comfortably below ActivityKit's 4 KB limit.
/// The activity never receives screen images, full documents or credentials.
@available(iOS 16.2, *)
extension ReadingActivityAttributes.ContentState {
  static func preview(paused: Bool, mode: String, count: Int,
                      terms: [(String, String)], source: String = "",
                      translation: String = "", status: String,position:Int = 0,total:Int? = nil,
                      detailPosition:Int = 0,detailTotal:Int = 1,presentation:String = "floating",typeCategory:String = UIContentSizeCategory.large.rawValue,originalTerm:String? = nil) -> Self {
    Self(paused: paused, mode: mode, count: count,
         terms: terms.prefix(1).map { .init(source: String($0.0.prefix(64)), meaning: String($0.1.prefix(150))) },
         source: String(source.prefix(110)), translation: String(translation.prefix(240)),
         status: String(status.prefix(60)),position:position,total:total ?? count,
         detailPosition:detailPosition,detailTotal:detailTotal,presentation:presentation,typeCategory:typeCategory,originalTerm:originalTerm.map{String($0.prefix(64))},updatedAt: Date())
  }
}

/// The sender and extension must use the SAME text budget. Background UIKit
/// and WidgetKit can have different current traits during a Settings change.
struct ReadingActivityTypography {
  let bodySize:CGFloat
  let translationSize:CGFloat
  private let normalWordSize:CGFloat
  init(category:String?) {
    let trait=UITraitCollection(preferredContentSizeCategory:UIContentSizeCategory(rawValue:category ?? UIContentSizeCategory.large.rawValue))
    bodySize=min(20,UIFontMetrics(forTextStyle:.body).scaledValue(for:16,compatibleWith:trait))
    translationSize=min(23,UIFontMetrics(forTextStyle:.body).scaledValue(for:17,compatibleWith:trait))
    normalWordSize=min(26,UIFontMetrics(forTextStyle:.title3).scaledValue(for:22,compatibleWith:trait))
  }
  var translationLines:Int {translationSize>19 ? 2 : 3}
  func longWord(_ text:String)->Bool {ReadingActivityText.height(text,font:.systemFont(ofSize:normalWordSize,weight:.semibold))>32}
  func wordSize(_ text:String)->CGFloat {longWord(text) ? 19 : normalWordSize}
  func meaningSize(_ text:String)->CGFloat {longWord(text) ? 16 : bodySize}
  func meaningLines(_ text:String)->Int {longWord(text) || bodySize>18 ? 1 : 2}
}

/// Use the narrow expanded-island content width to paginate before publishing.
/// Each page is measured, so the widget never needs to clip a returned meaning.
enum ReadingActivityText {
  static let width:CGFloat=288
  static func height(_ text:String,font:UIFont)->CGFloat {
    (text as NSString).boundingRect(with:CGSize(width:width,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font],context:nil).height
  }
  static func pages(_ text:String,size:CGFloat,lines:Int,weight:UIFont.Weight = .regular)->[String] {
    guard !text.isEmpty else{return []}
    let font=UIFont.systemFont(ofSize:size,weight:weight)
    let ceiling=ceil(font.lineHeight)*CGFloat(lines)+1
    var result:[String]=[];var start=text.startIndex
    while start<text.endIndex {
      var low=text.index(after:start);var high=text.endIndex;var best=low
      while low<=high {
        let distance=text.distance(from:low,to:high)
        let mid=text.index(low,offsetBy:distance/2)
        if height(String(text[start..<mid]),font:font)<=ceiling {
          best=mid
          if mid==text.endIndex {break}
          low=text.index(after:mid)
        } else {
          if mid==low {break}
          high=text.index(before:mid)
        }
      }
      // Prefer a nearby complete sentence or word, but never discard characters.
      let value=text[start..<best]
      if best<text.endIndex,let boundary=value.lastIndex(where:{$0.isWhitespace || ".!?;。！？；".contains($0)}),
        text.distance(from:start,to:boundary)>text.distance(from:start,to:best)/2 {best=text.index(after:boundary)}
      result.append(String(text[start..<best]));start=best
    }
    return result
  }
}

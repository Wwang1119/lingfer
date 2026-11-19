import Foundation
import CoreGraphics

enum LiveReadingPresentation:String,CaseIterable {
  case island, floating
  var title:String {self == .island ? "灵动岛" : "浮窗"}
  // These are alternative presentation modes. Do not launch a second remote
  // vocabulary request for an island the screen-sharing indicator can hide.
  func separatesVocabulary(readingMode:String)->Bool {false}
}

struct LiveVocabularyRequestKey:Equatable {
  let text:String
  let source:String
  let target:String
  let level:String
  let difficulty:String
}

/// A finite PiP timeline for a sequence of reading cards. One guard slot on
/// either side leaves room for AVKit's skip interval and preserves cyclic
/// previous/next navigation. The clock stays still until the cursor changes.
struct LivePreviewPlayback:Equatable {
  static let slotSeconds:Double = 30
  let count:Int
  let position:Int
  init(count:Int,position:Int) {
    self.count=max(0,count)
    self.position=min(max(0,position),max(0,count-1))
  }
  var timeSeconds:Double {Double(position+1)*Self.slotSeconds}
  var durationSeconds:Double {Double(max(1,count)+1)*Self.slotSeconds}
  var canSkip:Bool {count>1}
}

/// Returning inline is a temporary AVKit transition, not the reader dismissing
/// the window. Keep that distinction independent of controller callbacks.
struct LivePresentationPolicy {
  var mode:LiveReadingPresentation = .floating
  private(set) var hidden=false
  private(set) var restoringInline=false
  var wantsFloating:Bool {mode == .floating && !hidden}
  mutating func select(_ mode:LiveReadingPresentation) {self.mode=mode;hidden=false;restoringInline=false}
  mutating func restoreInline() {restoringInline=true}
  mutating func didStop(inForeground:Bool) {
    if mode == .floating,!restoringInline,!inForeground {hidden=true}
    restoringInline=false
  }
}

struct LiveViewportLine {
  let text:String
  let rect:CGRect
  var key:String {Self.key(text)}
  static func key(_ text:String)->String {
    text.lowercased().unicodeScalars.filter{CharacterSet.alphanumerics.contains($0)}.map(String.init).joined()
  }
}

/// Conservative, local chrome removal. A short word in the article body is
/// never removed merely because a navigation button can have the same name.
enum LiveReadingContent {
  static func hasReadingBody(_ lines:[LiveViewportLine])->Bool {
    let text=lines.filter{!isChrome($0) && $0.key.count>=6 && $0.rect.width>0.25}
    guard text.reduce(0,{$0+$1.key.count})>=60 else{return false}
    if text.contains(where:{$0.key.count>=100}) {return true}
    let ordered=text.sorted{$0.rect.midY>$1.rect.midY}
    return zip(ordered,ordered.dropFirst()).contains { a,b in
      let overlap=max(0,min(a.rect.maxX,b.rect.maxX)-max(a.rect.minX,b.rect.minX))
      return abs(a.rect.midY-b.rect.midY)<max(a.rect.height,b.rect.height)*3.5 && overlap>0.2
    }
  }
  static func isChrome(_ line:LiveViewportLine)->Bool {
    let text=line.text.trimmingCharacters(in:.whitespacesAndNewlines)
    let edge=line.rect.midY>0.87 || line.rect.midY<0.14
    guard edge else{return false}
    // Status icons can be OCR'd as mixed characters (for example "55+ 1X1à")
    // rather than a clean percentage. Restrict this exclusion to the small
    // upper-right status cluster, leaving full-width chapter headings intact.
    if line.rect.minY>0.945,line.rect.height<0.035,line.rect.minX>0.65,text.count<20 {return true}
    if line.rect.midY>0.92,
       text.range(of:"^\\d{1,2}:\\d{2}$|^\\d{1,3}\\s*%?$",options:.regularExpression) != nil {return true}
    let controls:Set<String>=["返回","关闭","更多","微信","阅读原文","写留言","写评论","评论","点赞","在看","收藏","分享","上一章","下一章","目录","设置","加入书架","Aa","AA","aA","Back","Done","Share"]
    if controls.contains(text) {return true}
    if text.count<40 {
      var key=LiveViewportLine.key(text);var count=0
      let labels=controls.map(LiveViewportLine.key).sorted{$0.count>$1.count}
      while let next=labels.first(where:{!$0.isEmpty && key.hasPrefix($0)}) {
        key=String(key.dropFirst(next.count));count += 1
      }
      if key.isEmpty,count>=2 {return true}
    }
    if line.rect.midY<0.14,text.count<120,
       text.range(of:"^(https?://)?[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+(/\\S*)?$",options:.regularExpression) != nil {return true}
    return false
  }
  static func visible(_ lines:[LiveViewportLine],excluding masks:[CGRect])->[LiveViewportLine] {
    lines.filter { line in
      !isChrome(line) && !masks.contains{mask in line.rect.intersects(mask)}
    }
  }
  static func addedCharacters(from old:String,to new:String)->Int {
    let projection=LiveSourceProjection(old)
    return new.components(separatedBy:"\n").filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && projection.range(of:$0)==nil}.reduce(0){$0+LiveViewportLine.key($1).count}
  }
}

struct LiveViewportSnapshot {
  let text:String
  let lines:[(NSRange,CGRect)]
  let changed:Bool
  let settled:Bool
  let page:Int
  let movement:CGFloat
}

/// Measure displacement from the last selected source geometry, never the
/// accumulated distance of frame-to-frame OCR jitter. Source ranges are the
/// stable identities; a missing/ambiguous anchor is not proof of scrolling.
struct LiveSelectionAnchorTracker {
  private var baseline:[NSRange:CGFloat]=[:]

  mutating func pin(_ positions:[(NSRange,CGRect)]) {
    baseline=Self.anchors(in:positions)
  }

  mutating func reset() {baseline.removeAll()}

  func netMovement(in positions:[(NSRange,CGRect)])->CGFloat? {
    guard baseline.count>=2 else{return nil}
    let current=Self.anchors(in:positions)
    let deltas=current.compactMap {range,y in baseline[range].map{y-$0}}.sorted()
    guard deltas.count>=2 else{return nil}
    let center=Self.median(deltas)
    let coherent=deltas.filter{abs($0-center)<=0.015}
    guard coherent.count*4>=deltas.count*3 else{return nil}
    return Self.median(coherent)
  }

  private static func median(_ sorted:[CGFloat])->CGFloat {
    let middle=sorted.count/2
    return sorted.count.isMultiple(of:2) ? (sorted[middle-1]+sorted[middle])/2 : sorted[middle]
  }

  private static func anchors(in positions:[(NSRange,CGRect)])->[NSRange:CGFloat] {
    var result:[NSRange:CGFloat]=[:],duplicates=Set<NSRange>()
    for (range,rect) in positions {
      guard range.location>=0,range.location != NSNotFound,range.length>=12,
        rect.width>0,rect.height>0,rect.midY.isFinite else{continue}
      if result.updateValue(rect.midY,forKey:range) != nil {duplicates.insert(range)}
    }
    for range in duplicates {result.removeValue(forKey:range)}
    return result
  }
}

/// Map a reflowed OCR line back to the unchanged source without submitting it
/// for translation again. Offsets always refer to the original UTF-16 text.
struct LiveSourceProjection {
  private var normalized=""
  private var ranges:[NSRange]=[]
  init(_ source:String) {
    var offset=0
    for character in source {
      let value=String(character);let range=NSRange(location:offset,length:(value as NSString).length)
      let key=LiveViewportLine.key(value)
      normalized += key;ranges += Array(repeating:range,count:(key as NSString).length)
      offset += range.length
    }
  }
  func range(of line:String)->NSRange? {
    let key=LiveViewportLine.key(line);guard !key.isEmpty else{return nil}
    let match=(normalized as NSString).range(of:key)
    guard match.location != NSNotFound,NSMaxRange(match)<=ranges.count else{return nil}
    let first=ranges[match.location],last=ranges[NSMaxRange(match)-1]
    return NSRange(location:first.location,length:NSMaxRange(last)-first.location)
  }
}

/// Stable source text and current geometry are separate: a short scroll updates
/// positions immediately without cancelling translation or clearing word cards.
struct LiveReadingViewport {
  static func hasSelectionToolbar(_ lines:[LiveViewportLine])->Bool {
    let actions=["拷贝","复制","查询","翻译","查找","搜索网页","copy","lookup","translate","find","searchweb"]
    if lines.contains(where:{line in
      guard line.text.count<70,line.rect.height<0.05 else{return false}
      var remaining=line.key;var count=0
      while !remaining.isEmpty {
        guard let action=actions.sorted(by:{$0.count>$1.count}).first(where:{remaining.hasPrefix($0)}) else{return false}
        remaining=String(remaining.dropFirst(action.count));count += 1
      }
      return count>=3
    }) {return true}
    let buttons=lines.filter{actions.contains($0.key) && $0.rect.height<0.05}
    return buttons.count>=3 && (buttons.map{$0.rect.midY}.max() ?? 1)-(buttons.map{$0.rect.midY}.min() ?? 0)<0.035
  }
  private var document:[String]=[]
  private var pending=""
  private var pendingCount=0
  private var page=0
  private var previousLocations:[String:CGFloat]=[:]

  mutating func update(_ incoming:[LiveViewportLine])->LiveViewportSnapshot {
    let visible=incoming.filter{!$0.key.isEmpty}
    let keys=document.map(LiveViewportLine.key)
    var matches:[Int:Int]=[:]
    var used=Set<Int>()
    for (i,line) in visible.enumerated() {
      if let j=keys.indices.first(where:{!used.contains($0) && keys[$0]==line.key}) {matches[i]=j;used.insert(j)}
    }
    let strong=matches.keys.filter{visible[$0].key.count>=12 && visible[$0].rect.midY>0.12 && visible[$0].rect.midY<0.90}
    let overlaps=(strong.count>=2 && Double(strong.count)/Double(max(1,visible.count))>=0.25) || (visible.count<=4 && strong.contains{visible[$0].key.count>=60})
    var candidate=document
    var newPage=false
    if document.isEmpty || !overlaps {candidate=visible.map{$0.text};newPage = !document.isEmpty}
    else if let first=matches.keys.min(),let last=matches.keys.max(),let firstOld=matches[first],let lastOld=matches[last] {
      let prefix=visible.prefix(first).filter{line in !keys.contains(where:{$0.hasPrefix(line.key) || $0.hasSuffix(line.key)})}.map{$0.text}
      let suffix=visible.dropFirst(last+1).filter{line in !keys.contains(where:{$0.hasPrefix(line.key) || $0.hasSuffix(line.key)})}.map{$0.text}
      let prepended=firstOld==0 ? prefix.count : 0
      if firstOld==0 {candidate=prefix+candidate}
      if lastOld==document.count-1 {candidate += suffix}
      // A moved floating window can reveal lines BETWEEN two known anchors.
      // Keep them too: prefix/suffix-only stitching permanently lost these
      // newly exposed lines even after they became plainly visible.
      let ordered=matches.keys.sorted()
      var insertions:[(Int,[String])]=[]
      for pair in zip(ordered,ordered.dropFirst()) {
        guard let a=matches[pair.0],let b=matches[pair.1],b==a+1,pair.1>pair.0+1 else{continue}
        let fresh=visible[(pair.0+1)..<pair.1].filter{line in
          !keys.contains(where:{$0==line.key || $0.hasPrefix(line.key) || $0.hasSuffix(line.key)})
        }.map{$0.text}
        if !fresh.isEmpty {insertions.append((b+prepended,fresh))}
      }
      for (index,lines) in insertions.sorted(by:{$0.0>$1.0}) {
        candidate.insert(contentsOf:lines,at:min(index,candidate.count))
      }
      // Retain a small reading margin, rather than accumulating an entire book.
      let start=max(0,firstOld+prepended-4)
      let end=min(candidate.count,lastOld+prepended+5+suffix.count+insertions.reduce(0){$0+$1.1.count})
      if start>8 || candidate.count>90 {candidate=Array(candidate[start..<max(start,end)])}
      for pair in zip(ordered,ordered.dropFirst()) {
        guard let a=matches[pair.0],let b=matches[pair.1],pair.1-pair.0>=3,b-a>=3 else{continue}
        let fresh=visible[(pair.0+1)..<pair.1].map{$0.key}.joined()
        let old=keys[(a+1)..<b].joined()
        func grams(_ value:String)->Set<String> {let c=Array(value);return Set(zip(c,c.dropFirst()).map{String($0.0)+String($0.1)})}
        let left=grams(fresh),right=grams(old)
        if fresh.count>40,!left.isEmpty,Double(left.intersection(right).count)/Double(max(1,left.union(right).count))<0.4 {
          candidate=visible.map{$0.text};newPage=true;break
        }
      }
    }
    let identity=candidate.map(LiveViewportLine.key).joined(separator:"|")
    if identity==pending {pendingCount += 1} else {pending=identity;pendingCount=1}
    let settled=document.isEmpty || candidate==document || pendingCount>=2
    var changed=false
    if settled,!candidate.isEmpty,candidate != document {
      document=candidate;changed=true
      if page==0 || newPage {page += 1}
    }
    let canonical=document.map(LiveViewportLine.key)
    var offsets:[Int]=[];var offset=0
    for line in document {offsets.append(offset);offset += (line as NSString).length+1}
    var located:[(NSRange,CGRect)]=[];var deltas:[CGFloat]=[];var positions:[String:CGFloat]=[:]
    for line in visible {
      if let i=canonical.firstIndex(of:line.key) {
        located.append((NSRange(location:offsets[i],length:(document[i] as NSString).length),line.rect))
        if let old=previousLocations[line.key] {deltas.append(line.rect.midY-old)}
        positions[line.key]=line.rect.midY
      }
    }
    previousLocations=positions
    let movement=deltas.sorted().dropFirst(deltas.count/2).first ?? 0
    return LiveViewportSnapshot(text:document.joined(separator:"\n"),lines:located,changed:changed,settled:settled,page:page,movement:movement)
  }
}

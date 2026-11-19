import Foundation

@main
struct CheckLiveReadingStability {
  static func main() {
    var checks=0
    func check(_ value:@autoclosure ()->Bool,file:StaticString=#file,line:UInt=#line) {
      checks += 1
      precondition(value(),file:file,line:line)
    }
    func lines(_ values:[String],shift:CGFloat = 0)->[LiveViewportLine] {
      values.enumerated().map {LiveViewportLine(text:$0.element,rect:CGRect(x:0.1,y:0.84-CGFloat($0.offset)*0.10+shift,width:0.8,height:0.035))}
    }
    let source=["Researchers maintain the original context.","Consistent practice is more effective.","An innovative approach transforms reading.","Evidence reveals an essential distinction.","A reliable method preserves understanding."]
    var viewport=LiveReadingViewport()
    let first=viewport.update(lines(source));check(first.changed && first.settled)
    let small=viewport.update(lines(source,shift:0.02));check(!small.changed && small.text==first.text && small.page==first.page)
    check(abs(small.movement-0.02)<0.001)
    var noisy=source;noisy[2]="An innovative approach transf0rms reading."
    let jitter=viewport.update(lines(noisy));check(!jitter.changed && jitter.text==first.text)
    let transient=viewport.update(lines(["A temporary menu with unrelated text","Open settings and other choices"]));check(!transient.changed && !transient.settled)
    check(!viewport.update(lines(source)).changed)
    let extended=source+["Consider the argument before a conclusion.","Preserve complete sentences when translating."]
    check(!viewport.update(lines(extended)).changed)
    let committed=viewport.update(lines(extended));check(committed.changed && committed.page==first.page)
    check(!viewport.update(lines(extended,shift:0.015)).changed)
    let replacement=["A different article begins here.","Completely new evidence is available.","The method has changed substantially.","Read this separate argument carefully."]
    check(!viewport.update(lines(replacement)).changed)
    let next=viewport.update(lines(replacement));check(next.changed && next.page != first.page)
    let wrapped="Researchers maintain\nthat consistent practice is effective.\nAn innovative approach improves reading.\nEvidence supports this conclusion."
    let parts=ReadingPassages.make(wrapped)
    check(parts.count==1 && parts[0].contains("maintain that") && parts[0].contains("Evidence supports"))
    check(ReadingPassages.make("第一句话完整结束。\n第二句话继续说明。\n第三句话提供证据。").count==1)
    check(ReadingPassages.make("First paragraph.\n\nSecond paragraph.").count==2)
    let long=String(repeating:"原句📖和完整译文。 Complete translated sentences. ",count:25)
    let pages=ReadingPassages.chunks(long)
    check(pages.count>3 && pages.joined()==long)
    let excerpt=LivePreviewExcerpt.make(context:String(repeating:"A long prefix ",count:25)+"essential argument follows.",surface:"essential",limit:75)
    check(excerpt.highlight != nil && excerpt.text.contains("essential"))
    let menu=LiveViewportLine(text:"拷贝 查询 翻译 查找 搜索网页",rect:CGRect(x:0.1,y:0.5,width:0.8,height:0.025))
    check(LiveReadingViewport.hasSelectionToolbar([menu]))
    check(!LiveReadingViewport.hasSelectionToolbar([LiveViewportLine(text:"我们需要拷贝资料并查询和翻译相关文字",rect:menu.rect)]))
    check(LiveReadingViewport.hasSelectionToolbar(["Copy","Look Up","Translate"].enumerated().map{LiveViewportLine(text:$0.element,rect:CGRect(x:CGFloat($0.offset)*0.2,y:0.5,width:0.18,height:0.025))}))
    let reflowed="Researchers\n maintain the original context. 📖 这是证据。"
    let projection=LiveSourceProjection(reflowed)
    let located=projection.range(of:"Researchers maintain")!
    check((reflowed as NSString).substring(with:located)=="Researchers\n maintain")
    check((reflowed as NSString).substring(with:projection.range(of:"这是证据")!)=="这是证据")
    check(projection.range(of:"unrelated words")==nil)
    var edited=LiveReadingViewport()
    let common=["A shared long introductory line.","Old content discusses an innovative argument.","Previous observations support this method.","An unchanged final sentence remains here."]
    _=edited.update(lines(common))
    let edit=[common[0],"Completely different findings replace the argument.","New experiments require another interpretation.",common[3]]
    _=edited.update(lines(edit));check(edited.update(lines(edit)).changed)
    var display=LivePresentationPolicy()
    check(display.wantsFloating)
    display.restoreInline();display.didStop(inForeground:false)
    check(display.wantsFloating && !display.hidden)
    display.didStop(inForeground:true);check(display.wantsFloating)
    display.didStop(inForeground:false);check(display.hidden && !display.wantsFloating)
    display.select(.floating);check(display.wantsFloating)
    display.select(.island);display.didStop(inForeground:false);check(!display.wantsFloating && !display.hidden)
    check(!LiveReadingPresentation.floating.separatesVocabulary(readingMode:"translation"))
    check(!LiveReadingPresentation.island.separatesVocabulary(readingMode:"translation"))
    check(!LiveReadingPresentation.floating.separatesVocabulary(readingMode:"learning"))
    let empty=LivePreviewPlayback(count:0,position:8)
    check(empty.position==0 && !empty.canSkip)
    check(empty.timeSeconds>0 && empty.timeSeconds<empty.durationSeconds)
    let single=LivePreviewPlayback(count:1,position:0)
    check(!single.canSkip && single.position==0)
    let firstCard=LivePreviewPlayback(count:4,position:0)
    check(firstCard.canSkip && firstCard.timeSeconds-15>=0)
    let lastCard=LivePreviewPlayback(count:4,position:3)
    check(lastCard.timeSeconds+15<lastCard.durationSeconds)
    check(LivePreviewPlayback(count:4,position:2).timeSeconds-lastCard.timeSeconds == -LivePreviewPlayback.slotSeconds)
    check(LivePreviewPlayback(count:2,position:3).position==1)
    check(LivePreviewPlayback(count:-1,position:-1)==LivePreviewPlayback(count:0,position:0))
    check(LiveReadingPresentation.floating.title=="浮窗" && LiveReadingPresentation.island.title=="灵动岛")
    let outside=LiveViewportLine(text:"A complete visible column beside the floating window.",rect:CGRect(x:0.7,y:0.5,width:0.28,height:0.04))
    let inside=LiveViewportLine(text:"The floating video's own translation",rect:CGRect(x:0.1,y:0.5,width:0.4,height:0.04))
    let mask=CGRect(x:0.05,y:0.4,width:0.55,height:0.3)
    check(LiveReadingContent.visible([outside,inside],excluding:[mask]).map{$0.text}==[outside.text])
    check(LiveReadingContent.isChrome(LiveViewportLine(text:"9:41",rect:CGRect(x:0.1,y:0.96,width:0.1,height:0.02))))
    check(LiveReadingContent.isChrome(LiveViewportLine(text:"55+ 1X1à",rect:CGRect(x:0.72,y:0.96,width:0.23,height:0.02))))
    check(!LiveReadingContent.isChrome(LiveViewportLine(text:"Chapter I",rect:CGRect(x:0.1,y:0.95,width:0.8,height:0.04))))
    check(LiveReadingContent.isChrome(LiveViewportLine(text:"阅读原文",rect:CGRect(x:0.1,y:0.07,width:0.2,height:0.02))))
    check(!LiveReadingContent.isChrome(LiveViewportLine(text:"返回",rect:CGRect(x:0.1,y:0.5,width:0.2,height:0.03))))
    check(!LiveReadingContent.isChrome(LiveViewportLine(text:"第一章 重新认识世界",rect:CGRect(x:0.1,y:0.89,width:0.8,height:0.04))))
    var hiddenMiddle=LiveReadingViewport()
    let anchors=["A long first source anchor remains visible.","A long final source anchor also remains visible."]
    _=hiddenMiddle.update(lines(anchors))
    let uncovered=[anchors[0],"Previously hidden evidence becomes visible after moving the window.",anchors[1]]
    _=hiddenMiddle.update(lines(uncovered))
    let recovered=hiddenMiddle.update(lines(uncovered))
    check(recovered.text.contains(uncovered[1]) && recovered.page==1)
    check(LiveReadingContent.addedCharacters(from:anchors.joined(separator:"\n"),to:uncovered.joined(separator:"\n"))>12)
    check(LiveReadingContent.addedCharacters(from:"Researchers\n maintain the original context.",to:"Researchers maintain the original context.")==0)
    let unicode="阅读📖原文和译文。 Complete sentences stay paired. "+String(repeating:"More evidence. ",count:12)
    let measured=LivePreviewPagination.chunks(unicode){$0.count<=42}
    check(measured.joined()==unicode && measured.allSatisfy{$0.count<=42})
    check(LivePreviewPagination.chunks(""){_ in true}.isEmpty)
    check(LivePreviewPagination.chunks("👩🏽‍🚀"){_ in false}==["👩🏽‍🚀"])
    check(LiveReadingContent.hasReadingBody(lines(source)))
    check(!LiveReadingContent.hasReadingBody(["Calendar","Camera","Photos","Settings"].enumerated().map{LiveViewportLine(text:$0.element,rect:CGRect(x:CGFloat($0.offset)*0.2,y:0.7,width:0.18,height:0.03))}))
    check(LiveReadingContent.isChrome(LiveViewportLine(text:"返回 微信 更多",rect:CGRect(x:0.1,y:0.93,width:0.8,height:0.025))))
    var shiftedMiddle=LiveReadingViewport()
    let stable=(0..<6).map{"A distinctive unchanged anchor number \($0) provides sufficient source context."}
    _=shiftedMiddle.update(lines(stable))
    let revealed=["A cropped prefix outside the retained document.",stable[2],"New middle evidence must occur before anchor three.",stable[3],stable[4]]
    _=shiftedMiddle.update(lines(revealed));let retained=shiftedMiddle.update(lines(revealed))
    check(retained.text.contains(stable[2]+"\n"+revealed[2]+"\n"+stable[3]))
    func anchorPositions(_ shifts:[CGFloat])->[(NSRange,CGRect)] {
      shifts.enumerated().map{(NSRange(location:$0.offset*60,length:36),CGRect(x:0.1,y:0.80-CGFloat($0.offset)*0.10+$0.element,width:0.8,height:0.035))}
    }
    var selection=LiveSelectionAnchorTracker()
    let pinned=anchorPositions([0,0,0,0])
    check(selection.netMovement(in:pinned)==nil)
    selection.pin(pinned)
    check(abs(selection.netMovement(in:pinned)!)<0.000001)
    var jitterSelection=LiveSelectionAnchorTracker()
    jitterSelection.pin(anchorPositions([0,0]))
    var stableForEveryFrame=true
    for frame in 0..<80 {
      let epsilon:CGFloat=frame.isMultiple(of:2) ? 0.002 : -0.002
      let movement=jitterSelection.netMovement(in:anchorPositions([epsilon,-epsilon]))
      stableForEveryFrame = stableForEveryFrame && movement != nil && abs(movement!)<0.0021
    }
    check(stableForEveryFrame)
    check(abs(selection.netMovement(in:anchorPositions([0.12,0.12,0.12,0.12]))!-0.12)<0.000001)
    check(abs(selection.netMovement(in:anchorPositions([0.03,0.03,0.03,0.03]))!-0.03)<0.000001)
    check(abs(selection.netMovement(in:anchorPositions([-0.13,-0.13,-0.13,-0.13]))!+0.13)<0.000001)
    check(selection.netMovement(in:Array(pinned.prefix(1)))==nil)
    check(selection.netMovement(in:[])==nil)
    check(abs(selection.netMovement(in:anchorPositions([0.12,0.12,0.12,0.40]))!-0.12)<0.000001)
    check(selection.netMovement(in:anchorPositions([0.14,0.14,-0.14,-0.14]))==nil)
    check(selection.netMovement(in:anchorPositions([0.12,0.12,0.40]))==nil)
    let unrelated=pinned.map{(NSRange(location:$0.0.location+1,length:$0.0.length),$0.1)}
    check(selection.netMovement(in:unrelated)==nil)
    var shortSelection=LiveSelectionAnchorTracker()
    shortSelection.pin([(NSRange(location:0,length:11),pinned[0].1),pinned[1]])
    check(shortSelection.netMovement(in:pinned)==nil)
    var ambiguousSelection=LiveSelectionAnchorTracker()
    ambiguousSelection.pin([pinned[0],pinned[0]])
    check(ambiguousSelection.netMovement(in:pinned)==nil)
    selection.pin(anchorPositions([0.20,0.20,0.20,0.20]))
    check(abs(selection.netMovement(in:anchorPositions([0.23,0.23,0.23,0.23]))!-0.03)<0.000001)
    selection.reset()
    check(selection.netMovement(in:pinned)==nil)
    jitterSelection.pin(anchorPositions([0,0]))
    check(abs(jitterSelection.netMovement(in:anchorPositions([0.11,0.13]))!-0.12)<0.000001)
    print("\(checks) stability checks passed: full-frame filtering, occlusion recovery, paired pagination, fixed selection anchors, viewport and PiP navigation")
  }
}

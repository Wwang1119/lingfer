import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct LingferActivityBundle: WidgetBundle {
  var body: some Widget { ReadingActivityWidget() }
}

struct ReadingActivityWidget: Widget {
  private let accent=Color(red:54/255,green:95/255,blue:112/255)
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
      VStack(alignment:.leading,spacing:5) {
        HStack {
          marker
          Spacer()
          Text(position(context.state)).monospacedDigit().accessibilityIdentifier("island-position")
        }.font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
        content(context.state)
        actions(context.state)
      }
      .padding(.horizontal,18).padding(.vertical,10)
      .accessibilityElement(children:.contain).accessibilityIdentifier("reading-activity-card")
      .foregroundStyle(Color(red:34/255,green:40/255,blue:40/255))
      .activityBackgroundTint(Color(red:246/255,green:246/255,blue:243/255))
      .activitySystemActionForegroundColor(accent)
      .widgetURL(URL(string:"lingfer://live-reading"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {marker.foregroundStyle(.white.opacity(0.65)).padding(.leading,8).padding(.top,5)}
        DynamicIslandExpandedRegion(.trailing) {
          Text(position(context.state)).font(.system(size:11,weight:.medium)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
            .accessibilityIdentifier("island-position")
            .padding(.trailing,10).padding(.top,5)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment:.leading,spacing:4) {
            content(context.state)
            actions(context.state)
          }
          .frame(minWidth:296,maxWidth:.infinity,alignment:.leading)
          .padding(.horizontal,4).padding(.bottom,2)
          .accessibilityElement(children:.contain).accessibilityIdentifier("reading-island-expanded")
          .foregroundStyle(.white)
        }
      } compactLeading: {
        Image(systemName:context.state.paused ? "pause.fill" : "text.viewfinder")
          .accessibilityLabel("语渡随屏阅读").accessibilityIdentifier("island-compact-leading")
      } compactTrailing: {
        Text(context.state.paused ? "暂停" : "\((context.state.total ?? context.state.count)>0 ? (context.state.position ?? 0)+1 : 0)/\(context.state.total ?? context.state.count)")
          .font(.system(size:11,weight:.medium)).monospacedDigit()
          .accessibilityIdentifier("island-compact-position")
      } minimal: {
        Image(systemName:context.state.paused ? "pause.fill" : "text.viewfinder")
          .accessibilityLabel("语渡随屏阅读").accessibilityIdentifier("island-minimal")
      }
      .widgetURL(URL(string:"lingfer://live-reading"))
      .keylineTint(accent)
    }
  }

  // Keep the independent Latin marker: screen OCR must not ingest our card.
  private var marker:some View {
    HStack(spacing:3) {
      Image(systemName:"text.viewfinder").font(.system(size:11))
      Text("LINGFER CARD").font(.system(size:8,weight:.semibold))
    }.accessibilityLabel("语渡随屏阅读")
  }
  private func position(_ state:ReadingActivityAttributes.ContentState)->String {
    let total=state.total ?? state.count
    let base="\(total>0 ? (state.position ?? 0)+1 : 0)/\(total)"
    let detail=(state.detailTotal ?? 1)>1 ? " · \((state.detailPosition ?? 0)+1)/\(state.detailTotal ?? 1)页" : ""
    let prefix=state.paused ? "暂停 · " : state.status == "正在翻译当前页面…" ? "更新中 · " : ""
    return prefix+base+detail
  }
  @ViewBuilder private func content(_ state:ReadingActivityAttributes.ContentState)->some View {
    let type=ReadingActivityTypography(category:state.typeCategory)
    if !state.translation.isEmpty {
      Text(state.translation)
        .font(.system(size:type.translationSize))
        .lineSpacing(0).lineLimit(type.translationLines).fixedSize(horizontal:false,vertical:true)
        .frame(maxWidth:.infinity,alignment:.leading)
        .accessibilityIdentifier("island-translation").privacySensitive()
    } else if let term=state.terms.first {
      let layoutWord=state.originalTerm ?? term.source
      VStack(alignment:.leading,spacing:2) {
        Text(term.source).font(.system(size:type.wordSize(layoutWord),weight:.semibold))
          .lineLimit(2).fixedSize(horizontal:false,vertical:true)
          .accessibilityLabel(state.originalTerm ?? term.source)
          .accessibilityIdentifier("island-word")
        Text(term.meaning).font(.system(size:type.meaningSize(layoutWord)))
          .lineLimit(type.meaningLines(layoutWord)).fixedSize(horizontal:false,vertical:true)
          .accessibilityIdentifier("island-meaning")
        if !state.source.isEmpty, !type.longWord(layoutWord),type.bodySize<=18,
          ReadingActivityText.height(term.meaning,font:.systemFont(ofSize:type.meaningSize(layoutWord)))<=21 {
          context(state.source,word:term.source).font(.system(size:12))
            .foregroundStyle(.secondary).lineLimit(1)
        }
      }.frame(maxWidth:.infinity,alignment:.leading).privacySensitive()
    } else {
      Text(state.status).font(.system(size:16)).lineLimit(3).fixedSize(horizontal:false,vertical:true)
        .frame(maxWidth:.infinity,alignment:.leading)
    }
  }
  private func context(_ source:String,word:String)->Text {
    guard let range=source.range(of:word,options:.caseInsensitive) else {return Text(source)}
    return Text(String(source[..<range.lowerBound]))+Text(String(source[range])).bold()+Text(String(source[range.upperBound...]))
  }
  private func actions(_ state:ReadingActivityAttributes.ContentState)->some View {
    HStack(spacing:2) {
      Button(intent:PreviousReadingItemIntent()) {icon("chevron.left")}
        .accessibilityLabel("上一项或上一页").accessibilityIdentifier("island-previous")
      Button(intent:NextReadingItemIntent()) {icon("chevron.right")}
        .accessibilityLabel("下一项或下一页").accessibilityIdentifier("island-next")
      Spacer(minLength:2)
      Button(intent:ToggleReadingPauseIntent()) {icon(state.paused ? "play.fill" : "pause.fill")}
        .accessibilityLabel(state.paused ? "继续" : "暂停").accessibilityIdentifier("island-pause")
      Button(intent:StopReadingIntent()) {icon("stop.fill")}
        .accessibilityLabel("停止阅读").accessibilityIdentifier("island-stop")
      Link(destination:URL(string:"lingfer://live-reading?display=\(state.presentation == "island" ? "floating" : "island")")!) {
        icon(state.presentation == "island" ? "pip.enter" : "apps.iphone")
      }.accessibilityLabel(state.presentation == "island" ? "开启浮窗并保留灵动岛" : "收起浮窗，仅保留灵动岛")
        .accessibilityIdentifier("island-switch-display")
    }
    .font(.system(size:15,weight:.medium)).buttonStyle(.plain)
  }
  private func icon(_ name:String)->some View {Image(systemName:name).frame(width:44,height:44).contentShape(Rectangle())}
}

import ImageIO
import NaturalLanguage
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

final class ShareViewController: UIViewController {
  private let model = ShareReadingModel()

  override func viewDidLoad() {
    super.viewDidLoad()
    overrideUserInterfaceStyle = .light
    let host = UIHostingController(rootView: ShareReadingView(model: model, close: { [weak self] in
      self?.model.close()
      self?.extensionContext?.completeRequest(returningItems: nil)
    }))
    host.overrideUserInterfaceStyle = .light
    addChild(host)
    view.addSubview(host.view)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    host.didMove(toParent: self)
    readSharedInput()
  }

  private func readSharedInput() {
    let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) }) {
      provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { [weak self] value, _ in
        if let payload = value as? [String: Any], let page = payload[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any], let text = page["text"] as? String, !text.isEmpty {
          self?.model.accept(text, source: page["title"] as? String ?? "Safari 网页")
        } else { self?.readFallback(providers, items: items) }
      }
    } else { readFallback(providers, items: items) }
  }

  private func readFallback(_ providers: [NSItemProvider], items: [NSExtensionItem]) {
    if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] value, _ in
        if let text = value as? String { self?.model.accept(text, source: "分享的文字") }
        else if let text = value as? NSAttributedString { self?.model.accept(text.string, source: "分享的文字") }
        else { self?.model.fail("没有收到可阅读的文字，请尝试分享截图。") }
      }
    } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
      provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
        guard let data else { self?.model.fail("图片没有读取完成，请重试。"); return }
        self?.model.recognize(data)
      }
    } else if let text = items.compactMap({ $0.attributedContentText?.string }).first, !text.isEmpty {
      model.accept(text, source: "分享的文字")
    } else {
      model.fail("当前 App 只分享了链接，没有提供正文。请选中文字再分享，或分享当前页面的截图。")
    }
  }
}

struct NativeReadingGlass: ViewModifier {
  var radius:CGFloat=12
  @Environment(\.accessibilityReduceTransparency) private var solid
  @ViewBuilder func body(content:Content)->some View {
    if solid {content.background(NativeReadingTheme.paper,in:RoundedRectangle(cornerRadius:radius)).overlay(RoundedRectangle(cornerRadius:radius).stroke(NativeReadingTheme.line,lineWidth:1))}
    else if #available(iOS 26.0,*) { content.glassEffect(.regular.interactive(),in:RoundedRectangle(cornerRadius:radius)) }
    else { content.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:radius)).overlay(RoundedRectangle(cornerRadius:radius).stroke(NativeReadingTheme.line.opacity(0.7),lineWidth:1)) }
  }
}
private typealias GlassChip = NativeReadingGlass

struct NativeReadingGlassButton:ButtonStyle {
  func makeBody(configuration:Configuration)->some View {
    configuration.label.font(.subheadline.weight(.medium))
      .foregroundStyle(NativeReadingTheme.accent)
      .padding(.horizontal,14).frame(minHeight:44)
      .contentShape(Capsule()).modifier(NativeReadingGlass(radius:24))
      .opacity(configuration.isPressed ? 0.65 : 1)
  }
}
private struct SharePlacement: Identifiable { let id:String;let word:ShareWord;let anchor:CGRect;let label:CGRect? }
private struct SharePicture: View {
  @ObservedObject var model:ShareReadingModel
  let image:UIImage
  private func placements(_ size:CGSize)->[SharePlacement] {
    let obstacles=model.ocrWords.map{CGRect(x:$0.rect.minX*size.width,y:$0.rect.minY*size.height,width:$0.rect.width*size.width,height:$0.rect.height*size.height)}
    var occupied:[CGRect]=[];var result:[SharePlacement]=[]
    for word in model.words.prefix(14) {
      guard let start=word.sourceStart,let end=word.sourceEnd else {continue}
      let tokens=zip(model.ocrWords,obstacles).filter{$0.0.range.location<end && NSMaxRange($0.0.range)>start}
      guard let first=tokens.first else {continue}
      let anchor=tokens.dropFirst().reduce(first.1){$0.union($1.1)}
      let caption=word.shortTranslation
      let width=min(160,max(44,(caption as NSString).size(withAttributes:[.font:UIFont.systemFont(ofSize:12)]).width+16));let height:CGFloat=25
      let candidates=[CGRect(x:anchor.midX-width/2,y:anchor.minY-height-4,width:width,height:height),CGRect(x:anchor.midX-width/2,y:anchor.maxY+4,width:width,height:height),CGRect(x:anchor.maxX+4,y:anchor.midY-height/2,width:width,height:height),CGRect(x:anchor.minX-width-4,y:anchor.midY-height/2,width:width,height:height),CGRect(x:size.width-width-4,y:anchor.minY,width:width,height:height),CGRect(x:4,y:anchor.minY,width:width,height:height)]
      let bounds=CGRect(origin:.zero,size:size).insetBy(dx:3,dy:3)
      let label=candidates.first{box in bounds.contains(box) && !obstacles.contains{$0.insetBy(dx:-2,dy:-2).intersects(box)} && !occupied.contains{$0.insetBy(dx:-3,dy:-3).intersects(box)}}
      if let label {occupied.append(label)}
      result.append(SharePlacement(id:word.id,word:word,anchor:anchor,label:label))
    };return result
  }
  var body:some View {
    Image(uiImage:image).resizable().aspectRatio(contentMode:.fit).overlay {
      GeometryReader { geo in
        ForEach(placements(geo.size)) { item in
          Rectangle().fill(Color.blue.opacity(0.7)).frame(width:item.anchor.width,height:1.5).position(x:item.anchor.midX,y:item.anchor.maxY+1)
          Button {model.open(item.word)} label:{Color.clear.frame(width:item.anchor.width,height:max(16,item.anchor.height)).contentShape(Rectangle())}
            .buttonStyle(.plain).position(x:item.anchor.midX,y:item.anchor.midY).accessibilityIdentifier("share-marker-\(item.word.word)").accessibilityLabel("\(item.word.surface)，查看详解")
          if let box=item.label {
            Button {model.open(item.word)} label:{Text(item.word.shortTranslation).font(.system(size:12)).lineLimit(1).padding(.horizontal,7).frame(width:box.width,height:box.height).modifier(GlassChip())}
              .buttonStyle(.plain).position(x:box.midX,y:box.midY).accessibilityIdentifier("share-glass-\(item.word.word)")
          }
        }
      }
    }.accessibilityIdentifier("share-original-image")
  }
}

// Presentation values mirror lib/features/companion/lingfer_theme.dart.
enum NativeReadingTheme {
  private static func adaptive(_ light:UInt32,_ dark:UInt32)->UIColor {
    UIColor { traits in
      let rgb=traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(red:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:1)
    }
  }
  static let backgroundUI = adaptive(0xF6F6F3,0x171C1F)
  static let paperUI = adaptive(0xFFFFFF,0x20272B)
  static let inkUI = adaptive(0x222828,0xF2F3EE)
  static let mutedUI = adaptive(0x667073,0xA9B5B9)
  static let accentUI = adaptive(0x365F70,0xACCDDA)
  static let lineUI = adaptive(0xE5E5EA,0x39454B)
  static let background = Color(uiColor:backgroundUI)
  static let paper = Color(uiColor:paperUI)
  static let ink = Color(uiColor:inkUI)
  static let muted = Color(uiColor:mutedUI)
  static let accent = Color(uiColor:accentUI)
  static let onAccent = Color(uiColor:adaptive(0xFFFFFF,0x17272F))
  static let line = Color(uiColor:lineUI)
  static let warning = Color(uiColor:adaptive(0x9B4525,0xF1B196))
  static let warningSurface = Color(uiColor:adaptive(0xFFF1E9,0x392A24))
  static let reading = Font.custom("Georgia",size:20,relativeTo:.body)
  static let word = Font.custom("Georgia",size:27,relativeTo:.title2)

  static func savedIDs() -> Set<String> {
    guard let raw=CompanionStore.defaults.string(forKey:"saved"),let data=raw.data(using:.utf8),let words=try? JSONDecoder().decode([ShareWord].self,from:data) else {return []}
    return Set(words.map(\.id))
  }
  static func context(_ text:String, word:String)->Text {
    guard !word.isEmpty,let range=text.range(of:word,options:.caseInsensitive) else {return Text(text)}
    return Text(String(text[..<range.lowerBound])) + Text(String(text[range])).bold().foregroundColor(accent) + Text(String(text[range.upperBound...]))
  }
  static func syncLabel(_ value:String)->String {
    if value.hasPrefix("已放进语渡生词本") {return "已同步到语渡生词本"}
    if value.hasPrefix("已保存在当前分享记录中") {return "本次收藏尚未同步到主 App"}
    return value
  }
}
private typealias SharePaper = NativeReadingTheme
private struct ShareSurface:ViewModifier {
  func body(content:Content)->some View {
    content.background(SharePaper.paper).clipShape(RoundedRectangle(cornerRadius:24))
  }
}
private struct ShareAction:ButtonStyle {
  var muted=false
  func makeBody(configuration:Configuration)->some View {
    configuration.label.font(.subheadline.weight(.semibold))
      .foregroundColor(muted ? SharePaper.muted : SharePaper.accent)
      .padding(.horizontal,10).padding(.vertical,10).frame(minHeight:48)
      .contentShape(Rectangle()).opacity(configuration.isPressed ? 0.55 : 1)
  }
}
private struct ShareSentence:View {
  let word:ShareWord
  var body:some View {
    HStack(alignment:.top,spacing:12) {
      Rectangle().fill(SharePaper.line).frame(width:2)
      VStack(alignment:.leading,spacing:8) {
        Text("原句").font(.caption).foregroundColor(SharePaper.muted)
        SharePaper.context(word.context,word:word.surface).font(SharePaper.reading).lineSpacing(8).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
      }.frame(maxWidth:.infinity,alignment:.leading)
    }.fixedSize(horizontal:false,vertical:true)
  }
}
private struct ShareBookmark:View {
  let saved:Bool
  let action:()->Void
  let identifier:String
  var body:some View {
    Button(action:action) {Image(systemName:saved ? "bookmark.fill" : "bookmark").font(.system(size:22)).frame(width:48,height:48).contentShape(Rectangle())}
      .buttonStyle(.plain).foregroundColor(SharePaper.accent).accessibilityLabel(saved ? "已收藏" : "收藏生词").accessibilityIdentifier(identifier)
  }
}
private struct ShareWordCard:View {
  let word:ShareWord
  let saved:Bool
  let save:()->Void
  let known:()->Void
  let explain:()->Void
  let syncNotice:String?
  @Environment(\.dynamicTypeSize) private var typeSize
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      HStack(alignment:.top,spacing:8) {
        Text(word.surface).font(SharePaper.word).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
        ShareBookmark(saved:saved,action:save,identifier:"share-save-\(word.word)")
      }
      Text(word.translation).font(.body).lineSpacing(7).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
      ShareSentence(word:word)
      if typeSize.isAccessibilitySize {
        VStack(alignment:.leading,spacing:0) { actions }
      } else {HStack(spacing:8) { actions }}
      if let syncNotice {ShareNotice(text:syncNotice)}
    }.padding(18).frame(maxWidth:.infinity,alignment:.leading).modifier(ShareSurface())
  }
  @ViewBuilder private var actions:some View {
    Button(action:explain) {Label("语境讲解",systemImage:"text.alignleft")}.buttonStyle(ShareAction()).accessibilityIdentifier("share-explain-\(word.word)")
    Button("标为熟词",action:known).buttonStyle(ShareAction(muted:true)).accessibilityIdentifier("share-known-\(word.word)")
  }
}
private struct ShareNotice:View {
  let text:String
  var body:some View {
    Text(SharePaper.syncLabel(text)).font(.callout).foregroundColor(text.hasPrefix("已放进") ? SharePaper.accent : SharePaper.warning)
      .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
      .accessibilityIdentifier("share-sync-notice")
  }
}
struct ShareReadingView:View {
  @ObservedObject var model:ShareReadingModel
  let close:()->Void
  var title: String = "语渡阅读"
  var doneTitle: String = "完成"
  var controls: AnyView? = nil
  var compactControls: AnyView? = nil
  var showVocabularyScope=false
  @State private var section=1
  @State private var scopeOpen=false
  @State private var languageOpen=false
  @State private var aiConsentOpen=false
  @State private var savedIDs=SharePaper.savedIDs()
  @State private var lastSavedID:String?
  @Environment(\.dynamicTypeSize) private var typeSize

  var body:some View {
    NavigationView {
      GeometryReader { geometry in
        let wide=geometry.size.width>=680 && !typeSize.isAccessibilitySize
        VStack(spacing:0) {
          if geometry.size.height<480,let compactControls {compactControls}
          else if let controls {controls}
          header(compact:geometry.size.height<420)
          Rectangle().fill(SharePaper.line).frame(height:1)
          if wide {
            HStack(alignment:.top,spacing:0) {
              original.frame(maxWidth:.infinity)
              Rectangle().fill(SharePaper.line).frame(width:1)
              companion.frame(width:geometry.size.width*5/11)
            }
          } else {
            tabs
            if section==0 {original} else {companion}
          }
        }.background(SharePaper.background)
      }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement:.navigationBarLeading) {Button("联网 AI") {aiConsentOpen=true}.buttonStyle(ShareAction()).accessibilityIdentifier("share-ai-consent")}
        ToolbarItem(placement:.principal) {Text(title).font(.headline).foregroundColor(SharePaper.ink).lineLimit(1)}
        ToolbarItem(placement:.navigationBarTrailing) {Button(doneTitle,action:close).buttonStyle(.plain).fixedSize(horizontal:true,vertical:false).accessibilityIdentifier("share-done")}
      }
      .sheet(isPresented:$scopeOpen) {scopeSheet}
      .sheet(isPresented:$languageOpen) {languageSheet}
      .sheet(isPresented:$aiConsentOpen) {NativeAIConsentSheet(model:model)}
      .sheet(item:$model.selected) {word in ShareWordDetail(model:model,word:word,savedIDs:$savedIDs)}
    }.navigationViewStyle(.stack).tint(SharePaper.accent).foregroundColor(SharePaper.ink)
      .onAppear {savedIDs=SharePaper.savedIDs();model.refreshAIConsent()}
      .onReceive(NotificationCenter.default.publisher(for:Notification.Name("lingferAIConsentChanged"))) {_ in model.refreshAIConsent()}
  }
  private var modeButton:some View {
    Menu {
      Button("学习辅助") {if model.readingMode != "learning" {model.setMode("learning")}}
      Button("整页对照") {if model.readingMode != "translation" {model.setMode("translation")};section=1}
    } label: {
      HStack(spacing:5) {
        Text(model.readingMode == "translation" ? "整页对照" : "学习辅助")
        Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold))
      }
    }.buttonStyle(NativeReadingGlassButton()).accessibilityIdentifier("share-mode")
  }
  private func header(compact:Bool)->some View {
    VStack(alignment:.leading,spacing:0) {
      if typeSize.isAccessibilitySize {
        HStack {modeButton;Spacer();if model.readingMode == "learning" || showVocabularyScope {scopeButton}}
        languageSummary
      } else {
        HStack(spacing:0) {
          modeButton
          Spacer(minLength:4)
          languageSummary
          if model.readingMode == "learning" || showVocabularyScope {scopeButton}
        }
      }
    }.font(.subheadline).padding(.horizontal,12).padding(.vertical,4).background(SharePaper.background)
  }
  private var languageSummary:some View {
    Button {languageOpen=true} label: {
      HStack(spacing:6) {
        Text("\(model.languageName(model.sourceLanguage)) → \(model.languageName(model.effectiveTarget))").fixedSize(horizontal:false,vertical:true)
        Image(systemName:"chevron.down").font(.caption)
      }
    }.buttonStyle(NativeReadingGlassButton()).accessibilityIdentifier("share-language-summary")
  }
  private var languageSheet:some View {
    NavigationView {
      ScrollView {
        VStack(alignment:.leading,spacing:24) {
          VStack(alignment:.leading,spacing:8) {
            Text("原文语言").font(.caption).foregroundColor(SharePaper.muted)
            Picker("原文",selection:Binding(get:{model.sourceLanguage},set:{if model.sourceLanguage != $0 {model.setLanguages(source:$0)}})) {
              ForEach(model.languages,id:\.0) {Text($0.1).tag($0.0)}
            }.accessibilityIdentifier("share-source-language")
          }
          VStack(alignment:.leading,spacing:8) {
            Text("译文语言").font(.caption).foregroundColor(SharePaper.muted)
            Picker("译文",selection:Binding(get:{model.effectiveTarget},set:{if model.effectiveTarget != $0 {model.setLanguages(target:$0)}})) {
              ForEach(model.languages.filter{$0.0 != "auto"},id:\.0) {Text($0.1).tag($0.0)}
            }.accessibilityIdentifier("share-target-language")
          }
        }.pickerStyle(.menu).padding(22).frame(maxWidth:.infinity,alignment:.leading)
      }.background(SharePaper.paper).navigationTitle("语言").navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItem(placement:.navigationBarTrailing) {Button("完成") {languageOpen=false}.accessibilityIdentifier("share-language-done")}}
    }.navigationViewStyle(.stack).tint(SharePaper.accent)
  }
  private var languages:some View {
    HStack(spacing:4) {
      Picker("原文",selection:Binding(get:{model.sourceLanguage},set:{if model.sourceLanguage != $0 {model.setLanguages(source:$0)}})) {
        ForEach(model.languages,id:\.0) {Text($0.1).tag($0.0)}
      }.accessibilityIdentifier("share-source-language")
      Image(systemName:"arrow.right").font(.caption).foregroundColor(SharePaper.muted).accessibilityHidden(true)
      Picker("译文",selection:Binding(get:{model.effectiveTarget},set:{if model.effectiveTarget != $0 {model.setLanguages(target:$0)}})) {
        ForEach(model.languages.filter{$0.0 != "auto"},id:\.0) {Text($0.1).tag($0.0)}
      }.accessibilityIdentifier("share-target-language")
    }.font(.subheadline).pickerStyle(.menu).fixedSize(horizontal:false,vertical:true)
  }
  private var scopeTitle:String {
    if model.englishScope {return model.levels.first{$0.0==model.level}?.1 ?? model.level}
    return ["basic":"基础","intermediate":"进阶","advanced":"高阶"][model.difficulty] ?? "进阶"
  }
  private var scopeButton:some View {
    Button {scopeOpen=true} label: {
      HStack(spacing:6) {Text(scopeTitle);Image(systemName:"chevron.down").font(.caption)}
    }.buttonStyle(ShareAction()).accessibilityLabel("\(model.englishScope ? "学习范围" : "参考难度")，\(scopeTitle)")
      .accessibilityIdentifier("share-scope-summary")
  }
  private var tabs:some View {
    HStack(spacing:0) {
      tab("原文",value:0,identifier:"share-original-tab")
      tab(model.readingMode == "translation" ? "译文" : "词卡 \(model.words.count)",value:1,identifier:"share-words-tab")
    }.padding(4).background(SharePaper.line.opacity(0.55),in:Capsule()).padding(.horizontal,18).padding(.vertical,8)
  }
  private func tab(_ title:String,value:Int,identifier:String)->some View {
    Button {section=value} label: {
      Text(title).font(.subheadline.weight(section==value ? .semibold : .regular))
        .frame(maxWidth:.infinity,minHeight:44)
        .background(section==value ? SharePaper.paper : Color.clear,in:Capsule())
        .foregroundColor(section==value ? SharePaper.ink : SharePaper.muted).contentShape(Capsule())
    }.buttonStyle(.plain).accessibilityIdentifier(identifier).accessibilityValue(section==value ? "已选中" : "")
  }
  private var original:some View {
    ScrollView {
      VStack(alignment:.leading,spacing:18) {
        if typeSize.isAccessibilitySize {Text(model.source).font(.caption).foregroundColor(SharePaper.muted)}
        Text(model.historyPageCount>0 ? "本次阅读原文" : "已识别原文").font(.headline)
        if !model.text.isEmpty {
          Text("\(model.text.filter{!$0.isWhitespace}.count) 字\(model.historyPageCount>0 ? " · \(model.historyPageCount) 个页面记录" : "")")
            .font(.caption).foregroundColor(SharePaper.muted).accessibilityIdentifier("share-source-coverage")
          if controls != nil {
            Text("这里显示本机已读到的全部原文，不代表整篇文章。浮窗遮住的新内容，可移开浮窗后补读。")
              .font(.caption).foregroundColor(SharePaper.muted).fixedSize(horizontal:false,vertical:true)
          }
        }
        if let image=model.image {
          SharePicture(model:model,image:image).clipShape(RoundedRectangle(cornerRadius:10))
          Text("点原词标记或译义查看详解。").font(.caption).foregroundColor(SharePaper.muted)
        }
        if !model.text.isEmpty {
          Text(model.text).font(SharePaper.reading).lineSpacing(12).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            .accessibilityIdentifier("share-original-text")
        } else if model.loading {ProgressView("正在读取分享内容…")} else {
          Text(model.error ?? (controls == nil ? "没有收到原文。请返回原 App，选中文字或分享清晰截图。" : "切换到想读的 App，原文会自动出现在这里。")).foregroundColor(SharePaper.muted)
        }
      }.frame(maxWidth:640,alignment:.leading).frame(maxWidth:.infinity,alignment:.center).padding(20)
    }.background(SharePaper.paper).accessibilityIdentifier("share-original-scroll")
  }
  @ViewBuilder private var companion:some View {
    if model.readingMode == "translation" {pageTranslation} else {vocabulary}
  }
  private var pageTranslation:some View {
    ScrollView {
      VStack(alignment:.leading,spacing:18) {
        Text("整页对照").font(.title3.weight(.semibold))
        Text("已翻译 \(model.pageParts.filter{$0.translation != nil}.count) / \(model.pageParts.count) 段 · 不筛难度，不排除熟词").font(.caption).foregroundColor(SharePaper.muted)
        if model.loading {ProgressView("正在翻译…")}
        if let error=model.error {
          Text(error).foregroundColor(SharePaper.warning)
          Button("重试未完成段落") {model.retryPageTranslation()}.buttonStyle(ShareAction()).accessibilityIdentifier("share-page-retry")
        }
        ForEach(model.pageParts) {part in
          VStack(alignment:.leading,spacing:12) {
            Text(part.source).font(.body).lineSpacing(6).textSelection(.enabled)
            Text(part.translation ?? "尚未翻译").font(.body).lineSpacing(8).foregroundColor(part.translation == nil ? SharePaper.muted : SharePaper.accent).textSelection(.enabled)
            Divider()
          }.fixedSize(horizontal:false,vertical:true)
        }
        if !model.loading && model.pageParts.isEmpty {Text("没有可翻译的文字，请回到原文检查。").foregroundColor(SharePaper.muted)}
        Text("仅发送当前文字进行翻译，图片留在本机；译文不会自动加入生词本。").font(.caption).foregroundColor(SharePaper.muted)
      }.padding(18).frame(maxWidth:640).frame(maxWidth:.infinity,alignment:.leading)
    }.accessibilityIdentifier("share-page-scroll")
  }
  private var vocabulary:some View {
    ScrollView {
      VStack(alignment:.leading,spacing:16) {
        if typeSize.isAccessibilitySize {Text(model.source).font(.caption).foregroundColor(SharePaper.muted)}
        HStack(alignment:.firstTextBaseline) {
          Text("找到 \(model.words.count) 个匹配词").font(.subheadline).foregroundColor(SharePaper.muted)
          Spacer()
          if model.effectiveSource=="en" && model.targetLanguage=="zh" {Text("离线释义").font(.caption).foregroundColor(SharePaper.muted)}
        }
        if model.loading {ProgressView(model.image == nil ? "正在读取词汇…" : "正在识别截图…").padding(.vertical,20)}
        if let error=model.error {
          VStack(alignment:.leading,spacing:8) {
            Text(error).foregroundColor(SharePaper.warning).fixedSize(horizontal:false,vertical:true)
            Button("重新读取") {model.setLevel(model.level)}.buttonStyle(ShareAction()).accessibilityIdentifier("share-retry-reading")
          }.padding(16).background(SharePaper.warningSurface).cornerRadius(10)
        } else if !model.loading && model.words.isEmpty {
          VStack(alignment:.leading,spacing:12) {
            Image(systemName:model.text.isEmpty && controls != nil ? "viewfinder" : "text.magnifyingglass").font(.system(size:26,weight:.light)).foregroundColor(SharePaper.accent)
            Text(model.text.isEmpty && controls != nil ? "等待读取页面" : "当前范围没有匹配词").font(.system(.title3,design:.serif).weight(.semibold))
            Text(model.text.isEmpty && controls != nil ? "切换到想读的 App，停稳页面后会自动更新。" : "调整学习范围，或回到原文核对内容。").font(.callout).foregroundColor(SharePaper.muted)
            if !model.text.isEmpty {Button("调整范围") {scopeOpen=true}.buttonStyle(ShareAction())}
          }.padding(24).frame(maxWidth:.infinity,alignment:.leading).modifier(ShareSurface())
        }
        ForEach(model.words) {word in
          ShareWordCard(word:word,saved:savedIDs.contains(word.id),save:{model.save(word);savedIDs=SharePaper.savedIDs();lastSavedID=word.id},known:{model.known(word.id)},explain:{model.open(word)},syncNotice:lastSavedID==word.id ? model.notice : nil)
        }
        if let notice=model.notice, !model.words.contains(where:{$0.id==lastSavedID}) {ShareNotice(text:notice)}
        Text("英语→中文基础释义离线可用。其他翻译方向和语境讲解会发送对应文字给 AI，图片留在本机。")
          .font(.caption).foregroundColor(SharePaper.muted).fixedSize(horizontal:false,vertical:true).padding(.top,4)
      }.padding(18).frame(maxWidth:640).frame(maxWidth:.infinity)
    }.accessibilityIdentifier("share-words-scroll")
  }
  private var scopeSheet:some View {
    NavigationView {
      List {
        if model.englishScope {
          ForEach(model.levels,id:\.0) {value in
            Button {if model.level != value.0 {model.setLevel(value.0)};scopeOpen=false} label: {
              HStack {Text(value.1);Spacer();if model.level==value.0 {Image(systemName:"checkmark")}}
                .frame(minHeight:48).foregroundColor(model.level==value.0 ? SharePaper.accent : SharePaper.ink)
            }.accessibilityIdentifier("share-level-\(value.0)").listRowBackground(SharePaper.paper)
          }
        } else {
          ForEach(["basic","intermediate","advanced"],id:\.self) {value in
            Button {if model.difficulty != value {model.setDifficulty(value)};scopeOpen=false} label: {
              HStack {Text(["basic":"基础","intermediate":"进阶","advanced":"高阶"][value]!);Spacer();if model.difficulty==value {Image(systemName:"checkmark")}}
                .frame(minHeight:48).foregroundColor(SharePaper.ink)
            }.listRowBackground(SharePaper.paper)
          }
        }
        Text(model.englishScope ? "按考试词表筛选；已标为熟词的词会自动略过。" : "非英语难度为学习参考，并非官方考试分级。")
          .font(.caption).foregroundColor(SharePaper.muted).listRowBackground(SharePaper.paper)
      }.listStyle(.plain).background(SharePaper.background).navigationTitle(model.englishScope ? "选择学习范围" : "选择参考难度").navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItem(placement:.navigationBarTrailing) {Button("关闭") {scopeOpen=false}}}
    }.navigationViewStyle(.stack).tint(SharePaper.accent)
  }
}
/// The first step has its own stable layout, before the live page has any text.
struct ReadingStartView:View {
  @ObservedObject var model:ShareReadingModel
  let message:String
  let start:()->Void
  let close:()->Void
  var previous:(()->Void)?=nil
  var displayControls:AnyView?=nil
  @State private var aiConsentOpen=false
  @Environment(\.dynamicTypeSize) private var typeSize
  var body:some View {
    NavigationView {
      GeometryReader {geometry in
        ScrollView {
          VStack(spacing:24) {
            Spacer(minLength:20)
            Image(systemName:"text.viewfinder").font(.system(size:30,weight:.light)).foregroundColor(SharePaper.accent)
              .frame(width:76,height:76).modifier(GlassChip(radius:38)).accessibilityHidden(true)
            VStack(spacing:12) {
              Text("随屏阅读").font(.system(.largeTitle,design:.serif).weight(.semibold)).foregroundColor(SharePaper.ink)
              Text("授权后可切换到想读的 App。\n停稳页面，即可查看阅读结果。")
                .font(.body).lineSpacing(5).foregroundColor(SharePaper.muted).multilineTextAlignment(.center)
            }
            // Reading mode and language are peers, with independent menus.
            if geometry.size.width<360 || typeSize.isAccessibilitySize {
              VStack(spacing:10) {modeMenu;languageMenu}
            } else {
              HStack(spacing:10) {modeMenu;languageMenu}
            }
            Button(model.aiConsentAllowed ? "联网 AI · 已允许" : "联网 AI · 仅本机阅读") {aiConsentOpen=true}
              .buttonStyle(ShareAction()).accessibilityIdentifier("live-ai-consent")
            if let displayControls {
              displayControls
              Text(model.readingMode == "translation" ? "浮窗对照显示原文和译文；也可单独选择灵动岛。\n读屏只读取当时可见的内容。" : "浮窗显示原句与词义；也可单独选择灵动岛。\n灵动岛未显示时，可从通知中心查看。")
                .font(.footnote).foregroundColor(SharePaper.muted).multilineTextAlignment(.center)
            }
            Button(action:start) {
              HStack(spacing:10) {Text("开启系统读屏");Image(systemName:"arrow.right").font(.system(size:15,weight:.medium))}
                .font(.body.weight(.semibold)).frame(maxWidth:.infinity,minHeight:54)
                .foregroundColor(SharePaper.onAccent).background(SharePaper.accent,in:Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("live-start")
            if let previous {Button("查看上次结果",action:previous).buttonStyle(ShareAction())}
            VStack(spacing:10) {
              Text("下一步由系统请求共享屏幕。")
              Text("图片留在本机；联网翻译与讲解仅发送对应文字。")
            }.font(.footnote).foregroundColor(SharePaper.muted).multilineTextAlignment(.center).lineSpacing(4)
            if message != "开启系统读屏后，切换到想阅读的 App。" && !message.isEmpty {
              Text(message).font(.footnote).foregroundColor(SharePaper.warning).multilineTextAlignment(.center)
            }
            Spacer(minLength:20)
          }.padding(.horizontal,28).padding(.vertical,20).frame(maxWidth:480,minHeight:geometry.size.height)
            .frame(maxWidth:.infinity)
        }.background(SharePaper.background)
      }.navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItem(placement:.navigationBarLeading) {
          Button(action:close) {Image(systemName:"chevron.left").font(.system(size:17,weight:.semibold)).frame(width:16,height:16)}
            .buttonStyle(.plain).accessibilityLabel("返回").accessibilityIdentifier("share-done")
        }}
    }.navigationViewStyle(.stack).tint(SharePaper.accent).foregroundStyle(SharePaper.ink)
      .sheet(isPresented:$aiConsentOpen) {NativeAIConsentSheet(model:model)}
      .onAppear {model.refreshAIConsent()}
      .onReceive(NotificationCenter.default.publisher(for:Notification.Name("lingferAIConsentChanged"))) {_ in model.refreshAIConsent()}
  }
  private var modeMenu:some View {
    Menu {
      Button {if model.readingMode != "learning" {model.setMode("learning")}} label:{Label("学习辅助",systemImage:model.readingMode == "learning" ? "checkmark" : "text.book.closed")}
      Button {if model.readingMode != "translation" {model.setMode("translation")}} label:{Label("整页对照",systemImage:model.readingMode == "translation" ? "checkmark" : "character.bubble")}
    } label: {
      choiceLabel(model.readingMode == "translation" ? "整页对照" : "学习辅助")
    }.buttonStyle(.plain).accessibilityIdentifier("live-mode-options").accessibilityLabel("阅读方式，\(model.readingMode == "translation" ? "整页对照" : "学习辅助")")
  }
  private var languageMenu:some View {
    Menu {
      Menu("原文语言") {ForEach(model.languages,id:\.0) {code,name in Button(name){if model.sourceLanguage != code {model.setLanguages(source:code)}}}}
      Menu("译文语言") {ForEach(model.languages.filter{$0.0 != "auto"},id:\.0) {code,name in Button(name){if model.effectiveTarget != code {model.setLanguages(target:code)}}}}
    } label: {
      choiceLabel("\(model.languageName(model.sourceLanguage)) → \(model.languageName(model.effectiveTarget))")
    }.buttonStyle(.plain).accessibilityIdentifier("live-reading-options")
  }
  private func choiceLabel(_ text:String)->some View {
    HStack(spacing:6) {
      Text(text).fixedSize(horizontal:false,vertical:true)
      Image(systemName:"chevron.down").font(.system(size:10,weight:.semibold))
    }.font(.subheadline).foregroundColor(SharePaper.accent).frame(maxWidth:.infinity,minHeight:44)
      .padding(.horizontal,12).modifier(GlassChip(radius:24))
  }
}

private struct NativeAIConsentSheet:View {
  @ObservedObject var model:ShareReadingModel
  @Environment(\.dismiss) private var dismiss
  var body:some View {
    NavigationView {
      ScrollView {
        VStack(alignment:.leading,spacing:20) {
          Text("使用联网 AI").font(.title2.weight(.semibold))
          Text(CompanionStore.aiConsentDisclosure).font(.body).lineSpacing(6).fixedSize(horizontal:false,vertical:true)
          Link("打开隐私政策",destination:CompanionStore.privacyPolicyURL).accessibilityIdentifier("ai-consent-policy")
          Text("联系邮箱：wyxwyx05@163.com").font(.footnote).foregroundColor(SharePaper.muted)
          Button("允许联网 AI") {model.setAIConsent(true);dismiss()}
            .buttonStyle(NativeReadingGlassButton()).accessibilityIdentifier("ai-consent-allow")
          Button(model.aiConsentAllowed ? "关闭联网 AI，保留本机阅读" : "仅本机阅读") {model.setAIConsent(false);dismiss()}
            .buttonStyle(ShareAction(muted:true)).accessibilityIdentifier("ai-consent-local")
        }.padding(24).frame(maxWidth:560,alignment:.leading).frame(maxWidth:.infinity)
      }.background(SharePaper.background).foregroundColor(SharePaper.ink)
        .navigationTitle("联网 AI 与隐私").navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItem(placement:.navigationBarTrailing) {Button("完成") {dismiss()}}}
    }.navigationViewStyle(.stack).tint(SharePaper.accent)
  }
}

private struct ShareWordDetail:View {
  @ObservedObject var model:ShareReadingModel
  let word:ShareWord
  @Binding var savedIDs:Set<String>
  var body:some View {
    NavigationView {
      ScrollView {
        VStack(alignment:.leading,spacing:20) {
          HStack(alignment:.top,spacing:8) {
            Text(word.surface).font(SharePaper.word).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
            ShareBookmark(saved:savedIDs.contains(word.id),action:{model.save(word);savedIDs=SharePaper.savedIDs()},identifier:"share-detail-save")
          }
          Text(word.translation).font(.body).lineSpacing(7).textSelection(.enabled)
          ShareSentence(word:word)
          Rectangle().fill(SharePaper.line).frame(height:1)
          Text("语境讲解").font(.headline).foregroundColor(SharePaper.accent)
          if model.explaining {
            HStack(alignment:.top,spacing:10) {ProgressView();Text("正在结合原文讲解…").foregroundColor(SharePaper.muted)}
              .accessibilityIdentifier("share-ai-loading")
          }
          if let answer=model.answer {
            Text(answer).font(.body).lineSpacing(10).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
              .foregroundColor(answer=="详解暂未响应，原词译义和收藏仍可使用。" ? SharePaper.warning : SharePaper.ink)
              .accessibilityIdentifier("share-answer")
          }
          Button("重新请求讲解") {model.explain(word)}.buttonStyle(ShareAction()).disabled(model.explaining).accessibilityIdentifier("share-retry-explanation")
          Button("标为熟词") {model.known(word.id);model.selected=nil}.buttonStyle(ShareAction(muted:true)).accessibilityIdentifier("share-detail-known")
          if let notice=model.notice {ShareNotice(text:notice)}
          Text("讲解仅依据当前原句，基础释义和收藏始终可用。").font(.caption).foregroundColor(SharePaper.muted)
        }.padding(22).frame(maxWidth:640,alignment:.leading).frame(maxWidth:.infinity)
      }.background(SharePaper.paper).navigationTitle("语境讲解").navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItem(placement:.navigationBarTrailing) {Button("关闭") {model.selected=nil}}}
    }.navigationViewStyle(.stack).tint(SharePaper.accent).foregroundColor(SharePaper.ink)
  }
}

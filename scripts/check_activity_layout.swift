// Temporary simulator rendering harness for the production widget content.
// Uses sample text, does not start capture or call any translation service.
import UIKit
import SwiftUI
@main final class LayoutQA:UIResponder,UIApplicationDelegate {
 func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {true}
 func application(_ application:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions)->UISceneConfiguration {
  let config=UISceneConfiguration(name:"Layout",sessionRole:session.role);config.delegateClass=LayoutScene.self;return config
 }
}
final class LayoutScene:UIResponder,UIWindowSceneDelegate {
 var window:UIWindow?
 func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions) {
  guard let scene=scene as? UIWindowScene else{return}
  let window=UIWindow(windowScene:scene);window.rootViewController=UIHostingController(rootView:Text("语渡灵动岛排版验证\n测试样例，不含读屏或真实翻译").padding());window.makeKeyAndVisible();self.window=window
  DispatchQueue.main.asyncAfter(deadline:.now()+1) {self.render()}
 }
 @MainActor func render() {
  let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
  var records:[[String:Any]]=[]
  let sampleTranslation="阅读完整的段落有助于理解原意。保留上下文可以避免误解，也能帮助我们判断一个词在当前语境中的准确含义。翻页时应保持阅读位置稳定，长内容通过前后按钮继续查看。"
  let examples=[("word","essential","必不可少的；关键的", "Consider the essential argument."),("long-word","electroencephalographically","通过脑电图记录的方式来观察并分析大脑活动", ""),("long-source",String(repeating:"语言理解与实际语境",count:5),"准确的上下文解释应完整保留。", ""),("translation","",sampleTranslation, "")]
  for category in [UIContentSizeCategory.large,.accessibilityExtraExtraExtraLarge] {
   UITraitCollection(preferredContentSizeCategory:category).performAsCurrent {
    let type=ReadingActivityTypography(category:category.rawValue)
    for (name,word,meaning,context) in examples {
     let translated=name=="translation"
     let chunks=ReadingActivityText.pages(meaning,size:translated ? type.translationSize : type.meaningSize(word),lines:translated ? type.translationLines : type.meaningLines(word))
     let words=ReadingActivityText.pages(word,size:type.wordSize(word),lines:2,weight:.semibold)
     let state=ReadingActivityAttributes.ContentState.preview(paused:false,mode:translated ? "translation" : "learning",count:9,terms:translated ? [] : [(words.first ?? word,chunks.first ?? meaning)],source:context,translation:translated ? chunks.first ?? "" : "",status:"布局样例 · 无读屏",position:4,total:9,detailPosition:0,detailTotal:max(chunks.count,words.count),presentation:"island",typeCategory:category.rawValue,originalTerm:word)
     let widget=ReadingActivityWidget()
     let panel=VStack(alignment:.leading,spacing:4) {widget.content(state);widget.actions(state)}.frame(width:288,alignment:.leading).foregroundStyle(.white).padding(8).background(.black)
     let host=UIHostingController(rootView:panel)
     let size=host.sizeThatFits(in:CGSize(width:304,height:10000))
     let renderer=ImageRenderer(content:panel);renderer.scale=3
     let label=name+(category == .large ? "-normal" : "-large-type")
     if let image=renderer.uiImage,let data=image.pngData() {try? data.write(to:dir.appendingPathComponent(label+".png"))}
     records.append(["name":label,"height":size.height,"contentHeight":size.height-16,"pages":chunks.count,"bodySize":type.bodySize,"translationSize":type.translationSize])
    }
   }
  }
  let data=try! JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]);try! data.write(to:dir.appendingPathComponent("measurements.json"))
  print("LINGFER_LAYOUT_READY",String(data:data,encoding:.utf8)!)
 }
}

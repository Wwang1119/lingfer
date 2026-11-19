import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene,willConnectTo:session,options:connectionOptions)
    if let url=connectionOptions.urlContexts.first(where:{$0.url.scheme == "lingfer" && $0.url.host == "live-reading"})?.url {
      DispatchQueue.main.asyncAfter(deadline:.now()+0.7) { self.showReading(in:scene,url:url) }
    }
  }
  private func showReading(in scene:UIScene,url:URL? = nil) {
    guard let root=(scene as? UIWindowScene)?.windows.first(where:{$0.isKeyWindow})?.rootViewController else{return}
    var presenter=root
    while let next=presenter.presentedViewController {presenter=next}
    LiveReadingSession.shared.open(from:presenter)
    if let url,let mode=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="display"})?.value.flatMap(LiveReadingPresentation.init(rawValue:)) {
      LiveReadingSession.shared.setPresentation(mode)
    }
  }
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let reading = URLContexts.filter { $0.url.scheme == "lingfer" && $0.url.host == "live-reading" }
    if !reading.isEmpty {
      DispatchQueue.main.async {
        self.showReading(in:scene,url:reading.first?.url)
      }
    }
    let others=URLContexts.subtracting(reading)
    if !others.isEmpty {super.scene(scene,openURLContexts:others)}
  }
}

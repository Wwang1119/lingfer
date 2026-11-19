import Flutter
import Foundation
import UIKit

final class ShareStatePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lingfer/share_reader", binaryMessenger: registrar.messenger())
    let plugin=ShareStatePlugin()
    registrar.addMethodCallDelegate(plugin, channel: channel)
    FlutterEventChannel(name:"lingfer/apple_screen_reader_events",binaryMessenger:registrar.messenger()).setStreamHandler(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getAIConsent":
      let arguments=ProcessInfo.processInfo.arguments
      let diagnostic=arguments.contains("--lingfer-live-qa") || ProcessInfo.processInfo.environment["LINGFER_LIVE_QA"] == "1"
      if diagnostic,arguments.contains("--qa-preserve-reading"),arguments.contains("--qa-public-reading-fixture") {
        _ = LiveReadingSession.shared
      }
      result(CompanionStore.aiConsentState())
    case "setAIConsent":
      guard let values=call.arguments as? [String:Any],values["version"] as? Int == CompanionStore.aiConsentVersion,
        let allowed=values["allowed"] as? Bool else {result(CompanionStore.aiConsentState());return}
      CompanionStore.setAIConsent(allowed:allowed)
      result(CompanionStore.aiConsentState())
    case "status": result(LiveReadingSession.shared.status())
    case "start":
      guard let presenter=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).flatMap({$0.windows}).first(where:{$0.isKeyWindow})?.rootViewController else {result(false);return}
      var top=presenter
      while let next=top.presentedViewController {top=next}
      LiveReadingSession.shared.open(from:top);result(true)
    case "stop": LiveReadingSession.shared.stop();result(nil)
    case "pause": LiveReadingSession.shared.setPaused((call.arguments as? [String:Any])?["paused"] as? Bool ?? true);result(nil)
    case "capture": LiveReadingSession.shared.configure();result(nil)
    case "configure":
      guard let values = call.arguments as? [String: Any] else { result(nil); return }
      var changes: [String: Any] = [:]
      for key in ["level", "proxyUrl", "appSecret", "saved", "sourceLanguage", "targetLanguage", "generalDifficulty", "readingMode"] {
        if let value = values[key] as? String { changes[key] = value }
      }
      if let known = values["known"] as? [String] { changes["known"] = known }
      if let automatic = values["automatic"] as? Bool { changes["automatic"] = automatic }
      CompanionStore.defaults.merge(changes)
      LiveReadingSession.shared.configure()
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }
  func onListen(withArguments arguments:Any?,eventSink events:@escaping FlutterEventSink)->FlutterError? {LiveReadingSession.shared.sink=events;return nil}
  func onCancel(withArguments arguments:Any?)->FlutterError? {LiveReadingSession.shared.sink=nil;return nil}
}

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Use iOS Vision OCR to avoid CocoaPods downloading MLKit language models
    // from dl.google.com (often blocked on mainland China networks).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VisionOcrPlugin") {
      VisionOcrPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShareStatePlugin") {
      ShareStatePlugin.register(with: registrar)
    }
  }
}

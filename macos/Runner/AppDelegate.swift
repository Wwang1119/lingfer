import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var pendingOpenPaths: [String] = []
  private var fileOpenChannel: FlutterMethodChannel?
  private var securityScopeChannel: FlutterMethodChannel?
  private var securityScopedUrls: [URL] = []

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    ensureFileOpenChannel()
    ensureSecurityScopeChannel()
    flushPendingOpenPaths()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    handleOpenPath(filename)
    return true
  }

  override func application(_ application: NSApplication, openFiles filenames: [String]) {
    for name in filenames {
      handleOpenPath(name)
    }
    application.reply(toOpenOrPrint: .success)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func handleOpenPath(_ filename: String) {
    let url = URL(fileURLWithPath: filename).standardizedFileURL
    _ = url.startAccessingSecurityScopedResource()
    securityScopedUrls.append(url)
    let path = url.path
    let lower = path.lowercased()
    if !(lower.hasSuffix(".txt") || lower.hasSuffix(".epub")) {
      return
    }

    pendingOpenPaths.append(path)
    ensureFileOpenChannel()
    flushPendingOpenPaths()
  }

  private func ensureFileOpenChannel() {
    if fileOpenChannel != nil { return }
    guard let controller = mainFlutterViewController() else { return }
    fileOpenChannel = FlutterMethodChannel(
      name: "lingfer/file_open",
      binaryMessenger: controller.engine.binaryMessenger
    )
  }

  private func ensureSecurityScopeChannel() {
    if securityScopeChannel != nil { return }
    guard let controller = mainFlutterViewController() else {
      // In some startup phases the FlutterViewController isn't attached yet.
      // Retry shortly so Dart can call the channel later (e.g. after FilePicker).
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
        self?.ensureSecurityScopeChannel()
      }
      return
    }
    let channel = FlutterMethodChannel(
      name: "lingfer/security_scope",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      if call.method != "startAccess" {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = call.arguments as? String, !path.isEmpty else {
        result(false)
        return
      }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      let ok = url.startAccessingSecurityScopedResource()
      if ok {
        self.securityScopedUrls.append(url)
      }
      result(ok)
    }
    securityScopeChannel = channel
  }

  private func flushPendingOpenPaths() {
    guard let channel = fileOpenChannel else { return }
    if pendingOpenPaths.isEmpty { return }
    let paths = pendingOpenPaths
    pendingOpenPaths.removeAll()
    for path in paths {
      channel.invokeMethod("openFile", arguments: path)
    }
  }

  private func mainFlutterViewController() -> FlutterViewController? {
    if let window = mainFlutterWindow,
       let controller = window.contentViewController as? FlutterViewController {
      return controller
    }
    for window in NSApplication.shared.windows {
      if let controller = window.contentViewController as? FlutterViewController {
        return controller
      }
    }
    return nil
  }
}

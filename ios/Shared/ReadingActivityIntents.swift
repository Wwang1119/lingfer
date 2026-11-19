import AppIntents
import Foundation

private enum ReadingActivityActionError:LocalizedError {
  case inactive
  var errorDescription:String? {"本次读屏已结束，请回到语渡重新开启。"}
}

@available(iOS 17.0, *)
struct PreviousReadingItemIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "语渡上一词或上一语段"
  static var openAppWhenRun = false
  @available(iOS 26.0, *) static var supportedModes:IntentModes {.background}
  func perform() async throws -> some IntentResult {
    #if !LINGFER_WIDGET_EXTENSION
    let active=await MainActor.run { ()->Bool in
      guard LiveReadingSession.shared.running else {ReadingActivityManager.shared.end();return false}
      LiveReadingSession.shared.moveActivitySelection(-1);return true
    }
    guard active else {throw ReadingActivityActionError.inactive}
    #endif
    return .result()
  }
}

@available(iOS 17.0, *)
struct NextReadingItemIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "语渡下一词或下一语段"
  static var openAppWhenRun = false
  @available(iOS 26.0, *) static var supportedModes:IntentModes {.background}
  func perform() async throws -> some IntentResult {
    #if !LINGFER_WIDGET_EXTENSION
    let active=await MainActor.run { ()->Bool in
      guard LiveReadingSession.shared.running else {ReadingActivityManager.shared.end();return false}
      LiveReadingSession.shared.moveActivitySelection(1);return true
    }
    guard active else {throw ReadingActivityActionError.inactive}
    #endif
    return .result()
  }
}

@available(iOS 17.0, *)
struct ToggleReadingPauseIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "暂停或继续语渡随屏阅读"
  static var openAppWhenRun = false
  @available(iOS 26.0, *) static var supportedModes:IntentModes {.background}
  func perform() async throws -> some IntentResult {
    #if !LINGFER_WIDGET_EXTENSION
    let active=await MainActor.run { ()->Bool in
      let session = LiveReadingSession.shared
      guard session.running else {ReadingActivityManager.shared.end();return false}
      session.setPaused(!session.paused);return true
    }
    guard active else {throw ReadingActivityActionError.inactive}
    #endif
    return .result()
  }
}

@available(iOS 17.0, *)
struct StopReadingIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "停止语渡随屏阅读"
  static var openAppWhenRun = false
  @available(iOS 26.0, *) static var supportedModes:IntentModes {.background}
  func perform() async throws -> some IntentResult {
    #if !LINGFER_WIDGET_EXTENSION
    await MainActor.run { LiveReadingSession.shared.stop() }
    #endif
    return .result()
  }
}

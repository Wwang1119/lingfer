import XCTest
import Vision
import UIKit
import ObjectiveC

final class ReadingUITests: XCTestCase {
  private let app = XCUIApplication()
  private var restoreSystemSynchronization:(()->Void)?

  override func setUpWithError() throws { continueAfterFailure = false }
  override func tearDownWithError() throws {
    if app.state == .runningBackground || app.state == .runningForeground {
      app.activate()
      let stop=app.buttons["live-stop"]
      if stop.exists && stop.isHittable {stop.tap()}
    }
    app.terminate()
    restoreSystemSynchronization?();restoreSystemSynchronization=nil
  }

  private func fixtureURL(_ filename: String) throws -> URL {
    let address = ProcessInfo.processInfo.environment["LINGFER_FIXTURE_BASE_URL"]
    let base = try XCTUnwrap(address.flatMap { URL(string: $0) },
                             "Set LINGFER_FIXTURE_BASE_URL in the test runner to the fixture server reachable by this iPhone.")
    XCTAssertTrue(["http", "https"].contains(base.scheme ?? "") && base.host != nil,
                  "The fixture server must be an absolute HTTP(S) URL.")
    return base.appendingPathComponent(filename)
  }

  private func requirePhysicalDevice() throws {
    #if targetEnvironment(simulator)
    throw XCTSkip("此集成测试需要真机的系统捕获能力及已注册的 App Group；无签名模拟器仅验证展示。")
    #endif
  }

  private func button(_ text: String, in application: XCUIApplication? = nil) -> XCUIElement {
    (application ?? app).descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", text, text)).firstMatch
  }

  /// Observe the actual video in the external fixture. Never foreground
  /// Lingfer or tap a recovery control while waiting for initial automatic PiP.
  private func waitForActualLivePiP(in reader:XCUIApplication,timeout:TimeInterval)->Bool {
    let deadline=Date().addingTimeInterval(timeout)
    while Date()<deadline {
      guard reader.state == .runningForeground else{return false}
      if let image=XCUIScreen.main.screenshot().image.cgImage {
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
        request.minimumTextHeight=0.002;request.recognitionLanguages=["zh-Hans","en-US"]
        if (try? VNImageRequestHandler(cgImage:image,options:[:]).perform([request])) != nil {
          let text=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined().replacingOccurrences(of:" ",with:"")
          if text.contains("点浮窗") {return true}
        }
      }
      Thread.sleep(forTimeInterval:0.8)
    }
    return false
  }

  private func screenshot(_ name: String, of application: XCUIApplication? = nil) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways
    add(attachment)
  }

  // Test-runner-only workaround for the permanently animated sharing indicator.
  // Keep event-loop synchronization; exclude animations only for SpringBoard.
  // The selector variants are also handled by Appium's upstream WebDriverAgent.
  private func avoidSystemAnimationWait()->()->Void {
    guard let type=NSClassFromString("XCUIApplicationProcess") else{return {}}
    func isSystem(_ receiver:AnyObject)->Bool {
      guard let value=receiver as? NSObject,value.responds(to:NSSelectorFromString("bundleID")) else{return false}
      return value.value(forKey:"bundleID") as? String == "com.apple.springboard"
    }
    let selector=NSSelectorFromString("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:")
    if let method=class_getInstanceMethod(type,selector) {
      let original=method_getImplementation(method)
      let call=unsafeBitCast(original,to:(@convention(c)(AnyObject,Selector,Bool,Bool)->Void).self)
      let block:@convention(block)(AnyObject,Bool,Bool)->Void={object,animations,pre in call(object,selector,isSystem(object) ? false : animations,pre)}
      let replacement=imp_implementationWithBlock(block)
      method_setImplementation(method,replacement)
      return {method_setImplementation(method,original);_ = imp_removeBlock(replacement)}
    }
    let legacy=NSSelectorFromString("waitForQuiescenceIncludingAnimationsIdle:")
    guard let method=class_getInstanceMethod(type,legacy) else{return {}}
    let original=method_getImplementation(method)
    let call=unsafeBitCast(original,to:(@convention(c)(AnyObject,Selector,Bool)->Void).self)
    let block:@convention(block)(AnyObject,Bool)->Void={object,animations in call(object,legacy,isSystem(object) ? false : animations)}
    let replacement=imp_implementationWithBlock(block)
    method_setImplementation(method,replacement)
    return {method_setImplementation(method,original);_ = imp_removeBlock(replacement)}
  }

  private func scrollTo(_ element:XCUIElement,in host:XCUIApplication) {
    let scroll=host.scrollViews["share-words-scroll"]
    for _ in 0..<12 {
      if element.isHittable {Thread.sleep(forTimeInterval:0.6);return}
      let up = !(element.exists && element.frame.minY < scroll.frame.minY)
      scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:up ? 0.8 : 0.25)).press(forDuration:0.1,thenDragTo:scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:up ? 0.25 : 0.8)),withVelocity:.slow,thenHoldForDuration:0.5)
    }
    XCTAssertTrue(element.isHittable,host.debugDescription)
  }

  func testAutomaticPreviewAndIsland() throws {
    try requirePhysicalDevice()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    app.launchEnvironment["LINGFER_LIVE_QA"]="1";app.launchArguments=["--lingfer-live-qa"]
    app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30),app.debugDescription)
    button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:15),app.debugDescription)
    app.buttons["live-start"].tap()
    XCTAssertTrue(system.buttons["共享整个屏幕"].waitForExistence(timeout:12),system.debugDescription)
    screenshot("ios-island-before-screen-sharing")
    system.buttons["共享整个屏幕"].tap()
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15),app.debugDescription)
    defer {
      app.activate()
      if app.buttons["live-stop"].exists {app.buttons["live-stop"].tap()}
    }
    XCUIDevice.shared.press(.home);safari.activate()
    Thread.sleep(forTimeInterval:6)
    screenshot("ios-auto-floating-translation")
    app.activate()
    XCTAssertTrue(app.staticTexts["live-pip-active"].waitForExistence(timeout:10),app.debugDescription)
    XCTAssertTrue(app.staticTexts["live-island-active"].waitForExistence(timeout:10),app.debugDescription)
    screenshot("ios-auto-preview-island-status")
    safari.activate()
    system.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.03)).press(forDuration:1.5)
    screenshot("ios-island-after-long-press")
    let pause=system.buttons["island-pause"]
    if !pause.waitForExistence(timeout:2) {
      // System screen-sharing may take priority in the island. Its Live Activity
      // should remain available on the Lock Screen/Notification Center.
      system.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.002)).press(forDuration:0.1,thenDragTo:system.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.7)))
    }
    if !pause.waitForExistence(timeout:2) {
      XCUIDevice.shared.press(.home)
      system.windows.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.002)).press(forDuration:0.1,thenDragTo:system.windows.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.7)))
    }
    let activityPermission=system.staticTexts.matching(NSPredicate(format:"label CONTAINS '允许语渡的实时活动' OR label CONTAINS 'Allow Live Activities'")).firstMatch
    if activityPermission.waitForExistence(timeout:2) {
      for name in ["始终允许","允许","Always Allow","Allow"] where system.buttons[name].exists {
        system.buttons[name].tap();break
      }
    }
    XCTAssertTrue(pause.waitForExistence(timeout:8),system.debugDescription)
    screenshot("ios-island-expanded")
    pause.tap()
    Thread.sleep(forTimeInterval:2)
    screenshot("ios-island-paused")
    // Verify the intent changed the live session, not just the widget label.
    app.activate()
    XCTAssertTrue(app.buttons["live-pause"].label.contains("继续"),app.debugDescription)
    app.buttons["share-original-tab"].tap()
    XCTAssertFalse(app.staticTexts["share-original-text"].label.contains("语渡随屏阅读"))
    app.buttons["live-pause"].tap()
    safari.activate()
    Thread.sleep(forTimeInterval:2)
    screenshot("ios-island-authorized-compact")
    system.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.03)).press(forDuration:1.5)
    if !system.buttons["island-stop"].waitForExistence(timeout:2) {
      system.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.002)).press(forDuration:0.1,thenDragTo:system.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.7)))
    }
    XCTAssertTrue(system.buttons["island-stop"].waitForExistence(timeout:8),system.debugDescription)
    system.buttons["island-stop"].tap()
    Thread.sleep(forTimeInterval:2)
    screenshot("ios-island-stopped")
    app.activate()
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10),app.debugDescription)
    XCTAssertFalse(app.staticTexts["live-pip-active"].exists)
    screenshot("ios-island-stop-released-session")
  }

  func testLiveCapturePermissionProbe() throws {
    app.launch()
    let start=button("开启随屏阅读")
    XCTAssertTrue(start.waitForExistence(timeout:30),app.debugDescription)
    start.tap()
    let disclosure=button("了解，继续")
    if disclosure.waitForExistence(timeout:3) {disclosure.tap()}
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:20),app.debugDescription)
    screenshot("ios-live-reader-ready")
    app.buttons["live-start"].tap()
    Thread.sleep(forTimeInterval:2)
    screenshot("ios-live-system-picker")
    print("LIVE_APP\n"+app.debugDescription)
    print("LIVE_SYSTEM\n"+XCUIApplication(bundleIdentifier:"com.apple.springboard").debugDescription)
  }

  func testLiveCaptureOnDevice() throws {
    try requirePhysicalDevice()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    safari.terminate();safari.launch()
    if safari.buttons["ReloadButton"].isHittable {safari.buttons["ReloadButton"].tap()}
    app.launchEnvironment["LINGFER_LIVE_QA"]="1";app.launchArguments=["--lingfer-live-qa"]
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    let oldPicker=system.staticTexts.matching(NSPredicate(format:"label BEGINSWITH '屏幕上包括通知在内的所有内容'")).firstMatch
    if oldPicker.exists {oldPicker.tap()}
    app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30),app.debugDescription)
    button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:15),app.debugDescription)
    app.buttons["live-start"].tap()
    let share=system.buttons["共享整个屏幕"]
    XCTAssertTrue(share.waitForExistence(timeout:10),system.debugDescription)
    share.tap()
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15),app.debugDescription)
    defer {
      app.activate()
      if app.buttons["live-stop"].exists {app.buttons["live-stop"].tap()}
    }
    // The system sharing control remains above our app after authorization.
    // Leave that control before interacting with the app underneath it.
    XCUIDevice.shared.press(.home)
    XCUIApplication(bundleIdentifier:"com.apple.mobilesafari").activate()
    Thread.sleep(forTimeInterval:4)
    app.activate()
    Thread.sleep(forTimeInterval:2)
    screenshot("ios-live-started-device")
    app.buttons["share-original-tab"].tap()
    let initialOriginal=app.staticTexts["share-original-text"]
    XCTAssertTrue(initialOriginal.waitForExistence(timeout:10),app.debugDescription)
    XCTAssertTrue(initialOriginal.label.contains("Researchers maintain") || initialOriginal.label.contains("evidence reveals"),initialOriginal.label)
    let firstText=initialOriginal.label
    let firstIsA=firstText.contains("Researchers maintain")
    app.buttons["share-words-tab"].tap()
    let bookmark=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'share-save-'")).firstMatch
    XCTAssertTrue(bookmark.waitForExistence(timeout:10),app.debugDescription)
    let savedWord=String(bookmark.identifier.dropFirst("share-save-".count))
    scrollTo(bookmark,in:app)
    bookmark.tap()
    XCTAssertTrue(app.staticTexts["已同步到语渡生词本"].waitForExistence(timeout:5),app.debugDescription)
    Thread.sleep(forTimeInterval:1)
    app.buttons["live-pip"].tap()
    let pipReady=app.staticTexts["live-pip-active"]
    XCTAssertTrue(pipReady.waitForExistence(timeout:8),app.debugDescription)
    screenshot("ios-live-pip-started-device")
    XCUIApplication(bundleIdentifier:"com.apple.mobilesafari").activate()
    Thread.sleep(forTimeInterval:5)
    screenshot("ios-live-background-preview-device")
    app.activate()
    XCTAssertTrue(app.buttons["live-stop"].waitForExistence(timeout:15),app.debugDescription)
    app.buttons["share-original-tab"].tap()
    let original=app.staticTexts["share-original-text"]
    XCTAssertTrue(original.waitForExistence(timeout:15),app.debugDescription)
    let otherPage=firstIsA ? "evidence reveals" : "Researchers maintain"
    for _ in 0..<5 where !original.label.contains(otherPage) {
      safari.activate();Thread.sleep(forTimeInterval:5);app.activate()
    }
    XCTAssertTrue(original.label.contains(otherPage),original.label)
    XCTAssertFalse(original.label.contains("LINGFER LIVE"),original.label)
    print("LIVE_CAPTURE_RESULT\n"+app.debugDescription)
    screenshot("ios-live-captured-original-device")
    app.buttons["live-stop"].tap()
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10),app.debugDescription)
    screenshot("ios-live-stopped-device")
    app.buttons["share-done"].tap()
    Thread.sleep(forTimeInterval:2)
    screenshot("ios-live-returned-home-device")
    // Personal-device notification banners can cover this header. Let them
    // retract and restore our app if an external system surface took focus.
    app.activate();Thread.sleep(forTimeInterval:6)
    button("生词本").tap()
    XCTAssertTrue(button("开始复习").waitForExistence(timeout:10),app.debugDescription)
    XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@",savedWord)).firstMatch.waitForExistence(timeout:5),app.debugDescription)
    screenshot("ios-live-saved-in-app-device")
  }

  func testShareRecordSurvivesRelaunch() throws {
    try requirePhysicalDevice()
    app.launch()
    XCTAssertTrue(button("设置").waitForExistence(timeout:25),app.debugDescription)
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    safari.terminate();safari.launch()
    let share=safari.buttons.matching(NSPredicate(format:"identifier == 'ShareButton' OR label == '分享' OR label == '共享' OR label == 'Share'")).firstMatch
    if !share.waitForExistence(timeout:2) {safari.buttons["MoreMenuButton"].tap()}
    XCTAssertTrue(share.waitForExistence(timeout:10),safari.debugDescription)
    share.tap()
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    let names=NSPredicate(format:"label == '语渡' OR label == '语渡阅读'")
    let systemReader=system.descendants(matching:.any).matching(names).firstMatch
    let safariReader=safari.descendants(matching:.any).matching(names).firstMatch
    if !systemReader.waitForExistence(timeout:2) && !safariReader.exists {
      for surface in [safari,system] {
        let row=surface.collectionViews["activityCollectionView"].scrollViews.allElementsBoundByIndex.first(where:{$0.cells.matching(identifier:"shareCell").count>0}) ?? surface.collectionViews["activityCollectionView"].scrollViews.firstMatch
        if !row.exists {continue}
        for _ in 0..<12 {
          if systemReader.isHittable || safariReader.isHittable {break}
          let more=row.cells.matching(NSPredicate(format:"label == '更多' OR label == 'More'")).firstMatch
          if more.isHittable {more.tap();break}
          row.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5)).press(forDuration:0.1,thenDragTo:row.coordinate(withNormalizedOffset:CGVector(dx:0.15,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.3)
        }
      }
    }
    for surface in [safari,system] {
      let list=surface.tables["tableView"]
      if !list.isHittable {continue}
      for _ in 0..<18 {
        if systemReader.isHittable || safariReader.isHittable {break}
        list.swipeUp()
      }
    }
    let reader=systemReader.isHittable ? systemReader : safariReader
    XCTAssertTrue(reader.waitForExistence(timeout:10),safari.debugDescription)
    reader.tap()
    let ready=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in safari.buttons["share-done"].exists || system.buttons["share-done"].exists},object:nil)
    XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:25),.completed)
    let host=safari.buttons["share-done"].exists ? safari : system
    host.buttons["share-original-tab"].tap()
    let text=host.staticTexts["share-original-text"]
    XCTAssertTrue(text.waitForExistence(timeout:15),host.debugDescription)
    XCTAssertFalse(text.label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,text.label)
    let originalProbe=String(text.label.components(separatedBy:"\n").first(where:{!$0.isEmpty})!.prefix(30))
    host.buttons["share-mode"].tap()
    let translate=host.buttons["整页对照"].exists ? host.buttons["整页对照"] : system.buttons["整页对照"]
    XCTAssertTrue(translate.waitForExistence(timeout:5),host.debugDescription);translate.tap()
    let complete=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in
      host.scrollViews["share-page-scroll"].exists && !host.progressIndicators.firstMatch.exists &&
      !host.buttons["share-page-retry"].exists && !host.staticTexts["尚未翻译"].exists
    },object:nil)
    XCTAssertEqual(XCTWaiter.wait(for:[complete],timeout:60),.completed,host.debugDescription)
    screenshot("ios-share-page-translation-device")
    host.buttons["share-mode"].tap()
    let learn=host.buttons["学习辅助"].exists ? host.buttons["学习辅助"] : system.buttons["学习辅助"]
    XCTAssertTrue(learn.waitForExistence(timeout:5),host.debugDescription);learn.tap()
    host.buttons["share-done"].tap()
    app.terminate();app.launch()
    let resume=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS '继续阅读'")).firstMatch
    XCTAssertTrue(resume.waitForExistence(timeout:20),app.debugDescription)
    for _ in 0..<5 {if resume.isHittable {break};app.swipeUp()}
    resume.tap()
    XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@",originalProbe,originalProbe)).firstMatch.waitForExistence(timeout:15),app.debugDescription)
    screenshot("ios-share-record-after-relaunch")
  }

  func testScreenshotReading() throws {
    app.launch()
    let start = button("选择截图")
    XCTAssertTrue(start.waitForExistence(timeout: 25))
    start.tap()
    let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 20), app.debugDescription)
    photo.tap()
    XCTAssertTrue(button("原图阅读").waitForExistence(timeout: 25), app.debugDescription)
    let marker = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'maintain' AND label CONTAINS '查看详解'")).firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 25), app.debugDescription)
    screenshot("ios-anchored-original")
    marker.tap()
    XCTAssertTrue(button("关闭详解").waitForExistence(timeout: 10), app.debugDescription)
    let answer = app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS '认为' OR value CONTAINS '主张' OR label CONTAINS '认为' OR label CONTAINS '主张'")).firstMatch
    XCTAssertTrue(answer.waitForExistence(timeout: 40), app.debugDescription)
    XCTAssertFalse(button("重试详解").exists, app.debugDescription)
    screenshot("ios-anchored-detail")
    button("关闭详解").tap()
    button("语言与自动更新").tap()
    XCTAssertTrue(button("语言与阅读方式").waitForExistence(timeout: 5), app.debugDescription)
    screenshot("ios-language-preferences")
    button("关闭语言设置").tap()
  }

  func testNativeShareLayout() throws {
    app.launch()
    XCTAssertTrue(button("阅读").waitForExistence(timeout: 25))
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    safari.activate()
    screenshot("ios-safari-before-share", of: safari)
    print("SAFARI_STATE\n" + safari.debugDescription)
    let share = safari.buttons.matching(NSPredicate(format: "identifier == 'ShareButton' OR label == '分享' OR label == '共享' OR label == 'Share'")).firstMatch
    if !share.waitForExistence(timeout: 2) {
      let menu = safari.buttons["MoreMenuButton"]
      XCTAssertTrue(menu.exists, safari.debugDescription)
      menu.tap()
    }
    XCTAssertTrue(share.waitForExistence(timeout: 15), safari.debugDescription)
    share.tap()
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let predicate = NSPredicate(format: "label == '语渡' OR label == '语渡阅读'")
    let systemReader = system.descendants(matching: .any).matching(predicate).firstMatch
    let safariReader = safari.descendants(matching: .any).matching(predicate).firstMatch
    if !systemReader.waitForExistence(timeout:2) && !safariReader.exists {
      for surface in [safari,system] {
        let row=surface.collectionViews["activityCollectionView"].scrollViews.firstMatch
        if !row.exists {continue}
        for _ in 0..<8 {
          if systemReader.isHittable || safariReader.isHittable {break}
          row.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5)).press(forDuration:0.1,thenDragTo:row.coordinate(withNormalizedOffset:CGVector(dx:0.15,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.5)
        }
      }
    }
    let reader = systemReader.isHittable ? systemReader : safariReader
    XCTAssertTrue(reader.waitForExistence(timeout: 5), "SAFARI\n" + safari.debugDescription + "\nSYSTEM\n" + system.debugDescription)
    reader.tap()
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      safari.buttons["share-done"].exists || system.buttons["share-done"].exists
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 40), .completed,
      "SAFARI\n" + safari.debugDescription + "\nSYSTEM\n" + system.debugDescription)
    let host = safari.buttons["share-done"].exists ? safari : system
    XCTAssertTrue(host.buttons["share-scope-summary"].isHittable,host.debugDescription)
    screenshot("native-ios-portrait",of:host)
    XCUIDevice.shared.orientation = .landscapeLeft
    Thread.sleep(forTimeInterval:1)
    XCTAssertTrue(host.buttons["share-done"].isHittable,host.debugDescription)
        if host.buttons["share-original-tab"].exists {
      host.buttons["share-original-tab"].tap()
    }
    XCTAssertTrue(host.staticTexts["share-original-text"].exists,host.debugDescription)
    XCTAssertGreaterThan(host.scrollViews["share-original-scroll"].frame.height,80,host.debugDescription)
    screenshot("native-ios-landscape",of:host)
    XCUIDevice.shared.orientation = .portrait
    Thread.sleep(forTimeInterval:1)
    if host.buttons["share-words-tab"].exists {host.buttons["share-words-tab"].tap()}
    if host.buttons["share-language-summary"].exists {host.buttons["share-language-summary"].tap();Thread.sleep(forTimeInterval:0.8)}
    host.buttons["share-source-language"].tap()
    XCTAssertTrue(host.buttons["自动识别"].waitForExistence(timeout:8),host.debugDescription)
    host.buttons["自动识别"].tap()
    host.buttons["share-target-language"].tap()
    XCTAssertTrue(host.buttons["英语"].waitForExistence(timeout:8),host.debugDescription)
    host.buttons["英语"].tap()
    if host.buttons["share-language-done"].exists {host.buttons["share-language-done"].tap()}
    let empty=host.staticTexts["当前范围没有匹配词"]
    XCTAssertTrue(empty.waitForExistence(timeout:8),host.debugDescription)
    screenshot("native-ios-empty",of:host)
    host.buttons["share-original-tab"].tap()
    XCTAssertTrue(host.staticTexts["share-original-text"].exists,host.debugDescription)
    if host.buttons["share-language-summary"].exists {host.buttons["share-language-summary"].tap();Thread.sleep(forTimeInterval:0.8)}
    host.buttons["share-target-language"].tap()
    XCTAssertTrue(host.buttons["中文"].waitForExistence(timeout:8),host.debugDescription)
    host.buttons["中文"].tap()
    host.buttons["share-source-language"].tap()
    XCTAssertTrue(host.buttons["英语"].waitForExistence(timeout:8),host.debugDescription)
    host.buttons["英语"].tap()
    if host.buttons["share-language-done"].exists {host.buttons["share-language-done"].tap()}
    host.buttons["share-done"].tap()
  }

  func testSafariShare() throws {
    app.launch()
    XCTAssertTrue(button("选择截图").waitForExistence(timeout: 25))
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    safari.activate()
    screenshot("ios-safari-before-share", of: safari)
    print("SAFARI_STATE\n" + safari.debugDescription)
    let share = safari.buttons.matching(NSPredicate(format: "identifier == 'ShareButton' OR label == '分享' OR label == '共享' OR label == 'Share'")).firstMatch
    if !share.waitForExistence(timeout: 2) {
      let menu = safari.buttons["MoreMenuButton"]
      XCTAssertTrue(menu.exists, safari.debugDescription)
      menu.tap()
    }
    XCTAssertTrue(share.waitForExistence(timeout: 15), safari.debugDescription)
    share.tap()
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let predicate = NSPredicate(format: "label == '语渡' OR label == '语渡阅读'")
    let systemReader = system.descendants(matching: .any).matching(predicate).firstMatch
    let safariReader = safari.descendants(matching: .any).matching(predicate).firstMatch
    if !systemReader.waitForExistence(timeout:2) && !safariReader.exists {
      for surface in [safari,system] {
        let row=surface.collectionViews["activityCollectionView"].scrollViews.firstMatch
        if !row.exists {continue}
        for _ in 0..<8 {
          if systemReader.isHittable || safariReader.isHittable {break}
          row.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5)).press(forDuration:0.1,thenDragTo:row.coordinate(withNormalizedOffset:CGVector(dx:0.15,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.5)
        }
      }
    }
    let reader = systemReader.isHittable ? systemReader : safariReader
    XCTAssertTrue(reader.waitForExistence(timeout: 5), "SAFARI\n" + safari.debugDescription + "\nSYSTEM\n" + system.debugDescription)
    reader.tap()
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      safari.buttons["share-done"].exists || system.buttons["share-done"].exists
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 40), .completed,
      "SAFARI\n" + safari.debugDescription + "\nSYSTEM\n" + system.debugDescription)
    let host = safari.buttons["share-done"].exists ? safari : system
    XCTAssertTrue(host.staticTexts["maintain"].waitForExistence(timeout: 10), host.debugDescription)
    screenshot("ios-share-words", of: host)
    host.buttons["share-scope-summary"].tap()
    XCTAssertTrue(host.buttons["share-level-cet4"].waitForExistence(timeout:5),host.debugDescription)
    screenshot("native-ios-learning-range", of:host)
    host.buttons["share-level-cet4"].tap()
    host.buttons["share-original-tab"].tap()
    XCTAssertTrue(host.staticTexts["share-original-text"].exists,host.debugDescription)
    screenshot("native-ios-original", of:host)
    host.buttons["share-words-tab"].tap()
    let save = host.buttons["share-save-effective"]
    scrollTo(save,in:host)
    if save.isEnabled {
      save.tap()
      XCTAssertTrue(host.staticTexts.matching(NSPredicate(format: "label CONTAINS '已同步到语渡生词本'")).firstMatch.waitForExistence(timeout: 5), host.debugDescription)
    } else {XCTAssertEqual(save.label,"已收藏")}
    scrollTo(host.buttons["share-explain-maintain"],in:host)
    host.buttons["share-explain-maintain"].tap()
    screenshot("native-ios-ai-loading",of:host)
    let explanation = host.staticTexts["share-answer"]
    expectation(for: NSPredicate(format: "label CONTAINS '认为' OR label CONTAINS '主张'"), evaluatedWith: explanation)
    waitForExpectations(timeout: 35)
    screenshot("ios-share-explanation", of: host)
    host.buttons["share-retry-explanation"].tap()
    XCTAssertTrue(host.staticTexts["maintain"].exists,host.debugDescription)
    XCTAssertTrue(host.buttons["share-detail-save"].exists,host.debugDescription)
    XCTAssertTrue(host.staticTexts["share-answer"].waitForExistence(timeout:35),host.debugDescription)
    screenshot("native-ios-ai-retry",of:host)
    host.buttons["关闭"].tap()
    let known=host.buttons["share-known-occasional"]
    scrollTo(known,in:host);known.tap()
    XCTAssertFalse(host.buttons["share-known-occasional"].exists,host.debugDescription)
    screenshot("native-ios-known-excluded",of:host)
    host.buttons["完成"].tap()
    app.activate()
    button("生词本").tap()
    if !app.staticTexts.matching(NSPredicate(format: "label CONTAINS '已收藏'")).firstMatch.waitForExistence(timeout: 2) {
      button("生词本").tap()
    }
    XCTAssertTrue(app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "effective\n")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    screenshot("ios-share-synced")
  }

  func testChineseShareVocabulary() throws {
    app.launch()
    XCTAssertTrue(button("选择截图").waitForExistence(timeout: 25))
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    safari.activate()
    screenshot("ios-safari-before-share", of: safari)
    print("SAFARI_STATE\n" + safari.debugDescription)
    let share = safari.buttons.matching(NSPredicate(format: "identifier == 'ShareButton' OR label == '分享' OR label == '共享' OR label == 'Share'")).firstMatch
    if !share.waitForExistence(timeout: 2) {
      let menu = safari.buttons["MoreMenuButton"]
      XCTAssertTrue(menu.exists, safari.debugDescription)
      menu.tap()
    }
    XCTAssertTrue(share.waitForExistence(timeout: 15), safari.debugDescription)
    share.tap()
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let predicate = NSPredicate(format: "label == '语渡' OR label == '语渡阅读'")
    let systemReader = system.descendants(matching: .any).matching(predicate).firstMatch
    let safariReader = safari.descendants(matching: .any).matching(predicate).firstMatch
    if !systemReader.waitForExistence(timeout:2) && !safariReader.exists {
      for surface in [safari,system] {
        let row=surface.collectionViews["activityCollectionView"].scrollViews.firstMatch
        if !row.exists {continue}
        for _ in 0..<8 {
          if systemReader.isHittable || safariReader.isHittable {break}
          row.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5)).press(forDuration:0.1,thenDragTo:row.coordinate(withNormalizedOffset:CGVector(dx:0.15,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.5)
        }
      }
    }
    let reader = systemReader.isHittable ? systemReader : safariReader
    XCTAssertTrue(reader.waitForExistence(timeout: 5), "SAFARI\n" + safari.debugDescription + "\nSYSTEM\n" + system.debugDescription)
    reader.tap()
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      safari.buttons["share-done"].exists || system.buttons["share-done"].exists
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 40), .completed,
      "SAFARI\n" + safari.debugDescription + "\nSYSTEM\n" + system.debugDescription)
    let host = safari.buttons["share-done"].exists ? safari : system
    host.buttons["share-source-language"].tap()
    host.buttons["中文"].tap()
    let explain = host.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'share-explain-'")).firstMatch
    XCTAssertTrue(explain.waitForExistence(timeout: 35), host.debugDescription)
    let studyWord = String(explain.identifier.dropFirst("share-explain-".count))
    XCTAssertTrue(host.staticTexts[studyWord].exists, host.debugDescription)
    screenshot("ios-chinese-english-share", of: host)
    scrollTo(explain,in:host)
    explain.tap()
    XCTAssertTrue(host.staticTexts["share-answer"].waitForExistence(timeout: 35), host.debugDescription)
    screenshot("ios-chinese-english-detail", of: host)
    host.buttons["关闭"].tap()
    host.buttons["share-source-language"].tap()
    host.buttons["自动识别"].tap()
    host.buttons["share-target-language"].tap()
    host.buttons["中文"].tap()
    host.buttons["完成"].tap()
  }

  // UI redesign review: real app rendering, OCR and the existing AI service.
  func testUIDesignReview() throws {
    app.launch()
    XCTAssertTrue(button("选择截图").waitForExistence(timeout: 25), app.debugDescription)
    screenshot("ui-ios-home")
    if button("自动识别 → 中文").exists {
      button("自动识别 → 中文").tap()
      button("原文语言").tap()
      button("英语").tap()
      button("关闭语言设置").tap()
    }
    button("学习范围").tap()
    XCTAssertTrue(button("选择学习范围").waitForExistence(timeout: 5), app.debugDescription)
    screenshot("ui-ios-levels")
    button("关闭").tap()
    button("选择截图").tap()
    let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 20), app.debugDescription)
    photo.tap()
    XCTAssertTrue(button("原图阅读").waitForExistence(timeout: 25), app.debugDescription)
    let marker = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'maintain' AND label CONTAINS '查看详解'")).firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 25), app.debugDescription)
    screenshot("ui-ios-original-annotations")
    marker.tap()
    XCTAssertTrue(button("关闭详解").waitForExistence(timeout: 5), app.debugDescription)
    let answer = app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS '认为' OR value CONTAINS '主张' OR label CONTAINS '认为' OR label CONTAINS '主张'")).firstMatch
    XCTAssertTrue(answer.waitForExistence(timeout: 40), app.debugDescription)
    screenshot("ui-ios-explanation")
    button("关闭详解").tap()
    let back = app.buttons.matching(NSPredicate(format: "label == '返回' OR label == 'Back'")).firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
    back.tap()
    button("生词本").tap()
    screenshot("ui-ios-saved-words")
    button("设置").tap()
    screenshot("ui-ios-settings")
  }

  // Visual review only: preserve the current reading preferences and content.
  func testAppleGlassReview() throws {
    func capture(_ name: String) {
      Thread.sleep(forTimeInterval: 0.4)
      screenshot(name)
    }
    app.launch()
    XCTAssertTrue(button("粘贴文字").waitForExistence(timeout: 25), app.debugDescription)
    Thread.sleep(forTimeInterval: 0.4)
    capture("apple-ios-home")
    let scope = button("学习范围")
    for _ in 0..<5 {
      if scope.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(scope.isHittable, app.debugDescription)
    scope.tap()
    let levels = button("选择学习范围")
    if levels.waitForExistence(timeout: 2) {
      capture("apple-ios-levels")
      button("关闭").tap()
    } else {
      XCTAssertTrue(button("关闭语言设置").exists, app.debugDescription)
      capture("apple-ios-language")
      button("关闭语言设置").tap()
    }
    for _ in 0..<3 { app.swipeDown() }
    button("粘贴文字").tap()
    XCTAssertTrue(button("开始阅读").waitForExistence(timeout: 5), app.debugDescription)
    capture("apple-ios-text-input")
    button("关闭").tap()
    let sample = button("试读一段")
    for _ in 0..<6 {
      if sample.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(sample.isHittable, app.debugDescription)
    sample.tap()
    XCTAssertTrue(button("词卡").waitForExistence(timeout: 15), app.debugDescription)
    capture("apple-ios-reading")
    button("词卡").tap()
    let explain = app.buttons["语境讲解"].firstMatch
    XCTAssertTrue(explain.waitForExistence(timeout: 8), app.debugDescription)
    expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: explain)
    waitForExpectations(timeout: 8)
    Thread.sleep(forTimeInterval: 0.6)
    capture("apple-ios-word-cards")
    explain.tap()
    XCTAssertTrue(button("关闭").waitForExistence(timeout: 5))
    let pending = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '正在结合原文讲解' OR value CONTAINS '正在结合原文讲解'")).firstMatch
    if pending.waitForExistence(timeout: 1) {
      expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pending)
      waitForExpectations(timeout: 35)
    }
    capture("apple-ios-explanation")
    button("关闭").tap()
    let back = app.buttons.matching(NSPredicate(format: "label == '返回' OR label == 'Back'")).firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 5))
    back.tap()
    button("生词本").tap()
    Thread.sleep(forTimeInterval: 0.4)
    capture("apple-ios-saved-words")
    app.buttons.matching(NSPredicate(format: "label == '返回' OR label == 'Back'")).firstMatch.tap()
    button("设置").tap()
    Thread.sleep(forTimeInterval: 0.4)
    capture("apple-ios-settings")
  }
  func testContextualAutomaticPreview() throws {
    try requirePhysicalDevice()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    func visibleVideoText()->[(String,CGRect)] {
      guard let image=XCUIScreen.main.screenshot().image.cgImage else{return []}
      let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
      try? VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
      return request.results?.compactMap { result in result.topCandidates(1).first.map{($0.string,result.boundingBox)} } ?? []
    }
    app.launchEnvironment["LINGFER_LIVE_QA"]="1";app.launchArguments=["--lingfer-live-qa"]
    app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30),app.debugDescription)
    button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    app.buttons["live-start"].tap()
    XCTAssertTrue(system.buttons["共享整个屏幕"].waitForExistence(timeout:12),system.debugDescription)
    system.buttons["共享整个屏幕"].tap()
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15),app.debugDescription)
    defer {
      app.activate()
      if !app.buttons["live-stop"].exists,!app.buttons["live-start"].exists,button("开启随屏阅读").isHittable {button("开启随屏阅读").tap()}
      if app.buttons["live-stop"].exists {app.buttons["live-stop"].tap()}
    }
    XCUIDevice.shared.press(.home);safari.activate()
    Thread.sleep(forTimeInterval:6)
    screenshot("ios-context-floating-original")
    // AVKit keeps the PiP above our app too. At its default upper-right
    // position it covers the native pause button; move the visible window as
    // a reader would, then settle OCR at that position before comparing pages.
    let marker=visibleVideoText().first{$0.0.uppercased().contains("LINGFER LIVE")}
    XCTAssertNotNil(marker,"Locate the actual video; AVKit remembers its last corner")
    if let marker,marker.1.midY>0.5 {
      let position=CGVector(dx:marker.1.midX,dy:1-marker.1.midY)
      system.coordinate(withNormalizedOffset:position).press(forDuration:0.15,thenDragTo:system.coordinate(withNormalizedOffset:CGVector(dx:0.7,dy:0.75)),withVelocity:.slow,thenHoldForDuration:0.5)
    }
    Thread.sleep(forTimeInterval:5)
    screenshot("ios-context-floating-after-moving")
    app.activate()
    let debug=app.staticTexts["live-preview-debug"]
    XCTAssertTrue(debug.waitForExistence(timeout:10),app.debugDescription)
    XCTAssertTrue(debug.label.contains("highlight=true"),debug.label)
    XCTAssertTrue(app.staticTexts["live-pip-active"].exists,app.debugDescription)
    app.buttons["share-original-tab"].tap()
    let original=app.staticTexts["share-original-text"]
    XCTAssertTrue(original.waitForExistence(timeout:8),app.debugDescription)
    XCTAssertTrue(original.label.contains("innovative approach"),original.label)
    XCTAssertFalse(original.label.contains("LINGFER LIVE"),original.label)
    let text=original.label
    func field(_ name:String)->String {
      debug.label.components(separatedBy:name+"=").dropFirst().first?.components(separatedBy:" ").first ?? "missing"
    }
    app.buttons["live-pause"].tap()
    Thread.sleep(forTimeInterval:1)
    XCTAssertTrue(app.buttons["live-pause"].label.contains("继续"),app.debugDescription)
    screenshot("ios-context-paused-in-app")
    let frozen=debug.label.components(separatedBy:"context=").last
    let focus=field("focus")
    safari.activate();Thread.sleep(forTimeInterval:11)
    screenshot("ios-context-paused-original")
    app.activate()
    XCTAssertTrue(app.buttons["live-pause"].label.contains("继续"),app.debugDescription)
    XCTAssertEqual(field("focus"),focus,debug.label)
    XCTAssertEqual(debug.label.components(separatedBy:"context=").last,frozen)
    app.buttons["live-pause"].tap()
    safari.activate();Thread.sleep(forTimeInterval:14)
    // Video words are pixels, not accessible UI controls. Keep the actual
    // frozen and resumed screenshots for visual comparison rather than
    // asserting OCR's interpretation of a tiny counter under AVKit controls.
    screenshot("ios-context-next-highlight")
    app.activate()
    XCTAssertTrue(debug.label.contains("highlight=true"),debug.label)
    XCTAssertEqual(original.label,text,"Rotating the preview must not ingest its own translated video")
    app.buttons["live-stop"].tap()
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10),app.debugDescription)
  }

  func testStableReadingAndTranslation() throws {
    try requirePhysicalDevice()
    restoreSystemSynchronization=avoidSystemAnimationWait()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    var videoBounds:CGRect?
    func videoText()->[(String,CGRect)] {
      guard let image=XCUIScreen.main.screenshot().image.cgImage else{return []}
      let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.minimumTextHeight=0.003
      try? VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
      let values=request.results?.compactMap{v in v.topCandidates(1).first.map{($0.string,v.boundingBox)}} ?? []
      if let marker=values.first(where:{$0.0.uppercased().replacingOccurrences(of:" ",with:"").contains("LINGFER")}) {
        let titleWidth=(marker.0.uppercased() as NSString).size(withAttributes:[.font:UIFont.systemFont(ofSize:26,weight:.semibold)]).width
        let width=marker.1.width*800/max(1,titleWidth)
        let height=width*CGFloat(image.width)/CGFloat(image.height)*500/800
        let top=marker.1.maxY+height*20/500
        videoBounds=CGRect(x:marker.1.minX-width*225/800,y:top-height,width:width,height:height)
      }
      return values
    }
    app.launchEnvironment["LINGFER_LIVE_QA"]="1";app.launchArguments=["--lingfer-live-qa"];app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30))
    button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:15),app.debugDescription)
    app.buttons["live-display-floating"].tap()
    app.buttons["live-start"].tap()
    XCTAssertTrue(system.buttons["共享整个屏幕"].waitForExistence(timeout:12))
    system.buttons["共享整个屏幕"].tap()
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15))
    let initialMode=app.buttons["share-mode"].label
    defer {
      XCUIDevice.shared.orientation = .portrait;app.terminate()
    }
    XCUIDevice.shared.press(.home);safari.activate();Thread.sleep(forTimeInterval:7)
    if let marker=videoText().first(where:{$0.0.uppercased().replacingOccurrences(of:" ",with:"").contains("LINGFER")}),marker.1.midY>0.5 {
      system.coordinate(withNormalizedOffset:CGVector(dx:marker.1.midX,dy:1-marker.1.midY)).press(forDuration:0.15,thenDragTo:system.coordinate(withNormalizedOffset:CGVector(dx:0.70,dy:0.80)),withVelocity:.slow,thenHoldForDuration:0.5)
      Thread.sleep(forTimeInterval:4)
    }
    screenshot("stable-ios-highlight-and-location")
    app.activate()
    XCTAssertTrue(app.staticTexts["live-pip-inline"].waitForExistence(timeout:8))
    let originalLanguage=app.buttons["share-language-summary"].label.components(separatedBy:"→")
    let languages=["自动识别","中文","英语","日语","韩语","法语","德语","西班牙语","葡萄牙语","意大利语","印地语"]
    let originalSource=languages.first{originalLanguage.first?.contains($0) == true} ?? "自动识别"
    let originalTarget=languages.filter{$0 != "自动识别"}.first{originalLanguage.last?.contains($0) == true} ?? "中文"
    let levels=[("中考","zhongkao"),("高考","gaokao"),("四级","cet4"),("六级","cet6"),("考研","kaoyan"),("雅思","ielts"),("托福","toefl")]
    func setLanguages(_ source:String,_ target:String) {
      app.buttons["share-language-summary"].tap()
      app.buttons["share-source-language"].tap();app.buttons[source].firstMatch.tap()
      app.buttons["share-target-language"].tap();app.buttons[target].firstMatch.tap()
      app.buttons["share-language-done"].tap()
    }
    setLanguages("英语","中文")
    if !initialMode.contains("学习") {app.buttons["share-mode"].tap();app.buttons["学习辅助"].firstMatch.tap();Thread.sleep(forTimeInterval:1)}
    let originalScope=app.buttons["share-scope-summary"].label
    let originalLevel=levels.first{originalScope.contains($0.0)}?.1
    app.buttons["share-scope-summary"].tap();app.buttons["share-level-cet4"].tap()
    Thread.sleep(forTimeInterval:1)
    let debug=app.staticTexts["live-preview-debug"]
    XCTAssertTrue(debug.waitForExistence(timeout:10))
    XCTAssertTrue(debug.label.contains("highlight=true"),debug.label)
    func field(_ key:String)->String {debug.label.components(separatedBy:key+"=").dropFirst().first?.components(separatedBy:" ").first ?? "missing"}
    let first=field("focus")
    app.buttons["live-qa-next"].tap();Thread.sleep(forTimeInterval:0.5)
    XCTAssertNotEqual(field("focus"),first,debug.label)
    app.buttons["live-qa-previous"].tap();Thread.sleep(forTimeInterval:0.5)
    XCTAssertEqual(field("focus"),first,debug.label)
    let requests=field("requests")
    app.buttons["live-qa-recover"].tap();Thread.sleep(forTimeInterval:1)
    XCTAssertGreaterThan(Int(field("recoveries")) ?? 0,0)
    XCTAssertEqual(field("requests"),requests,"Redrawing must not request translation again")
    safari.activate();Thread.sleep(forTimeInterval:15)
    _=videoText()
    screenshot("stable-ios-background-recovered")
    safari.coordinate(withNormalizedOffset:CGVector(dx:0.18,dy:0.48)).press(forDuration:0.2,thenDragTo:safari.coordinate(withNormalizedOffset:CGVector(dx:0.18,dy:0.475)),withVelocity:.slow,thenHoldForDuration:0.5)
    Thread.sleep(forTimeInterval:4);app.activate()
    XCTAssertEqual(field("focus"),first,"A small scroll must keep the selected word")
    XCTAssertEqual(field("requests"),requests,"A small scroll must not re-request the same text")
    screenshot("stable-ios-small-scroll-keeps-anchor")
    let wordCount=field("words")
    // Live Activities are system-sized cards. Page using real AppIntents,
    // rather than assuming they support an arbitrary scrolling list.
    safari.activate()
    system.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.002)).press(forDuration:0.1,thenDragTo:system.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.72)))
    for name in ["始终允许","允许","Always Allow","Allow"] where system.buttons[name].exists {system.buttons[name].tap();break}
    let next=system.buttons["island-next"]
    XCTAssertTrue(next.waitForExistence(timeout:8),"Lingfer activity paging should be available in Notification Center")
    next.tap();Thread.sleep(forTimeInterval:1)
    let frame=next.frame
    if let image=XCUIScreen.main.screenshot().image.cgImage {
      let scale=CGFloat(image.width)/system.frame.width
      let area=CGRect(x:12,y:max(0,frame.minY-60),width:system.frame.width-24,height:104)
      if let cropped=image.cropping(to:CGRect(x:area.minX*scale,y:area.minY*scale,width:area.width*scale,height:area.height*scale)) {
        let attachment=XCTAttachment(image:UIImage(cgImage:cropped));attachment.name="stable-ios-activity-paging";attachment.lifetime = .keepAlways;add(attachment)
      }
    }
    app.activate();Thread.sleep(forTimeInterval:1)
    XCTAssertNotEqual(field("focus"),first,"The activity's Next intent must change the live session")
    XCTAssertEqual(field("words"),wordCount,"Opening our activity must not be read as a new one-word document")
    let oldContext=debug.label.components(separatedBy:"context=").last
    for _ in 0..<3 where debug.label.components(separatedBy:"context=").last==oldContext {
      safari.activate()
      safari.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.45)).tap()
      safari.coordinate(withNormalizedOffset:CGVector(dx:0.18,dy:0.80)).press(forDuration:0.05,thenDragTo:safari.coordinate(withNormalizedOffset:CGVector(dx:0.18,dy:0.30)),withVelocity:.slow,thenHoldForDuration:0.1)
      Thread.sleep(forTimeInterval:5);app.activate()
    }
    XCTAssertTrue(debug.label.contains("highlight=true"),debug.label)
    XCTAssertNotEqual(debug.label.components(separatedBy:"context=").last,oldContext,"A word leaving the reading region should move the anchor")
    screenshot("stable-ios-scroll-moves-anchor")
    // Actual existing AI service: verify complete-passage translation, not a
    // fabricated result. A service error must fail this integration check.
    app.buttons["share-mode"].tap();app.buttons["整页对照"].firstMatch.tap()
    let translated=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in debug.label.contains("context=translation|")},object:nil)
    XCTAssertEqual(XCTWaiter.wait(for:[translated],timeout:40),.completed,debug.label)
    screenshot("stable-ios-complete-passage-in-app")
    safari.activate();Thread.sleep(forTimeInterval:7)
    screenshot("stable-ios-multiline-page-translation")
    // Tiny video captions can fall below Vision's OCR threshold. Check the
    // actual video pixels using its last observed geometry, and retain the
    // screenshot for review; absence of OCR text alone is not a black frame.
    if let image=XCUIScreen.main.screenshot().image.cgImage,let bounds=videoBounds {
      let inside=bounds.insetBy(dx:bounds.width*0.2,dy:bounds.height*0.25)
      let area=CGRect(x:inside.minX*CGFloat(image.width),y:(1-inside.maxY)*CGFloat(image.height),width:inside.width*CGFloat(image.width),height:inside.height*CGFloat(image.height))
      if let crop=image.cropping(to:area) {
        var pixels=[UInt8](repeating:0,count:32*20*4)
        pixels.withUnsafeMutableBytes { bytes in
          let context=CGContext(data:bytes.baseAddress,width:32,height:20,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
          context.draw(crop,in:CGRect(x:0,y:0,width:32,height:20))
        }
        let brightness=pixels.enumerated().filter{$0.offset%4 != 3}.map{Double($0.element)}.reduce(0,+)/Double(32*20*3*255)
        XCTAssertGreaterThan(brightness,0.25,"Actual video content must not be black")
      } else {XCTFail("The previously observed video rectangle must remain on screen")}
    }
    app.activate()
    XCTAssertTrue(app.staticTexts["live-pip-inline"].exists)
    XCTAssertTrue(debug.label.contains("ready=true"),debug.label)
    let translationRequests=field("requests")
    app.buttons["live-qa-next"].tap();Thread.sleep(forTimeInterval:1)
    XCTAssertEqual(field("requests"),translationRequests,"Changing displayed translation page must use completed results")
    XCTAssertTrue(debug.label.contains("context=translation|"))
    if let originalLevel {
      app.buttons["share-mode"].tap();app.buttons["学习辅助"].firstMatch.tap()
      app.buttons["share-scope-summary"].tap();app.buttons["share-level-\(originalLevel)"].tap()
    }
    setLanguages(originalSource,originalTarget)
    if !initialMode.contains("学习") {app.buttons["share-mode"].tap();app.buttons["整页对照"].firstMatch.tap()}
    app.buttons["live-stop"].tap()
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10))
  }

  func testIslandAndFloatingTransitions() throws {
    guard #available(iOS 16.4, *) else {throw XCTSkip("System URL opening requires iOS 16.4")}
    try requirePhysicalDevice()
    restoreSystemSynchronization=avoidSystemAnimationWait()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    app.launchEnvironment["LINGFER_LIVE_QA"]="1";app.launchArguments=["--lingfer-live-qa"];app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30))
    button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:15))
    let options=app.buttons["live-reading-options"]
    options.tap()
    let originalMode=app.buttons["整页对照"].firstMatch.isSelected ? "整页对照" : "学习辅助"
    app.buttons["原文语言"].tap();app.buttons["英语"].firstMatch.tap()
    options.tap();app.buttons["译文语言"].tap();app.buttons["中文"].firstMatch.tap()
    app.buttons["live-mode-options"].tap();app.buttons["学习辅助"].firstMatch.tap()
    app.buttons["live-display-floating"].tap()
    app.buttons["live-start"].tap()
    XCTAssertTrue(system.buttons["共享整个屏幕"].waitForExistence(timeout:12))
    system.buttons["共享整个屏幕"].tap()
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15))
    defer {app.terminate()}
    safari.open(try fixtureURL("stable-scroll.html"));Thread.sleep(forTimeInterval:6)
    screenshot("island-ios-floating-before-return")
    // Locate the actual video rather than assuming AVKit's remembered corner.
    var anchor:(CGRect,Bool)?
    for _ in 0..<10 {
      guard let image=XCUIScreen.main.screenshot().image.cgImage else {return XCTFail("Missing screenshot")}
      let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.minimumTextHeight=0.003
      try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
      if let marker=request.results?.first(where:{($0.topCandidates(1).first?.string.uppercased().replacingOccurrences(of:" ",with:"") ?? "").contains("LINGFERLIVE")}) {anchor=(marker.boundingBox,false);break}
      if let footer=request.results?.first(where:{v in let t=v.topCandidates(1).first?.string ?? "";return t.contains("随阅读位置更新") || t.contains("前后按钮切换")}) {anchor=(footer.boundingBox,true);break}
      Thread.sleep(forTimeInterval:1)
    }
    XCTAssertNotNil(anchor,"Locate our video using its title or footer even if a notification covers the title")
    if let (box,footer)=anchor {
      system.coordinate(withNormalizedOffset:CGVector(dx:box.midX,dy:1-box.midY+(footer ? -0.035 : 0.04))).tap()
    }
    Thread.sleep(forTimeInterval:0.6)
    screenshot("island-ios-floating-system-controls")
    print("LINGFER PIP BUTTONS",system.buttons.allElementsBoundByIndex.map{($0.identifier,$0.label)})
    let restore=system.buttons.matching(NSPredicate(format:"label CONTAINS[c] '全屏' OR label CONTAINS[c] '还原' OR label CONTAINS[c] '返回App' OR label CONTAINS[c] 'Restore' OR label CONTAINS[c] 'Full Screen'")).firstMatch
    XCTAssertTrue(restore.waitForExistence(timeout:3),system.debugDescription)
    restore.tap()
    XCTAssertTrue(app.wait(for:.runningForeground,timeout:10))
    let debug=app.staticTexts["live-preview-debug"]
    XCTAssertTrue(debug.waitForExistence(timeout:10))
    XCTAssertTrue(debug.label.contains("hidden=false"),debug.label)
    XCTAssertTrue(app.buttons["live-pause"].label.contains("暂停"),"Returning to the app must not pause screen reading")
    safari.activate();Thread.sleep(forTimeInterval:5)
    screenshot("island-ios-floating-restored-after-return")
    app.activate();XCTAssertTrue(app.staticTexts["live-pip-inline"].waitForExistence(timeout:8))
    let shows=Int(debug.label.components(separatedBy:"shows=").dropFirst().first?.components(separatedBy:" ").first ?? "0") ?? 0
    XCTAssertGreaterThanOrEqual(shows,2,debug.label)
    app.buttons["live-display-island"].tap()
    XCTAssertTrue(debug.label.contains("display=island"),debug.label)
    expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.staticTexts["live-pip-active"]);waitForExpectations(timeout:8)
    screenshot("island-ios-explicit-display-choice")
    safari.activate();Thread.sleep(forTimeInterval:3)
    let island=system.otherElements.matching(NSPredicate(format:"identifier IN {'minimal.view','compact.view'} AND label == '语渡随屏阅读'")).allElementsBoundByIndex.first{$0.isHittable}
    if let island {island.press(forDuration:1.3)}
    else {system.coordinate(withNormalizedOffset:CGVector(dx:0.46,dy:0.032)).press(forDuration:1.3)}
    Thread.sleep(forTimeInterval:0.6)
    screenshot("island-ios-actual-expanded-attempt")
    if !system.buttons["island-next"].waitForExistence(timeout:2) {
      safari.coordinate(withNormalizedOffset:CGVector(dx:0.03,dy:0.45)).tap()
      system.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.002)).press(forDuration:0.1,thenDragTo:system.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.72)))
    }
    for name in ["始终允许","允许","Always Allow","Allow"] where system.buttons[name].exists {system.buttons[name].tap();break}
    let next=system.buttons["island-next"]
    XCTAssertTrue(next.waitForExistence(timeout:8),system.debugDescription)
    let expanded=system.otherElements["reading-island-expanded"]
    let lockCard=system.otherElements["reading-activity-card"]
    print("LINGFER ACTIVITY BOUNDS",expanded.exists ? expanded.frame : .zero,lockCard.exists ? lockCard.frame : .zero)
    let word=system.staticTexts["island-word"]
    XCTAssertTrue(word.exists)
    let original=word.label
    next.tap();Thread.sleep(forTimeInterval:1)
    print("LINGFER AFTER NEXT",safari.state.rawValue,app.state.rawValue,"wordVisible",word.exists)
    screenshot("island-ios-after-next-action")
    if !word.exists {
      let compact=system.descendants(matching:.any).matching(NSPredicate(format:"identifier IN {'island-compact-leading','island-minimal','island-compact-position'} OR label == '语渡随屏阅读'")).allElementsBoundByIndex.first{$0.isHittable}
      if let compact {compact.press(forDuration:1.3);Thread.sleep(forTimeInterval:0.6)}
    }
    if !word.waitForExistence(timeout:5) {
      app.activate();print("LINGFER ACTION DEBUG",debug.label);XCTFail("The updated activity must remain available after Next")
    }
    XCTAssertNotEqual(word.label,original)
    XCTAssertEqual(safari.state,.runningForeground,"Paging a Live Activity must keep the reader in the article")
    let area=expanded.exists ? CGRect(x:10,y:0,width:system.frame.width-20,height:min(190,expanded.frame.maxY+14)) : lockCard.exists ? lockCard.frame : CGRect(x:10,y:max(0,word.frame.minY-25),width:system.frame.width-20,height:min(160,next.frame.maxY-word.frame.minY+35))
    if let cg=XCUIScreen.main.screenshot().image.cgImage {
      let scale=CGFloat(cg.width)/system.frame.width
      if let crop=cg.cropping(to:CGRect(x:area.minX*scale,y:area.minY*scale,width:area.width*scale,height:area.height*scale)) {
        let attachment=XCTAttachment(image:UIImage(cgImage:crop));attachment.name="island-ios-readable-activity-card";attachment.lifetime = .keepAlways;add(attachment)
      }
    }
    let switchDisplay=system.descendants(matching:.any).matching(identifier:"island-switch-display").firstMatch
    XCTAssertTrue(switchDisplay.isHittable)
    switchDisplay.tap()
    XCTAssertTrue(app.wait(for:.runningForeground,timeout:10))
    XCTAssertTrue(app.buttons["live-display-floating"].isSelected)
    safari.activate();Thread.sleep(forTimeInterval:4)
    screenshot("island-ios-floating-after-display-switch")
    app.activate();XCTAssertTrue(app.staticTexts["live-pip-inline"].waitForExistence(timeout:8))
    app.buttons["live-display-island"].tap()
    app.buttons["live-stop"].tap()
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10))
    let restoredOptions=app.buttons["live-reading-options"]
    restoredOptions.tap();app.buttons["原文语言"].tap();app.buttons["自动识别"].firstMatch.tap()
    restoredOptions.tap();app.buttons["译文语言"].tap();app.buttons["英语"].firstMatch.tap()
    app.buttons["live-mode-options"].tap();app.buttons[originalMode].firstMatch.tap()
  }

  func testRestoreReadingPreferencesAfterIslandQA() throws {
    app.launch();defer{app.terminate()}
    if !app.buttons["live-start"].exists && !app.buttons["live-stop"].exists {
      XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30))
      button("开启随屏阅读").tap()
      if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    }
    if app.buttons["live-stop"].exists {app.buttons["live-stop"].tap()}
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:15))
    let options=app.buttons["live-reading-options"]
    chooseLiveLanguage(section:"原文语言",value:"自动识别")
    chooseLiveLanguage(section:"译文语言",value:"英语")
    app.buttons["live-mode-options"].tap();app.buttons["整页对照"].firstMatch.tap()
    app.buttons["live-display-floating"].tap()
    XCTAssertTrue(options.label.contains("自动识别") && options.label.contains("英语"),options.label)
    screenshot("island-ios-restored-reading-preferences")
  }

  private func chooseLiveLanguage(section:String,value:String) {
    let summary=app.buttons["live-reading-options"]
    XCTAssertTrue(summary.waitForExistence(timeout:10))
    summary.tap()
    let submenu=app.buttons[section]
    if !submenu.waitForExistence(timeout:2) {
      // A newly presented SwiftUI sheet can expose its controls before the
      // menu accepts input. Retry only after observing the menu did not open.
      XCTAssertTrue(summary.isHittable);summary.tap()
    }
    XCTAssertTrue(submenu.waitForExistence(timeout:5));submenu.tap()
    let option=app.buttons[value].firstMatch
    XCTAssertTrue(option.waitForExistence(timeout:5));option.tap()
  }

  private func verifyPiPSystemNavigation(mode:String,source:String,target:String,fixture:String,name:String) throws {
    guard #available(iOS 16.4, *) else {throw XCTSkip("Requires system URL opening")}
    try requirePhysicalDevice();restoreSystemSynchronization=avoidSystemAnimationWait()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    safari.open(try fixtureURL(fixture))
    app.terminate();app.launchEnvironment["LINGFER_LIVE_QA"]="1"
    app.launchArguments=["--lingfer-live-qa","--pip-navigation-qa","--qa-preserve-reading","--qa-public-reading-fixture"];app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30));button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    let languages=app.buttons["live-reading-options"]
    XCTAssertTrue(languages.waitForExistence(timeout:15))
    chooseLiveLanguage(section:"原文语言",value:source)
    chooseLiveLanguage(section:"译文语言",value:target)
    app.buttons["live-mode-options"].tap();app.buttons[mode].firstMatch.tap()
    app.buttons["live-display-floating"].tap();app.buttons["live-start"].tap()
    XCTAssertTrue(system.buttons["共享整个屏幕"].waitForExistence(timeout:12));system.buttons["共享整个屏幕"].tap()
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15));safari.activate()
    let debug=app.staticTexts["live-preview-debug"]
    func field(_ key:String)->String {debug.label.components(separatedBy:key+"=").dropFirst().first?.components(separatedBy:" ").first ?? "missing"}
    for _ in 0..<20 {
      Thread.sleep(forTimeInterval:3);app.activate()
      XCTAssertTrue(debug.waitForExistence(timeout:5),"Explicit diagnostics must be enabled for measuring remote requests")
      if field("loading")=="false",field("wordLoading")=="false",(Int(field("items")) ?? 0)>=3 {break}
      safari.activate()
    }
    XCTAssertEqual(field("loading"),"false");XCTAssertEqual(field("wordLoading"),"false")
    let count=Int(field("items")) ?? 0
    XCTAssertGreaterThanOrEqual(count,3);XCTAssertEqual(field("clock"),"true");XCTAssertEqual(field("skip"),"true")
    let requests=field("requests"),vocabularyRequests=field("wordRequests")
    var focus=Int(field("focus")) ?? -1
    var actions=Int(field("skipActions")) ?? -1
    print("LINGFER PIP NAV START",name,debug.label)
    func revealControls() throws {
      let forward=system.buttons.matching(NSPredicate(format:"label CONTAINS '快进' OR label CONTAINS[c] 'Skip Forward' OR label CONTAINS[c] 'Forward' OR label CONTAINS[c] 'Fast Forward'")).firstMatch
      func waitForStableControl() {
        // SpringBoard animation idling is disabled for the capture session.
        // AX can expose AVKit's buttons before its entering window accepts
        // touches, so wait for the actual control geometry to settle first.
        var previous=CGRect.null,stable=0
        for _ in 0..<12 {
          if forward.exists && forward.isHittable {
            let frame=forward.frame
            stable=frame==previous ? stable+1 : 0;previous=frame
            if stable>=3 {return}
          } else {stable=0}
          Thread.sleep(forTimeInterval:0.4)
        }
        XCTFail("The PiP skip control never settled")
      }
      if forward.exists && forward.isHittable {waitForStableControl();return}
      var point:CGVector?
      for _ in 0..<8 {
        guard let image=XCUIScreen.main.screenshot().image.cgImage else{throw NSError(domain:"PiP screenshot",code:1)}
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.minimumTextHeight=0.003;request.recognitionLanguages=["zh-Hans","en-US"]
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        if let marker=request.results?.first(where:{($0.topCandidates(1).first?.string.uppercased().replacingOccurrences(of:" ",with:"") ?? "").contains("LINGFERLIVE")}) {
          let box=marker.boundingBox;point=CGVector(dx:box.midX,dy:1-box.midY+0.04);break
        }
        if let footer=request.results?.first(where:{let text=$0.topCandidates(1).first?.string ?? "";return text.contains("点浮窗") || text.contains("本页结果已保留") || text.contains("随阅读位置更新")}) {
          let box=footer.boundingBox;point=CGVector(dx:box.midX,dy:1-box.midY-0.035);break
        }
        Thread.sleep(forTimeInterval:0.6)
      }
      XCTAssertNotNil(point,"Locate the actual video before touching it")
      if let point {system.coordinate(withNormalizedOffset:point).tap()}
      XCTAssertTrue(forward.waitForExistence(timeout:5),system.debugDescription)
      waitForStableControl()
    }
    safari.activate();Thread.sleep(forTimeInterval:2)
    // Stay in the external reader for all three taps. Returning to Lingfer
    // between skips could accidentally mask a broken seeking/controls state.
    for (step,direction) in [1,1,-1].enumerated() {
      try revealControls()
      let label=direction>0 ? "label CONTAINS '快进' OR label CONTAINS[c] 'Skip Forward' OR label CONTAINS[c] 'Forward'" : "label CONTAINS '快退' OR label CONTAINS[c] 'Skip Back' OR label CONTAINS[c] 'Backward' OR label CONTAINS[c] 'Rewind'"
      let skip=system.buttons.matching(NSPredicate(format:label)).firstMatch
      XCTAssertTrue(skip.isEnabled && skip.isHittable,"The actual system PiP skip control must be enabled")
      let skipLabel=skip.label
      screenshot("pip-"+name+"-controls-\(step)")
      skip.tap();Thread.sleep(forTimeInterval:1)
      XCTAssertEqual(safari.state,.runningForeground,"A system PiP skip must leave the article in the foreground")
      screenshot("pip-"+name+"-after-skip-\(step)")
      focus=(focus+direction+count)%count;actions+=1
      print("LINGFER PIP NAV TAP",name,step,skipLabel,"expectedFocus",focus)
    }
    // The transition hold must not merely postpone a cursor reset. Recheck
    // after it has expired while the article remains unchanged in the foreground.
    Thread.sleep(forTimeInterval:4)
    app.activate();XCTAssertTrue(debug.waitForExistence(timeout:8))
    XCTAssertEqual(Int(field("focus")),focus,debug.label)
    XCTAssertEqual(Int(field("skipActions")),actions,"Only the AVKit delegate increments this counter")
    XCTAssertEqual(field("requests"),requests,"Navigation must reuse the translated content")
    XCTAssertEqual(field("wordRequests"),vocabularyRequests)
    XCTAssertTrue(debug.label.contains("ready=true") && debug.label.contains("error=none"),debug.label)
    print("LINGFER PIP NAV FINISH",name,debug.label)
    safari.activate();Thread.sleep(forTimeInterval:2);try revealControls()
    screenshot("pip-"+name+"-restored-after-return")
    app.activate();XCTAssertTrue(app.staticTexts["live-pip-inline"].waitForExistence(timeout:8))
    XCTAssertGreaterThanOrEqual(Int(field("shows")) ?? 0,2)
    app.buttons["live-stop"].tap();XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10))
  }

  func testPiPSystemWordNavigation() throws {
    try verifyPiPSystemNavigation(mode:"学习辅助",source:"英语",target:"中文",fixture:"stable-scroll.html",name:"words")
  }

  func testPiPSystemPassageNavigation() throws {
    try verifyPiPSystemNavigation(mode:"整页对照",source:"自动识别",target:"英语",fixture:"island-chinese.html",name:"passages")
  }

  func testPiPSystemChineseWordNavigation() throws {
    try verifyPiPSystemNavigation(mode:"学习辅助",source:"自动识别",target:"英语",fixture:"island-chinese.html",name:"chinese-words")
  }

  func testFullPageCaptureAndLocalSessionHistory() throws {
    guard #available(iOS 16.4, *) else {throw XCTSkip("Requires system URL opening")}
    try requirePhysicalDevice();restoreSystemSynchronization=avoidSystemAnimationWait()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    safari.open(try fixtureURL("full-page-reading.html"))
    app.terminate();app.launchEnvironment["LINGFER_LIVE_QA"]="1"
    app.launchArguments=["--lingfer-live-qa","--qa-preserve-reading","--qa-public-reading-fixture"];app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30));button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    chooseLiveLanguage(section:"原文语言",value:"英语")
    chooseLiveLanguage(section:"译文语言",value:"中文")
    app.buttons["live-mode-options"].tap();app.buttons["学习辅助"].firstMatch.tap()
    app.buttons["live-display-floating"].tap();app.buttons["live-start"].tap()
    XCTAssertTrue(system.buttons["共享整个屏幕"].waitForExistence(timeout:12));system.buttons["共享整个屏幕"].tap()
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15));safari.activate()
    Thread.sleep(forTimeInterval:5);screenshot("nov14-unbranded-learning-float")
    app.activate();XCTAssertTrue(app.staticTexts["live-capture-summary"].waitForExistence(timeout:10))
    app.buttons["share-original-tab"].tap()
    let original=app.staticTexts["share-original-text"]
    XCTAssertTrue(original.waitForExistence(timeout:8))
    func normalizedOriginal()->String {original.label.replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression)}
    screenshot("nov14-complete-first-page-source")
    XCTAssertTrue(normalizedOriginal().contains("Reliable evidence"),"Read the first paragraph before displaying the PiP")
    print("LINGFER NOV14 PUBLIC SOURCE",normalizedOriginal())
    XCTAssertTrue(normalizedOriginal().contains("practical conclusion"),"The lower visible paragraph must be captured too")
    XCTAssertFalse(original.label.contains("点浮窗"),"The floating translation itself must be excluded from OCR")
    XCTAssertGreaterThanOrEqual(original.label.count,260)
    screenshot("nov14-complete-first-page-source")
    safari.activate();XCTAssertTrue(safari.buttons["Next sample page"].waitForExistence(timeout:8));safari.buttons["Next sample page"].tap()
    Thread.sleep(forTimeInterval:5);screenshot("nov14-next-page-learning-float")
    app.activate();XCTAssertTrue(original.waitForExistence(timeout:8))
    XCTAssertTrue(normalizedOriginal().contains("comprehensive investigation"),"Settled new-page content must replace the old live source")
    app.buttons["live-stop"].tap();XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10))
    XCTAssertTrue(button("查看上次结果").waitForExistence(timeout:8));button("查看上次结果").tap()
    app.buttons["share-original-tab"].tap();XCTAssertTrue(original.waitForExistence(timeout:8))
    XCTAssertTrue(normalizedOriginal().contains("Reliable evidence") && normalizedOriginal().contains("comprehensive investigation"),"History must retain both accepted pages locally")
    XCTAssertTrue(app.staticTexts["share-source-coverage"].label.contains("页面记录"))
    let historySummary=app.staticTexts["share-source-coverage"].label
    screenshot("nov14-local-session-history-source")
    let historyWords=app.buttons["share-words-tab"]
    let digits=historyWords.label.components(separatedBy:CharacterSet.decimalDigits.inverted).compactMap(Int.init)
    XCTAssertGreaterThan(digits.first ?? 0,1,"The local history must retain vocabulary across accepted pages")
    historyWords.tap();screenshot("nov14-local-session-history-words")
    print("LINGFER NOV14 HISTORY",historySummary)
  }

  func testOneTapPresentationAndAutomaticDock() throws {
    guard #available(iOS 16.4, *) else {throw XCTSkip("Requires system URL opening")}
    try requirePhysicalDevice();restoreSystemSynchronization=avoidSystemAnimationWait()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    safari.open(try fixtureURL("stable-scroll.html"))
    app.launchEnvironment["LINGFER_LIVE_QA"]="1"
    app.launchArguments=["--lingfer-live-qa","--qa-preserve-reading"];app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30));button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    chooseLiveLanguage(section:"原文语言",value:"英语")
    chooseLiveLanguage(section:"译文语言",value:"中文")
    app.buttons["live-mode-options"].tap();app.buttons["学习辅助"].firstMatch.tap()
    let floating=app.buttons["live-display-floating"],island=app.buttons["live-display-island"]
    func assertSelected(_ mode:XCUIElement) {
      let selected=XCTNSPredicateExpectation(predicate:NSPredicate(format:"isSelected == true"),object:mode)
      XCTAssertEqual(XCTWaiter.wait(for:[selected],timeout:3),.completed,"A single tap must update the selected presentation")
    }
    floating.tap();assertSelected(floating)
    app.buttons["live-start"].tap()
    XCTAssertTrue(system.buttons["共享整个屏幕"].waitForExistence(timeout:12))
    system.buttons["共享整个屏幕"].tap()
    safari.activate()
    let firstPreviewAt=Date()
    let initialAutomaticPreview=waitForActualLivePiP(in:safari,timeout:30)
    let initialObservationMs=Int(Date().timeIntervalSince(firstPreviewAt)*1000)
    let safariWasForeground=safari.state == .runningForeground
    if safariWasForeground {
      screenshot(initialAutomaticPreview ? "first-automatic-pip-safari" : "first-automatic-pip-safari-timeout")
    }

    // Returning to Lingfer can change PiP state. Inspect the retained AVKit
    // start count only after capturing the external screen and OCR result.
    app.activate()
    let current=app.staticTexts["live-startup-diagnostics"]
    var avkitEvidence="The AVKit start count outside the active app was unavailable."
    if current.waitForExistence(timeout:6) {
      let state=current.label
      print("LINGFER ONE TAP STARTUP",state)
      let startField="pipStartsOutsideActive="
      if let entry=state.split(separator:" ").first(where:{$0.hasPrefix(startField)}),
         let starts=Int(entry.dropFirst(startField.count)) {
        avkitEvidence="AVKit reported \(starts) start callback(s) outside the active app."
      }
    }
    if !initialAutomaticPreview {
      let background=app.staticTexts["live-background-diagnostics"]
      if background.waitForExistence(timeout:6) {print("LINGFER ONE TAP FAILURE_BACKGROUND",background.label)}
    }
    XCTAssertTrue(safariWasForeground,"The initial observation must take place with the public article in Safari.")
    XCTAssertTrue(initialAutomaticPreview,"The first Safari observation did not detect the PiP footer. Inspect the attached Safari screenshot. \(avkitEvidence)")
    guard initialAutomaticPreview else{return}
    print("LINGFER ONE TAP initialPreviewMs",initialObservationMs)
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15),"Authorization must retain the native reading panel.")
    XCTAssertTrue(app.buttons["live-stop"].isHittable)
    XCTAssertFalse(app.buttons["live-start"].exists)
    let debug=app.staticTexts["live-preview-debug"]
    XCTAssertTrue(debug.waitForExistence(timeout:8))
    func field(_ key:String)->String {debug.label.components(separatedBy:key+"=").dropFirst().first?.components(separatedBy:" ").first ?? "missing"}
    func tapOnce(_ mode:XCUIElement,_ name:String) {
      XCTAssertTrue(mode.isHittable)
      let started=Date();mode.tap();assertSelected(mode)
      print("LINGFER ONE TAP selection",name,"tapMs",Int(Date().timeIntervalSince(started)*1000))
    }
    XCTAssertEqual(field("display"),"floating")
    XCTAssertGreaterThanOrEqual(Int(field("shows")) ?? 0,1)
    print("LINGFER ONE TAP CONTENT_AT_RETURN pages",field("pages"),"words",field("words"),"loading",field("loading"))
    let requests=field("requests"),pages=field("pages")
    tapOnce(floating,"floating-repeat")
    XCTAssertEqual(field("requests"),requests);XCTAssertEqual(field("pages"),pages)
    tapOnce(island,"island")
    XCTAssertFalse(floating.isSelected)
    XCTAssertTrue(app.staticTexts["live-island-active"].waitForExistence(timeout:8),"Selecting island once must start the existing live activity path")
    tapOnce(island,"island-repeat")
    XCTAssertEqual(field("requests"),requests);XCTAssertEqual(field("pages"),pages)
    let rapidAt=Date()
    // No retries or artificial settling delay between these user choices.
    floating.tap();island.tap();floating.tap();assertSelected(floating)
    XCTAssertFalse(island.isSelected)
    print("LINGFER ONE TAP rapidFloatIslandFloatMs",Int(Date().timeIntervalSince(rapidAt)*1000))
    XCTAssertEqual(field("requests"),requests,"Presentation changes reuse the recognized source")
    XCTAssertEqual(field("pages"),pages,"Presentation changes must not restart capture")
    safari.activate()
    XCTAssertTrue(waitForActualLivePiP(in:safari,timeout:20),"Floating presentation must recover after the final single selection")
    screenshot("nov14-one-tap-pip-after-rapid-switch")
    app.activate();XCTAssertTrue(debug.waitForExistence(timeout:8))
    print("LINGFER ONE TAP FINISH pages",field("pages"),"requests",field("requests"),"shows",field("shows"),"recoveries",field("recoveries"),"skipActions",field("skipActions"))
    XCTAssertTrue(debug.label.contains("ready=true") && debug.label.contains("error=none"))
    app.buttons["live-stop"].tap();XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10))
    XCTAssertFalse(app.buttons["live-stop"].exists)
  }

  /// Authorized maintenance of the actual device's regenerable reader cache
  /// and source==mock empty examples. No fixtures or imports are created here.
  func testStorageCleanupAuthorizedNov14() throws {
    try requirePhysicalDevice()
    app.launchEnvironment.removeValue(forKey:"LINGFER_LIVE_QA");app.launchArguments=[];app.launch()
    let settings=button("设置")
    XCTAssertTrue(settings.waitForExistence(timeout:30));settings.tap()
    let usage=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS '阅读缓存 ' AND (label BEGINSWITH '本地存储' OR label BEGINSWITH '阅读缓存 ')")).firstMatch
    for _ in 0..<10 {
      if usage.exists && usage.isHittable {break}
      app.swipeUp()
    }
    XCTAssertTrue(usage.waitForExistence(timeout:15),"Settings must show actual cache usage")
    XCTAssertTrue(usage.isHittable)
    func cacheSummary()->String {
      let text=usage.label
      guard let range=text.range(of:#"阅读缓存 [0-9]+(?:\.[0-9]+)? (?:B|KB|MB)"#,options:.regularExpression) else{return "missing"}
      return String(text[range])
    }
    let before=cacheSummary()
    let clear=app.buttons.matching(NSPredicate(format:"label CONTAINS '清理阅读缓存'")).firstMatch
    XCTAssertTrue(clear.waitForExistence(timeout:8))
    var cleared=false
    if before != "阅读缓存 0 B" {
      XCTAssertTrue(clear.isEnabled && clear.isHittable,"Nonzero regenerable cache must be clearable")
      clear.tap();cleared=true
      let empty=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS '阅读缓存 0 B'"),object:usage)
      XCTAssertEqual(XCTWaiter.wait(for:[empty],timeout:15),.completed,"The real cache should be empty after cleanup")
    }
    let archive=app.buttons.matching(NSPredicate(format:"label CONTAINS '移除旧版空示例'")).firstMatch
    let hadLegacyExamples=archive.exists
    if hadLegacyExamples {
      if !archive.isHittable {app.swipeUp()}
      XCTAssertTrue(archive.isEnabled && archive.isHittable)
      archive.tap()
      let removed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:archive)
      XCTAssertEqual(XCTWaiter.wait(for:[removed],timeout:10),.completed,"Only the existing source==mock examples should be removed")
    }
    // Only byte totals and booleans enter the log. No private titles, file
    // paths, account values, screenshots or accessibility tree are attached.
    print("LINGFER STORAGE CLEANUP before",before,"after",cacheSummary(),"cacheCleared",cleared,"legacyMocksRemoved",hadLegacyExamples)
    XCTAssertFalse(button("缓存未清理完成，请重试。").exists)
    XCTAssertFalse(button("暂时无法移除示例，请重试。").exists)
  }

  func testRestoreUserReadingAfterFixtureQA() throws {
    app.launchEnvironment["LINGFER_LIVE_QA"]="1"
    app.launchArguments=["--lingfer-live-qa","--qa-restore-reading"];app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30))
    app.terminate()
  }

  func testFirstLaunchLibraryAndReaderNov14() throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("Use a dedicated fresh simulator, preserving the user's real library")
    #endif
    app.launch();XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30))
    screenshot("nov14-fresh-install-home")
    for _ in 0..<5 {
      if button("爱丽丝梦游仙境").exists && button("爱丽丝梦游仙境").isHittable {break}
      app.swipeUp()
    }
    XCTAssertTrue(button("爱丽丝梦游仙境").waitForExistence(timeout:8))
    XCTAssertTrue(button("福尔摩斯历险记").exists)
    XCTAssertTrue(button("傲慢与偏见").exists)
    screenshot("nov14-fresh-install-public-domain-library")
    button("爱丽丝梦游仙境").tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS 'Alice'")).firstMatch.waitForExistence(timeout:30))
    screenshot("nov14-public-domain-reader")
    app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.45)).tap()
    screenshot("nov14-public-domain-reader-controls")
    let scope=app.buttons.matching(NSPredicate(format:"label CONTAINS '四级' OR label CONTAINS '考研' OR label CONTAINS '六级'")).firstMatch
    XCTAssertTrue(scope.waitForExistence(timeout:8));XCTAssertTrue(scope.isHittable)
    scope.tap();XCTAssertTrue(app.staticTexts["学习范围"].waitForExistence(timeout:8))
    screenshot("nov14-reader-level-sheet")
    let closeScope=app.buttons.matching(NSPredicate(format:"label CONTAINS '关闭学习范围'")).firstMatch
    if closeScope.exists && closeScope.isHittable {closeScope.tap()}
    else {app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.18)).tap()}
    app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.45)).tap()
    // Pass the title/contents pages and verify actual prose is on screen,
    // rather than treating a visible book title as proof of readable content.
    let prose=app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] 'Alice' AND label CONTAINS[c] 'sister'")).firstMatch
    for _ in 0..<8 {
      if prose.exists && prose.isHittable {break}
      app.swipeLeft()
    }
    XCTAssertTrue(prose.waitForExistence(timeout:10));XCTAssertTrue(prose.isHittable)
    for _ in 0..<15 {
      let loading=app.staticTexts["正在生成注释…"]
      if !loading.exists {break}
      Thread.sleep(forTimeInterval:1)
    }
    let hasGloss=prose.label.range(of:#"[\u3400-\u9FFF]"#,options:.regularExpression) != nil
    print("LINGFER NOV14 PROSE",prose.label.count,"characters; gloss visible",hasGloss)
    screenshot("nov14-public-domain-prose")
  }

  func testIslandWordNavigation() throws {
    guard #available(iOS 16.4, *) else {throw XCTSkip("Requires system URL opening")}
    try requirePhysicalDevice();restoreSystemSynchronization=avoidSystemAnimationWait()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    app.launchEnvironment["LINGFER_LIVE_QA"]="1";app.launchArguments=["--lingfer-live-qa"];app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30));button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:15))
    let options=app.buttons["live-reading-options"]
    options.tap();app.buttons["原文语言"].tap();app.buttons["英语"].firstMatch.tap()
    options.tap();app.buttons["译文语言"].tap();app.buttons["中文"].firstMatch.tap()
    app.buttons["live-mode-options"].tap();app.buttons["学习辅助"].firstMatch.tap()
    app.buttons["live-display-island"].tap();app.buttons["live-start"].tap()
    XCTAssertTrue(system.buttons["共享整个屏幕"].waitForExistence(timeout:12));system.buttons["共享整个屏幕"].tap()
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15))
    safari.open(try fixtureURL("stable-scroll.html"));Thread.sleep(forTimeInterval:4)
    func expand() {
      // The image's AX frame can be offset above its actual system container.
      // Press the system-owned activity container rather than the tiny icon.
      let compact=system.otherElements.matching(NSPredicate(format:"identifier IN {'minimal.view','compact.view'} AND label == '语渡随屏阅读'")).allElementsBoundByIndex.first{$0.isHittable}
      if let compact {compact.press(forDuration:1.3)} else {system.coordinate(withNormalizedOffset:CGVector(dx:0.46,dy:0.032)).press(forDuration:1.3)}
      Thread.sleep(forTimeInterval:0.6)
    }
    expand()
    let word=system.staticTexts["island-word"]
    XCTAssertTrue(word.waitForExistence(timeout:8))
    let old=word.label
    print("LINGFER ORIGINAL WORD",old)
    screenshot("island-nav-before-next")
    XCTAssertTrue(system.buttons["island-next"].isHittable)
    system.buttons["island-next"].tap();Thread.sleep(forTimeInterval:1)
    print("LINGFER NEXT RESULT",word.exists ? word.label : "collapsed","Safari",safari.state.rawValue,"App",app.state.rawValue)
    screenshot("island-nav-after-next")
    XCTAssertEqual(safari.state,.runningForeground,"The Next action must keep the reader in Safari")
    XCTAssertNotEqual(word.label,old,"The actual background intent must update the displayed word")
    let new=word.label
    safari.coordinate(withNormalizedOffset:CGVector(dx:0.05,dy:0.45)).tap();expand()
    XCTAssertTrue(word.waitForExistence(timeout:8))
    XCTAssertEqual(word.label,new,"Reopening the island must preserve the selected next word")
    XCTAssertTrue(system.buttons["island-stop"].isHittable)
    screenshot("island-nav-updated-word")
    system.buttons["island-previous"].tap();Thread.sleep(forTimeInterval:1)
    if !word.exists {expand()}
    XCTAssertTrue(word.waitForExistence(timeout:8));XCTAssertEqual(word.label,old)
    XCTAssertEqual(safari.state,.runningForeground)
    screenshot("island-nav-previous-restored")
    app.activate();app.buttons["live-stop"].tap()
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10))
  }

  func testCoexistingVocabularyAndPassages() throws {
    guard #available(iOS 16.4, *) else {throw XCTSkip("Requires system URL opening")}
    try requirePhysicalDevice();restoreSystemSynchronization=avoidSystemAnimationWait()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    // Prepare a public page before starting the authorized capture.
    safari.open(try fixtureURL("island-chinese.html"))
    app.terminate();app.launchEnvironment["LINGFER_LIVE_QA"]="1";app.launchArguments=["--lingfer-live-qa"];app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30));button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    let language=app.buttons["live-reading-options"]
    XCTAssertTrue(language.waitForExistence(timeout:15))
    language.tap();app.buttons["原文语言"].tap();app.buttons["自动识别"].firstMatch.tap()
    language.tap();app.buttons["译文语言"].tap();app.buttons["英语"].firstMatch.tap()
    app.buttons["live-mode-options"].tap();app.buttons["整页对照"].firstMatch.tap()
    app.buttons["live-display-floating"].tap();app.buttons["live-start"].tap()
    XCTAssertTrue(system.buttons["共享整个屏幕"].waitForExistence(timeout:12));system.buttons["共享整个屏幕"].tap()
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15));safari.activate()
    let debug=app.staticTexts["live-preview-debug"]
    func field(_ name:String)->String {debug.label.components(separatedBy:name+"=").dropFirst().first?.components(separatedBy:" ").first ?? "missing"}
    let progress=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH '已翻译 '")).firstMatch
    func passagesComplete()->Bool {
      progress.exists && progress.label.range(of:#"已翻译 ([1-9][0-9]*) / \1 段"#,options:.regularExpression) != nil
    }
    for _ in 0..<15 {
      Thread.sleep(forTimeInterval:3);app.activate()
      if debug.exists {
        if field("loading")=="false",field("wordLoading")=="false",(Int(field("islandWords")) ?? 0)>0 {break}
      } else if passagesComplete() {break}
      safari.activate()
    }
    let hasMetrics=debug.exists
    XCTAssertTrue(passagesComplete(),"The actual full-page UI must show complete translated passages")
    XCTAssertTrue(app.staticTexts["live-island-active"].exists)
    if hasMetrics {
      print("LINGFER COEXIST",debug.label)
      XCTAssertTrue(debug.label.contains("context=translation|"));XCTAssertGreaterThan(Int(field("islandWords")) ?? 0,0)
      XCTAssertLessThanOrEqual(Int(field("wordRequests")) ?? 0,Int(field("pages")) ?? 0,"At most one vocabulary request per accepted page")
    } else {print("LINGFER COEXIST: device omitted launch diagnostics; validating visible results, request counts not measured in this run")}
    let requests=hasMetrics ? field("requests") : "",wordRequests=hasMetrics ? field("wordRequests") : ""
    XCTAssertTrue(app.buttons["share-scope-summary"].exists,"The island vocabulary scope remains adjustable in full-page mode")
    safari.activate();Thread.sleep(forTimeInterval:3)
    var usedNotificationCenter=false
    let compact=system.otherElements.matching(NSPredicate(format:"identifier IN {'minimal.view','compact.view'} AND label == '语渡随屏阅读'")).allElementsBoundByIndex.first{$0.isHittable}
    if let compact {compact.press(forDuration:1.3)} else {system.coordinate(withNormalizedOffset:CGVector(dx:0.46,dy:0.032)).press(forDuration:1.3)}
    let word=system.staticTexts["island-word"]
    if !word.waitForExistence(timeout:2) {
      usedNotificationCenter=true
      screenshot("coexist-system-island-priority")
      system.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.002)).press(forDuration:0.1,thenDragTo:system.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.72)))
      for name in ["始终允许","允许","Always Allow","Allow"] where system.buttons[name].exists {system.buttons[name].tap();break}

    }
    XCTAssertTrue(word.waitForExistence(timeout:8),"In coexistence the island holds vocabulary while the video shows passages")
    func captureActivity(_ name:String) {
      let card=system.otherElements[usedNotificationCenter ? "reading-activity-card" : "reading-island-expanded"]
      guard card.exists,let cg=XCUIScreen.main.screenshot().image.cgImage else{return}
      let area=card.frame.intersection(system.frame),scale=CGFloat(cg.width)/system.frame.width
      guard let cropped=cg.cropping(to:CGRect(x:area.minX*scale,y:area.minY*scale,width:area.width*scale,height:area.height*scale)) else{return}
      let attachment=XCTAttachment(image:UIImage(cgImage:cropped));attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    captureActivity("coexist-live-activity-card")
    let old=word.label
    system.buttons["island-next"].tap();Thread.sleep(forTimeInterval:1)
    if !word.exists {system.coordinate(withNormalizedOffset:CGVector(dx:0.46,dy:0.032)).press(forDuration:1.3)}
    XCTAssertTrue(word.waitForExistence(timeout:5));XCTAssertNotEqual(word.label,old,"The public fixture contains multiple eligible words")
    if usedNotificationCenter {XCTAssertNotEqual(app.state,.runningForeground)}
    else {XCTAssertEqual(safari.state,.runningForeground)}
    captureActivity("coexist-live-activity-next-word")
    safari.activate()
    safari.coordinate(withNormalizedOffset:CGVector(dx:0.05,dy:0.45)).tap()
    safari.coordinate(withNormalizedOffset:CGVector(dx:0.18,dy:0.48)).press(forDuration:0.1,thenDragTo:safari.coordinate(withNormalizedOffset:CGVector(dx:0.18,dy:0.475)),withVelocity:.slow,thenHoldForDuration:0.1)
    Thread.sleep(forTimeInterval:4);screenshot("store-ios-floating-after-island-collapses")
    app.activate();Thread.sleep(forTimeInterval:0.5)
    if hasMetrics {XCTAssertEqual(field("requests"),requests);XCTAssertEqual(field("wordRequests"),wordRequests)}
    XCTAssertTrue(app.staticTexts["live-pip-inline"].waitForExistence(timeout:8))
    // Finish in the existing app controls. The system can prioritize its sharing
    // indicator over our island while PiP is active; island Stop is covered by
    // testIslandWordNavigation, independently of this coexistence regression.
    app.buttons["live-stop"].tap()
    XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10))
  }

  func testIslandAutomaticEnglishTranslation() throws {
    guard #available(iOS 16.4, *) else {throw XCTSkip("Requires system URL opening")}
    try requirePhysicalDevice();restoreSystemSynchronization=avoidSystemAnimationWait()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    app.launchEnvironment["LINGFER_LIVE_QA"]="1";app.launchArguments=["--lingfer-live-qa"];app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30));button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    let options=app.buttons["live-reading-options"]
    XCTAssertTrue(options.waitForExistence(timeout:15))
    options.tap();app.buttons["原文语言"].tap();app.buttons["自动识别"].firstMatch.tap()
    options.tap();app.buttons["译文语言"].tap();app.buttons["英语"].firstMatch.tap()
    app.buttons["live-mode-options"].tap();app.buttons["整页对照"].firstMatch.tap()
    app.buttons["live-display-island"].tap();app.buttons["live-start"].tap()
    XCTAssertTrue(system.buttons["共享整个屏幕"].waitForExistence(timeout:12));system.buttons["共享整个屏幕"].tap()
    XCTAssertTrue(app.buttons["live-pause"].waitForExistence(timeout:15))
    let start=Date()
    safari.open(try fixtureURL("island-chinese.html"))
    let debug=app.staticTexts["live-preview-debug"]
    func value(_ name:String)->String {debug.label.components(separatedBy:name+"=").dropFirst().first?.components(separatedBy:" ").first ?? "missing"}
    for _ in 0..<15 {
      Thread.sleep(forTimeInterval:3);app.activate()
      XCTAssertTrue(debug.waitForExistence(timeout:5))
      if debug.label.contains("context=translation|"),value("loading")=="false" {break}
      safari.activate()
    }
    print("LINGFER REMOTE TRANSLATION seconds",Date().timeIntervalSince(start),debug.label)
    XCTAssertTrue(debug.label.contains("context=translation|"))
    let context=debug.label.components(separatedBy:"context=translation|").last ?? ""
    let translated=context.components(separatedBy:"|").dropFirst().joined(separator:"|")
    XCTAssertGreaterThan(translated.count,30,"Publish a complete passage instead of an isolated OCR line")
    XCTAssertEqual(value("loading"),"false")
    XCTAssertGreaterThan(Int(value("requests")) ?? 0,0)
    screenshot("island-ios-auto-english-translation-results")
    let requests=value("requests"),focus=value("focus")
    safari.activate()
    safari.coordinate(withNormalizedOffset:CGVector(dx:0.18,dy:0.48)).press(forDuration:0.1,thenDragTo:safari.coordinate(withNormalizedOffset:CGVector(dx:0.18,dy:0.475)),withVelocity:.slow,thenHoldForDuration:0.1)
    Thread.sleep(forTimeInterval:4);app.activate()
    XCTAssertEqual(value("requests"),requests,"A slight scroll must not repeat completed passage requests")
    XCTAssertEqual(value("focus"),focus,"A slight scroll must preserve the selected passage")
    safari.activate();Thread.sleep(forTimeInterval:1)
    let compact=system.otherElements.matching(NSPredicate(format:"identifier IN {'minimal.view','compact.view'} AND label == '语渡随屏阅读'")).allElementsBoundByIndex.first{$0.isHittable}
    if let compact {compact.press(forDuration:1.3)} else {system.coordinate(withNormalizedOffset:CGVector(dx:0.46,dy:0.032)).press(forDuration:1.3)}
    let translation=system.staticTexts["island-translation"]
    XCTAssertTrue(translation.waitForExistence(timeout:8))
    screenshot("island-ios-auto-english-expanded-translation")
    system.buttons["island-pause"].tap();Thread.sleep(forTimeInterval:1)
    app.activate();XCTAssertTrue(app.buttons["live-pause"].label.contains("继续"))
    safari.activate()
    system.coordinate(withNormalizedOffset:CGVector(dx:0.46,dy:0.032)).press(forDuration:1.3)
    XCTAssertTrue(system.buttons["island-stop"].waitForExistence(timeout:8));system.buttons["island-stop"].tap()
    app.activate();XCTAssertTrue(app.buttons["live-start"].waitForExistence(timeout:10))
  }

  // One-off device automation for the user's explicitly requested preference.
  func testRestoreAutomaticEnglishPreference() throws {
    app.launch();defer{app.terminate()}
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30))
    button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    let options=app.buttons["live-reading-options"]
    XCTAssertTrue(options.waitForExistence(timeout:15))
    options.tap();app.buttons["原文语言"].tap();app.buttons["自动识别"].firstMatch.tap()
    options.tap();app.buttons["译文语言"].tap();app.buttons["英语"].firstMatch.tap()
    XCTAssertTrue(options.label.contains("自动识别") && options.label.contains("英语"),options.label)
    screenshot("stable-ios-restored-automatic-english")
    app.buttons["share-done"].tap()
  }

  func testIndependentReadingSetupControls() throws {
    app.terminate();app.launch()
    XCTAssertTrue(button("开启随屏阅读").waitForExistence(timeout:30));button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    let mode=app.buttons["live-mode-options"],language=app.buttons["live-reading-options"]
    XCTAssertTrue(mode.waitForExistence(timeout:15));XCTAssertTrue(language.isHittable)
    XCTAssertTrue(mode.isHittable)
    let originalMode=mode.label
    language.tap()
    XCTAssertTrue(app.buttons["原文语言"].waitForExistence(timeout:5))
    XCTAssertTrue(app.buttons["译文语言"].exists)
    app.buttons["原文语言"].tap();app.buttons["自动识别"].firstMatch.tap()
    language.tap();app.buttons["译文语言"].tap();app.buttons["英语"].firstMatch.tap()
    XCTAssertEqual(mode.label,originalMode,"Language selection must preserve the independently selected reading mode")
    mode.tap();XCTAssertTrue(app.buttons["整页对照"].waitForExistence(timeout:5));app.buttons["整页对照"].firstMatch.tap()
    XCTAssertTrue(mode.label.contains("整页对照"))
    app.buttons["live-display-floating"].tap();XCTAssertTrue(app.buttons["live-display-floating"].isSelected)
    screenshot("store-ios-live-ready-independent-controls")
    mode.tap();app.buttons["学习辅助"].firstMatch.tap();XCTAssertTrue(mode.label.contains("学习辅助"))
    XCTAssertTrue(language.label.contains("自动识别") && language.label.contains("英语"))
    screenshot("store-ios-live-ready-learning")
    mode.tap();app.buttons["整页对照"].firstMatch.tap()
    app.buttons["share-done"].tap()
    screenshot("store-ios-current-home")
  }

  func testReadingPreparationReturnAndOptionalConsent() throws {
    app.launch()
    let entry=button("开启随屏阅读")
    XCTAssertTrue(entry.waitForExistence(timeout:30));entry.tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    let start=app.buttons["live-start"]
    XCTAssertTrue(start.waitForExistence(timeout:15))
    XCTAssertTrue(start.isHittable,"Opening reading must not cover the preparation view with an unsolicited sheet")
    XCTAssertFalse(app.buttons["ai-consent-allow"].exists)
    let back=app.buttons["share-done"]
    XCTAssertEqual(app.buttons.matching(identifier:"share-done").count,1)
    XCTAssertTrue(back.isHittable)
    screenshot("nov16-reading-preparation-single-return")
    app.buttons["live-ai-consent"].tap()
    XCTAssertTrue(app.buttons["ai-consent-local"].waitForExistence(timeout:5))
    app.buttons["ai-consent-local"].tap()
    XCTAssertTrue(start.isHittable)
    back.tap()
    XCTAssertTrue(entry.waitForExistence(timeout:8))
    XCTAssertTrue(entry.isHittable,"The single return action must dismiss the reading panel")
  }

  func testRefinedReadingDesign() throws {
    app.launch()
    XCTAssertTrue(button("粘贴文字").waitForExistence(timeout:30),app.debugDescription)
    Thread.sleep(forTimeInterval:0.5)
    screenshot("refined-ios-home")
    button("开启随屏阅读").tap()
    if button("了解，继续").waitForExistence(timeout:2) {button("了解，继续").tap()}
    app.buttons["live-mode-options"].tap();app.buttons["学习辅助"].firstMatch.tap()
    app.buttons["live-reading-options"].tap();app.buttons["原文语言"].tap();app.buttons["英语"].firstMatch.tap()
    app.buttons["live-reading-options"].tap();app.buttons["译文语言"].tap();app.buttons["中文"].firstMatch.tap()
    let start=app.buttons["live-start"]
    XCTAssertTrue(start.waitForExistence(timeout:15),app.debugDescription)
    XCTAssertLessThan(abs(start.frame.midX-app.frame.midX),3)
    Thread.sleep(forTimeInterval:0.5)
    screenshot("refined-ios-live-ready")
    app.buttons["live-reading-options"].tap()
    Thread.sleep(forTimeInterval:0.5)
    screenshot("refined-ios-live-options")
    app.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.35)).tap()
    app.buttons["share-done"].tap()
    let sample=button("试读一段")
    for _ in 0..<7 {if sample.isHittable {break};app.swipeUp()}
    XCTAssertTrue(sample.isHittable,app.debugDescription)
    sample.tap()
    XCTAssertTrue(button("词卡").waitForExistence(timeout:15))
    Thread.sleep(forTimeInterval:0.8)
    screenshot("refined-ios-reading")
  }

}

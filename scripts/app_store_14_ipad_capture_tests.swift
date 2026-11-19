import XCTest

/// Marketing-only real iPad UI capture. The production app is unchanged.
/// All vocabulary is created by actual public-sample bookmark taps; the only
/// network content is the app's public English sample after explicit AI opt-in.
final class IPadMarketing14Tests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "com.wang.yudu")
  override func setUpWithError() throws { continueAfterFailure = false }
  override func tearDownWithError() throws { app.terminate() }

  private func element(_ label: String) -> XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label)
    ).firstMatch
  }
  private func capture(_ name: String) {
    Thread.sleep(forTimeInterval: 0.7)
    let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    image.name = name; image.lifetime = .keepAlways; add(image)
  }
  private func home() {
    app.launch()
    XCTAssertTrue(element("开启随屏阅读").waitForExistence(timeout: 35))
  }
  private func sample() {
    let sample = element("试读一段")
    for _ in 0..<10 {
      if sample.isHittable { break }
      app.swipeUp(); Thread.sleep(forTimeInterval: 0.7)
    }
    XCTAssertTrue(sample.isHittable, app.debugDescription)
    sample.tap()
    XCTAssertTrue(app.staticTexts["英文试读"].waitForExistence(timeout: 20))
  }
  private func languagePanel() {
    let language = element("语言与自动更新")
    if language.waitForExistence(timeout: 2), language.isHittable { language.tap() }
    else {
      let action = app.buttons.allElementsBoundByIndex.first {
        $0.isHittable && $0.frame.midY < app.frame.height * 0.15
          && $0.frame.midX > app.frame.width * 0.65
          && !$0.label.contains("四级") && !$0.label.contains("收藏")
      }
      XCTAssertNotNil(action, app.debugDescription); action?.tap()
    }
    XCTAssertTrue(element("关闭语言设置").waitForExistence(timeout: 5), app.debugDescription)
  }
  private func englishToChinese(mode desiredMode: String) {
    languagePanel()
    let source = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '原文语言'")).firstMatch
    source.tap(); app.buttons.matching(NSPredicate(format: "label == '英语'")).firstMatch.tap()
    let target = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '译文语言'")).firstMatch
    target.tap(); app.buttons.matching(NSPredicate(format: "label == '中文'")).firstMatch.tap()
    XCTAssertTrue(source.label.contains("英语")); XCTAssertTrue(target.label.contains("中文"))
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH '阅读方式'")).firstMatch.tap()
    element(desiredMode).tap()
    let close = element("关闭语言设置"); close.tap()
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in !close.exists }, object: app
    )], timeout: 8), .completed)
  }

  @objc func test01HomePreparationAndLibrary() throws {
    home(); capture("ipad14-home")
    element("开启随屏阅读").tap()
    if element("了解，继续").waitForExistence(timeout: 2) { element("了解，继续").tap() }
    let start = app.buttons["live-start"]
    XCTAssertTrue(start.waitForExistence(timeout: 15)); XCTAssertTrue(start.isHittable)
    XCTAssertFalse(app.buttons["ai-consent-allow"].exists)
    app.buttons["live-mode-options"].tap(); app.buttons["整页对照"].firstMatch.tap()
    app.buttons["live-display-floating"].tap()
    capture("ipad14-reading-preparation")
    app.buttons["share-done"].tap()
    let alice = element("爱丽丝梦游仙境")
    for _ in 0..<10 {
      if alice.isHittable { break }
      app.swipeUp(); Thread.sleep(forTimeInterval: 0.6)
    }
    XCTAssertTrue(alice.isHittable)
    XCTAssertTrue(element("福尔摩斯历险记").exists)
    XCTAssertTrue(element("傲慢与偏见").exists)
    capture("ipad14-public-domain-library")
  }

  @objc func test02PublicWordCardsAndReview() throws {
    home()
    // Explicit opt-in only on this isolated simulator, while all content is public.
    let ai = element("联网 AI 尚未开启")
    if ai.exists {
      ai.tap()
      XCTAssertTrue(element("允许联网 AI").waitForExistence(timeout: 8))
      for _ in 0..<6 {
        if element("允许联网 AI").isHittable { break }
        app.swipeUp()
      }
      element("允许联网 AI").tap()
    }
    sample(); englishToChinese(mode: "学习辅助")
    let cards = element("词卡")
    if cards.exists && cards.isHittable { cards.tap() }
    let save = element("收藏生词")
    XCTAssertTrue(save.waitForExistence(timeout: 20), app.debugDescription)
    for _ in 0..<2 {
      XCTAssertTrue(save.isHittable, app.debugDescription); save.tap()
      Thread.sleep(forTimeInterval: 0.4)
    }
    capture("ipad14-public-context-word-cards")
    let back = app.buttons.matching(NSPredicate(format: "label == '返回' OR label == 'Back'")).firstMatch
    XCTAssertTrue(back.isHittable); back.tap()
    element("生词本").tap()
    XCTAssertTrue(element("开始复习").waitForExistence(timeout: 10))
    element("开始复习").tap()
    XCTAssertTrue(element("查看答案").waitForExistence(timeout: 8))
    element("查看答案").tap()
    XCTAssertTrue(element("认识").waitForExistence(timeout: 8))
    capture("ipad14-review-with-original")
  }

  @objc func test03PublicPairedTranslation() throws {
    home(); sample(); englishToChinese(mode: "整页对照")
    let translated = app.descendants(matching: .any).matching(NSPredicate(
      format: "label BEGINSWITH '译文' AND NOT (label BEGINSWITH '译文语言')"
    )).firstMatch
    // Wide iPad may display the panels side by side without a tab.
    if translated.exists && translated.isHittable { translated.tap() }
    let progress = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH '已翻译 '")
    ).firstMatch
    XCTAssertTrue(progress.waitForExistence(timeout: 15), app.debugDescription)
    let complete = NSPredicate { _, _ in
      let numbers = progress.label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
      return numbers.count >= 2 && numbers[0] > 0 && numbers[0] == numbers[1]
    }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: complete, object: app)], timeout: 100), .completed)
    capture("ipad14-public-paired-translation")
  }
}

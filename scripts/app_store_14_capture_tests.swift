import XCTest

/// Marketing capture only. Runs against the separately installed iOS build 14
/// in a fresh disposable simulator, using the app's public English sample.
/// Every saved item is created by tapping the real user-facing bookmark action.
final class Marketing14Tests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "com.wang.yudu")

  override func setUpWithError() throws { continueAfterFailure = false }
  override func tearDownWithError() throws { app.terminate() }

  private func button(_ label: String) -> XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label)
    ).firstMatch
  }

  private func capture(_ name: String) {
    Thread.sleep(forTimeInterval: 0.8)
    let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    image.name = name
    image.lifetime = .keepAlways
    add(image)
  }

  @objc func testPublicSampleVocabularyAndReview() throws {
    app.launch()
    XCTAssertTrue(button("粘贴文字").waitForExistence(timeout: 35))
    let sample = button("试读一段")
    for _ in 0..<8 {
      if sample.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(sample.isHittable)
    sample.tap()
    XCTAssertTrue(button("词卡").waitForExistence(timeout: 20))
    button("词卡").tap()
    let save = button("收藏生词")
    XCTAssertTrue(save.waitForExistence(timeout: 12))
    for _ in 0..<3 {
      for _ in 0..<3 {
        if save.isHittable { break }
        app.swipeUp()
      }
      guard save.isHittable else { break }
      save.tap()
      Thread.sleep(forTimeInterval: 0.4)
    }
    for _ in 0..<4 { app.swipeDown() }
    capture("marketing14-public-sample-word-cards")

    let back = app.buttons.matching(
      NSPredicate(format: "label == '返回' OR label == 'Back'")
    ).firstMatch
    XCTAssertTrue(back.isHittable)
    back.tap()
    XCTAssertTrue(button("生词本").waitForExistence(timeout: 6))
    button("生词本").tap()
    XCTAssertTrue(button("开始复习").waitForExistence(timeout: 10))
    capture("marketing14-saved-vocabulary")
    button("开始复习").tap()
    XCTAssertTrue(button("查看答案").waitForExistence(timeout: 8))
    capture("marketing14-review-recall")
    button("查看答案").tap()
    XCTAssertTrue(button("认识").waitForExistence(timeout: 8))
    capture("marketing14-review-with-original")
  }

  @objc func testPublicSamplePairedTranslation() throws {
    app.launch()
    XCTAssertTrue(button("粘贴文字").waitForExistence(timeout: 35))
    let sample = button("试读一段")
    for _ in 0..<8 {
      if sample.isHittable { break }
      app.swipeUp()
      // Flutter's scroll inertia is not always reported as an XCTest animation.
      Thread.sleep(forTimeInterval: 1.2)
    }
    XCTAssertTrue(sample.isHittable)
    Thread.sleep(forTimeInterval: 0.5)
    sample.tap()
    if !app.staticTexts["英文试读"].waitForExistence(timeout: 3), sample.isHittable {
      // Retry the same visible control after the scroll has fully stopped.
      sample.tap()
    }
    XCTAssertTrue(app.staticTexts["英文试读"].waitForExistence(timeout: 20), app.debugDescription)
    let language = button("语言与自动更新")
    if language.waitForExistence(timeout: 3) {
      language.tap()
    } else {
      // This frozen build omits the icon tooltip from its accessibility label.
      // Use the actual visible AppBar action: a right-side action with no
      // exam-range label. In full-translation mode the icon moves farther right.
      let action = app.buttons.allElementsBoundByIndex.first {
        $0.isHittable && $0.frame.midY < app.frame.height * 0.15
          && $0.frame.midX > app.frame.width * 0.65
          && !$0.label.contains("四级")
      }
      XCTAssertNotNil(action, app.debugDescription)
      action?.tap()
    }
    XCTAssertTrue(button("关闭语言设置").waitForExistence(timeout: 5), app.debugDescription)
    let sourceLanguage = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH '原文语言'")
    ).firstMatch
    sourceLanguage.tap()
    app.buttons.matching(NSPredicate(format: "label == '英语'")).firstMatch.tap()
    let targetLanguage = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH '译文语言'")
    ).firstMatch
    targetLanguage.tap()
    app.buttons.matching(NSPredicate(format: "label == '中文'")).firstMatch.tap()
    XCTAssertTrue(sourceLanguage.label.contains("英语"))
    XCTAssertTrue(targetLanguage.label.contains("中文"))
    let mode = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '阅读方式'"))
      .firstMatch
    XCTAssertTrue(mode.waitForExistence(timeout: 5), app.debugDescription)
    mode.tap()
    XCTAssertTrue(button("整页对照").waitForExistence(timeout: 5))
    button("整页对照").tap()
    let close = button("关闭语言设置")
    close.tap()
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in !close.exists }, object: app
    )], timeout: 8), .completed, app.debugDescription)
    let translatedTab = app.descendants(matching: .any).matching(NSPredicate(
      format: "label BEGINSWITH '译文' AND NOT (label BEGINSWITH '译文语言')"
    ))
      .firstMatch
    XCTAssertTrue(translatedTab.waitForExistence(timeout: 8), app.debugDescription)
    translatedTab.tap()

    let progress = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH '已翻译 '")
    ).firstMatch
    XCTAssertTrue(progress.waitForExistence(timeout: 10), app.debugDescription)
    let complete = NSPredicate { _, _ in
      let numbers = progress.label.components(separatedBy: CharacterSet.decimalDigits.inverted)
        .compactMap(Int.init)
      // Verify UI flow and completion here. Exported screenshots also require
      // human language/content review before source approval: simulated Vision
      // and Flutter SelectableText did not provide reliable CJK counts.
      return numbers.count >= 2 && numbers[0] > 0 && numbers[0] == numbers[1]
    }
    XCTAssertEqual(
      XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: complete, object: app)], timeout: 90),
      .completed,
      "Capture actual completed translations, never a pending or fabricated result"
    )
    capture("marketing14-public-paired-translation")
  }
}

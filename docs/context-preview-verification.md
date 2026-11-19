# iOS 原句高亮浮窗与最新 UI Beta 验证

日期：2026-11-08 至 2026-11-09，Asia/Macau。用户选择全自动浮窗保留原句并高亮对应词；在现有 Lingfer 工程中实现，保留 UI 窗口的全部改动。

## 实现范围

- 学习辅助浮窗每次展示一条原句片段，目标词加粗着色，下方展示词形与现有释义。长句围绕目标词截取，中文、表情和 UTF-16 范围均保留目标。
- 依据当前帧已有 OCR 行的位置，标明画面上部、中部或下部；无法可靠对应时仅写“当前页面”，不虚构精确坐标。仅保留内存中的行框，不保存原始帧。
- 同页每 10 秒轮换一个词，暂停时冻结当前词与原句；短时识别抖动后回到同页会接着原来的词序，最多保留 8 条历史记录及当前页，仅在内存中保存，停止会清空。轮换与位置更新不调用翻译服务；筛词、语言、收藏、熟词、AI 和 App Group 数据格式沿用现有实现。
- 整页对照浮窗保留对应原文片段与已有译文，按已完成的段落轮换。完整译文仍在语渡原对照面板中查看。
- 删除把灵动岛长按当作保证入口的提示；系统可能优先显示屏幕共享活动，可在通知中心的语渡实时活动或语渡内操作。

## 边界

iOS 的画中画只能在自身窗口内展示内容，无法在微信、其他 PDF 阅读器的原页面上逐词画线。浮窗遮挡处的原文像素不可恢复；本轮真机发现遮挡边缘会返回半截 OCR 词，已将受遮挡的行带剔除，并在系统播放控件短暂盖住识别标记时保留最近测得的排除区域最多 8 秒，避免把残片当成完整原句。被挡文字需要移动浮窗露出后才能重新读到；保守剔除可能也暂时省略同一水平带的另一列文字。

默认翻译应用扩展、导入 PDF 自动原位标注不在本轮实现范围。安卓没有进行新的业务改动，保留用户已认可的功能与最新界面。

## 验证进度

- Flutter 全量 36 项通过（最新 UI 快照）。
- 最新界面 iPhone 15 Pro Max / iOS 27.2 真机 `testRefinedReadingDesign` 通过，用时 24.768 秒。
- 原句截取、跨行连接与词序管理共 23 项断言通过，覆盖长句末尾目标、大小写、中文、表情、极小长度、空文本、缺失目标、10 秒轮换、暂停、同页返回和词数减少。
- 最终 iPhone 原句浮窗真机用例 `testContextualAutomaticPreview` 通过，用时 62.375 秒，0 失败、0 界面运行时警告；结果 `/private/tmp/lingfer-toolchain/context-preview-9-device-10.xcresult`。验证真实 OCR、原句与高亮存在、移开浮窗、暂停冻结、继续、浮窗文本不反馈入原文及停止流程。
- 自动换词人工对照最终真实截图：同一公开文章浮窗从 `1/7 Researchers` 前进至 `3/7 effective`，原句与高亮同步。视频中的文字不是可访问控件，不以二次 OCR 识别小序号代替画面核对。
- 初期失败结果如实保留在本机：包含边缘 OCR 残片，以及自动测试的诊断刷新、系统浮窗遮挡按钮、记忆角落位置、播放控件盖住小序号和结束清理操作问题。最后两轮业务流程分别通过；此处仅以最终代码的第 10 轮为验收结果。诊断状态只在明确开启验收模式时发布语义变化，不对生产界面逐帧发布。
- 分享扩展、收藏／熟词、AI 讲解与 App Group 同步未更改接口或数据格式。完整业务回归沿用（8）的已记录真机结果，见 [阅读浮窗与菜单分类验证](reading-controls-verification.md)；本轮重点复验新增展示、识别排除和生命周期，没有声称重新执行全部云端／分享用例。
- 实际读屏验证使用 Safari 内公开静态英文文章，尚未在本轮直接操作用户微信文章或第三方 PDF；需继续由测试员试读实际场景。
- TestFlight：2.1.1（9）于 2026-11-09 00:11:49 上传成功；00:20 核实原“王业翔内部测试”组两位测试员已可下载，组内状态“正在测试”，新版测试说明已保存并重新加载核实。没有提交正式商店审核。

## 本轮直接修改

`ios/Runner/LiveScreenCapture.swift`、`ios/Runner/LivePreviewExcerpt.swift`、`ios/Runner.xcodeproj/project.pbxproj`、`ios/RunnerUITests/ReadingUITests.swift`、`scripts/check_live_preview_excerpt.swift`、`test/fixtures/context.html`、`pubspec.yaml`，以及本文、验证截图和发布记录。

## 最新 UI 真机截图

[首页](context-preview-screenshots/refined-ios-home.png)、[读屏准备页](context-preview-screenshots/refined-ios-live-ready.png)、[阅读选项](context-preview-screenshots/refined-ios-live-options.png)、[试读](context-preview-screenshots/refined-ios-reading.png)。这些是真机截图，与上一轮的模拟器截图分别保留。

## 最终上下文浮窗真机截图

[初次显示](context-preview-screenshots/ios-context-floating-original.png)、[原句及高亮](context-preview-screenshots/ios-context-floating-after-moving.png)、[暂停保持](context-preview-screenshots/ios-context-paused-original.png)、[继续并自动换词](context-preview-screenshots/ios-context-next-highlight.png)。所有图片来自最终通过的真机测试，未重绘内容。

测试结束已停止 iPhone 屏幕共享，并关闭只提供公开样例的临时网页服务；没有清空用户数据、操作私密应用或创建付费云资源。

## 签名与交付候选

主 App、分享扩展和实时活动扩展均为 `2.1.1（9）`，已严格验证苹果发布签名；主 App 与分享扩展的 `group.com.wang.yudu` 权限同时存在于签名和发布配置中。后台读屏、实时活动声明保留。最终归档 `build/ios/archive/Runner-2.1.1-9-stable.xcarchive`；发布包 `artifacts/Lingfer-2.1.1-9-TestFlight.ipa`，SHA-256 `c85fba5cdcb6e2e252f191c7960bb5d81f482ac3813e38aa425f39524f7bfaf7`。163 个生产源码／资源的归档前后哈希一致，未混入后续修改。

最终下载凭证：[原两人测试组已开放（9）](release-screenshots/testflight-2.1.1-9-ready.jpg)、[已保存的测试说明](release-screenshots/testflight-2.1.1-9-notes.jpg)。状态记录 `artifacts/testflight-2.1.1-9-status.json`。本轮没有提交或推送代码，也没有发布正式商店更新。

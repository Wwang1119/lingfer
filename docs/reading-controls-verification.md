# 阅读浮窗与菜单分类验证

日期：2026-11-08。工作版本：2.1.1（8），沿用现有语渡项目与 Flutter 界面。

## Android

用户确认语言设置正确后原功能能运行。本轮重点为功能分类，不重新设计视觉：

- 主面板：本页词卡／本页译文、暂停／继续、阅读设置、更多；底部独立“停止阅读”。
- 阅读设置：阅读方式、学习范围（学习辅助时）、翻译语言；语言页再分原文和译文。
- 更多：重新识别当前页、回到语渡。每个子页均可返回上一级，不必关闭再打开。
- 原有回调、捕获会话、缓存、词卡及收藏复用。相同语言时保留原文，菜单明确提示并提供修改目标语言入口；不擅自切换目标语言，不再只显示叹号。

Fold5 原位安装（8），数据保留。原生回归通过：菜单分类与返回、语言／范围／停止回调，相同语言不请求服务且保留原文，完整翻译部分失败／重试与缓存，既有词卡三种尺寸／字体验证。真实截图：[主菜单](reading-controls-screenshots/android-menu-root.png)、[阅读设置](reading-controls-screenshots/android-menu-settings.png)。最终测试捕获已通过主 App 正常停止。

## iPhone

已实现授权后自动准备并开启画中画，画中画改为以译文／词义为主，去掉占空间的原屏缩略图。等待 AVKit 源挂载和可播放后再启动，用户关闭浮窗后不反复弹回。持续刷新画中画内容不等于重复请求翻译。

自动浮窗已在 iPhone 15 Pro Max / iOS 27.2 实际出现，测试未点击“显示翻译浮窗”；后台 Safari 页面变化可更新词义。它是系统视频画中画，不能将任意可点击卡片贴到微信的原词坐标。首次实时活动授权界面也已实际看到，系统共享与其他活动会影响灵动岛显示优先级；下拉通知中心是保留的操作路径。

新增独立 WidgetKit 实时活动扩展，摘要最多 3 个词或短段译文，提供暂停／继续、停止和返回词卡。与主 App 共用 ActivityAttributes 和 LiveActivityIntent，由 App 原会话执行操作，不从扩展发起翻译或捕获。系统取消授权时清理准备中的实时活动。已实际看到通知中心的“语渡随屏阅读”卡片，并点击暂停后回主 App 核对会话确实暂停。首次“允许语渡的实时活动？”是独立的系统许可；此前未完成，因此不能只用 Activity.request 成功宣称灵动岛已显示。当前已加入明确提示，授权后停止／清理的真机测试已于后续通过，结果在 `/private/tmp/lingfer-toolchain/ios-auto-island-8-allowed.xcresult`；系统分享／完整翻译／关闭重开恢复也已通过；自动换页与收藏回主 App 在排除来消息遮挡后重新通过；未将失败或未运行测试记作通过。

## 检查与交付

- 35 项 Flutter 测试通过；本轮 Dart 仅修改 iPhone 首次使用说明。
- Android 原生测试通过，真实菜单截图见上方。
- iPhone 新增扩展已通过构建及安装；自动浮窗已实拍并通过对应断言，实时活动卡片及暂停已实测。授权后暂停／继续／停止、释放读屏与画中画的完整测试已通过；原有自动变化与收藏回主 App 也已完成补验。
- TestFlight（7）后续已完成苹果处理，原内部测试组 2 人可下载，说明已保存。（7）没有本轮自动浮窗、灵动岛和新版安卓菜单，不将这些能力写入旧包说明。
- （8）已完成签名归档和导出，核对主 App／分享扩展的 App Group、新实时活动扩展的独立签名及一致版本号；已于 20:52 上传成功并完成苹果处理，原内部组 2 人当前可下载（8），测试说明已保存。[TestFlight 开放凭证](release-screenshots/testflight-2.1.1-8-ready.jpg)。正式 App Store 未提交审核。没有 Git 提交或推送，没有新购云资源或启用账号同步。

## 本轮直接修改文件

- Android：`screen/NativeReadingMenu.kt`（分类与返回）、`screen/PageTranslation.kt`（错误操作入口）、`screen/MultilingualTranslator.kt`（相同语言仍保留原文）、`screen/ScreenReaderService.kt`（明确错误状态）、`NativePanelUiInstrumentation.kt`（分类与原文保留回归）。路径均在 `android/app/src/` 对应源码目录。
- iPhone：`ios/Runner/LiveScreenCapture.swift`（自动浮窗、准备／取消、实时活动状态和自身面板排除）、`ios/Runner/ReadingActivityManager.swift`、`ios/Shared/ReadingActivityAttributes.swift`、`ios/Shared/ReadingActivityIntents.swift`、`ios/LingferActivity/`（独立系统扩展）、`ios/Runner/SceneDelegate.swift`（返回词卡）、`ios/Runner/Info.plist`、`ios/Runner.xcodeproj/project.pbxproj`。
- 展示与测试：`lib/features/companion/companion_shell.dart` 仅更新 iPhone 首次使用说明；`ios/RunnerUITests/ReadingUITests.swift` 增加自动浮窗和实时活动操作测试；`scripts/add_ios_reading_activity.rb` 保留可重复的扩展接入；`pubspec.yaml` 为 2.1.1+8。
- 另一个界面窗口并行更新的 `ShareViewController.swift` 和 `LiveReadingHost` 展示已保留，未覆盖其新启动说明与按钮设计；最终归档源码哈希在 `artifacts/testflight-2.1.1-8-source-manifest.json`。

## 签名与权限

`artifacts/Lingfer-2.1.1-8-TestFlight.ipa` 的严格签名验证通过。主 App、分享扩展和实时活动扩展均为 2.1.1（8），分发配置关闭调试权限并具备 TestFlight 权限。`com.wang.yudu` 与 `com.wang.yudu.LingferShare` 继续使用 `group.com.wang.yudu`；实时活动扩展通过 ActivityKit 接收短摘要，不新增数据库、网络访问或 App Group 文件读写。校验结果与 SHA-256 在同目录。

### 当前已通过的新流程

`testAutomaticPreviewAndIsland` 在真实 iPhone 通过（63.888 秒）：不点画中画按钮即可出现浮窗；实时活动点“始终允许”；暂停后主 App 显示继续识别；原文未被自身活动卡片替换；继续后可更新；实时活动的停止结束捕获、浮窗和活动，主 App 恢复开启入口。第一次和第二次系统提示分别可能为“允许”和“始终允许”。灵动岛是否占据当前可见位置由系统决定，测试保留通知中心操作路径，不把系统共享标识当作语渡自定义图标。

截图：[自动翻译浮窗](reading-controls-screenshots/ios-auto-floating.png)、[共享期间的系统位置与浮窗](reading-controls-screenshots/ios-island-compact.png)、[停止后恢复开启入口](reading-controls-screenshots/ios-stopped.png)。通知中心截图可能包含私人通知，仅保留在本机临时测试结果，不作为交付图片。

另一个界面窗口随后继续修改 Android `ScreenReaderService.kt` 的悬浮按钮外观与面板定位，本窗口的分类回调仍保留；本次已安装的 Android 功能包与截图来自这些后续外观改动之前。iOS 已上传包的生产源码校验保持一致，后续测试辅助改动单独记录在 `artifacts/testflight-2.1.1-8-validation-source.json`。

## 最终验收结果

- `testAutomaticPreviewAndIsland`：66.243 秒，通过；已允许后的新会话、自动画中画、实时活动暂停／继续／停止与释放均实际完成。
- `testLiveCaptureOnDevice`：58.908 秒，通过；实际捕获 A/B 页面变化、原句保留、排除自身界面、收藏回主 App 生词本、停止／返回通过。
- 以上两项最终结果：`/private/tmp/lingfer-toolchain/ios-reading-stable-regression-8.xcresult`，2 项、0 失败。
- `testShareRecordSurvivesRelaunch`：52.612 秒，通过；Safari 分享、整页对照、完成、重新打开恢复的结果在 `/private/tmp/lingfer-toolchain/ios-reading-final-regression-8.xcresult`。该结果包中的早先重复测试受到通知横幅影响，未作为通过证据；新两项以最终包为准。
- 生产 iOS 源码与已上传（8）归档的哈希一致。测试辅助代码只修正轮换样例计时与通知遮挡，后续哈希单列记录；没有借修改 App 逻辑绕过测试。
- 两端测试捕获与本机临时样例服务已停止。正式 App Store 保持原发布状态；未提交正式审核、Git 提交或推送。

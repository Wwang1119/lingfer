# 整页对照与重新连接后的验证

日期：2026-11-08。本轮最终代码为 2.1.1（7），两台真机均已安装。TestFlight 2.1.1（7）后续已完成处理，向原两位测试员开放下载，测试说明已保存。

## 本轮新增与修复

- 在现有语渡中分开“学习辅助”和“整页对照”。默认保留学习辅助，旧设置自动兼容；不改生词、熟词或复习数据结构。
- 整页对照逐段显示原文与完整译文，适用于不以背词为目的的阅读；不按考试范围过滤、不略过熟词、不自动保存段落到生词本。语言由用户选择，同语种时明确提示修改译文语言。
- Flutter 阅读页、Android 悬浮菜单与原生对照面板、iOS 系统分享和实时读屏共用各平台已有的服务与授权路径。iOS 视频画中画仅预览部分译文，完整对照在语渡内查看。
- 完整译文按原文段落和方向缓存，段落换位置仍可复用。失败保留原文与已完成段落；重试只处理缺失段落。校验返回段落 ID，不把遗漏当成成功。Flutter 单次超过 12000 字会提示分段；原生分享沿用最多 12000 字的读取上限。这里的整页指本次已读取的屏幕／分享原文，不代表自动翻完整本文件。
- 原生已译段落通过既有本机／App Group 通道恢复到 Flutter；返回同一原文直接复用，避免再次请求。云账号与远程数据库未开通。
- 修复 Samsung Fold5 小屏启动时短暂零宽导致快捷按钮算出负宽、首页列表空白的问题。保留当前导航与视觉设计；新增零宽到正常宽度的回归测试。
- 自动语言识别先构造主要文字系统的样本，避免少量中文浏览器提示盖过长篇拉丁文字。这里只调整识别样本，原文和 OCR 坐标不变。
- 快速更改语言时立即作废旧请求，并按请求发起时的方向记录缓存，防止旧中文译文被当成新选语言的结果复用。
- 修复 iOS 停止画中画后，系统恢复界面回调可能重新打开已停止面板的问题；读屏已停止时不再恢复。

## 验证进度

| 项目 | 已观察结果 |
| --- | --- |
| Flutter | 35 项测试通过，包含段落完整性、遗漏与重试、缓存与原生结果复用、旧设置兼容、零宽恢复、窄屏大字及已有阅读／复习 |
| Dart 检查 | 新增翻译组件与相关展示文件无问题；控制器的历史括号风格提示单列，不把它算成新功能错误 |
| Android | 原生完整翻译缓存、部分失败与重试、考试范围独立性及原词词卡三种尺寸测试通过；新增识别样本与最终版本回归也已通过，安装保留原应用数据 |
| iPhone 实时流程 | 最终构建（7）的两项真机自动测试均通过。实际通过：系统授权、后台 Safari、页面自动变化、排除自身画中画、完整原句、收藏、视频画中画、停止、返回主 App 生词本 |
| iPhone 分享与整页翻译 | 最终实际测试通过 Safari 分享、3/3 段完整中译、切回学习辅助、完成、关闭并重新打开主 App，原文记录可继续；最终自动测试已同时核对正文 value 并通过；未用失败截图冒充通过 |
| 账号与费用 | 本轮未购买或创建云资源；未把本机与 App Group 同步称为云同步 |

## 本轮直接修改文件

- `android/app/src/androidTest/kotlin/com/wang/lingfer/screen/NativePanelUiInstrumentation.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/MainActivity.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/MultilingualTranslator.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/NativeOcrEngine.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/NativeReadingMenu.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/PageTranslation.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/ReadingOptions.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/ScreenReaderService.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/ScreenReaderState.kt`
- `ios/LingferShare/ShareViewController.swift`
- `ios/Runner/LiveScreenCapture.swift`
- `ios/Runner/ShareStatePlugin.swift`
- `ios/RunnerUITests/ReadingUITests.swift`
- `ios/Shared/CompanionStore.swift`
- `ios/Shared/NativeReadingModel.swift`
- `lib/features/companion/companion_components.dart`
- `lib/features/companion/companion_controller.dart`
- `lib/features/companion/companion_reader.dart`
- `lib/features/companion/companion_shell.dart`
- `lib/features/companion/multilingual_reader.dart`
- `lib/features/companion/page_translation.dart`
- `lib/features/companion/page_translation_view.dart`
- `lib/features/companion/reading_assistant.dart`
- `lib/features/companion/reading_controls.dart`
- `lib/features/companion/reading_preferences.dart`
- `pubspec.yaml`
- `test/companion_ui_test.dart`
- `test/multilingual_reader_test.dart`
- `test/page_translation_test.dart`

## 发布状态与待办

- 2.1.1（7）：已完成签名归档和导出，核对主 App 与扩展的 App Group 权限；19:17 上传成功，19:49 核对仍在苹果处理队列。[（7）处理状态凭证](release-screenshots/testflight-2.1.1-7-processing.jpg)。两台真机已原位安装（7），但 TestFlight（7）尚未开放下载，测试说明已备妥，处理中的编辑框暂不可用。
- TestFlight 2.1.1（6）已向原“王业翔内部测试”组 2 人开放，组内显示“正在测试”，测试说明已保存。它包含独立整页对照、原生段落缓存、Fold5 启动与 iOS 停止画中画修复；（7）补充最终快速切换语言的缓存保护。当前手机已装（7），无需退回（6）。[可下载版本凭证](release-screenshots/testflight-2.1.1-6.jpg)。正式 App Store 仍为 1.2.9，未提交正式审核、Git 提交或推送。
- iOS 完整流程截图已替换为最终构建（7）真机画面；Android 原生面板在同轮构建（6）验证，最终首页来自（7）。真机截图：[iOS 整页对照](page-translation-screenshots/ios-page-translation.png)、[iOS 后台画中画](page-translation-screenshots/ios-background-preview.png)、[iOS 收藏回主 App](page-translation-screenshots/ios-saved-in-app.png)、[iOS 分享后恢复](page-translation-screenshots/ios-share-restored.png)、[Fold5 最终小屏首页](page-translation-screenshots/android-final-home.png)、[Android 阅读菜单](page-translation-screenshots/android-reading-menu.png)、[Android 整页对照](page-translation-screenshots/android-page-translation.png)。
- Android 实屏当前将 OCR 行作为对照片段，跨行长句的段落合并与浏览器工具栏过滤还需优化。它翻译读取到的文字，不保证还原被遮挡／受保护内容。iOS Safari 分享可利用已有预处理取得自然段。
- 账号与跨设备同步仍待低成本资源方案；本机收藏、复习与学习备份可继续使用。主 App 及系统扩展旧入口保留。

## 安装与签名记录

- 安卓最终 2.1.1（7）已安装到 Fold5，保留应用数据；测试捕获已正常停止。
- iPhone 最终构建（7）的两项真实界面测试均通过，结果在 `/private/tmp/lingfer-toolchain/ios-2.1.1-7-regression-retry.xcresult`；Flutter 的 35 项测试也已通过。
- iOS 归档：`build/ios/archive/Runner-2.1.1-7.xcarchive`；安装包：`artifacts/Lingfer-2.1.1-7-TestFlight.ipa`；同目录保留 SHA-256、源码清单、签名验证和测试说明。
- 导出包主 App `com.wang.yudu` 与分享扩展 `com.wang.yudu.LingferShare` 均为 2.1.1（7），分发签名和描述文件含正确 App Group，并关闭调试权限。上传来自同一签名归档。
- 本轮临时局域网英文样例服务和调试转发已关闭；没有清空手机数据或更改系统锁屏设置。

## 后续发布状态核对

2026-11-08 20:34：（7）已完成苹果处理，原内部组 2 人的构建版本页显示“正在测试”，测试说明已保存。[开放测试凭证](release-screenshots/testflight-2.1.1-7-ready.jpg)。上方 19:49 的处理状态保留为时间记录。自动翻译浮窗与灵动岛属于后续（8）改进，未包含在（7）中。

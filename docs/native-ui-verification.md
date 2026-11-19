# 原生面板接入与验证

日期：2026-11-08（Asia/Macau）。继续修改现有语渡工程，未另起项目、提交、推送或发布。本文仅记录本轮原生展示层工作，不将之前的多语言、实时捕获或 Flutter 重设计归入本轮。

## 界面接入

两端原生词卡使用 Flutter 的同一组角色色：背景 `#F5F4EF`、纸面 `#FFFEFA`、正文 `#252C34`、辅助文字 `#68717A`、操作色 `#294963`、分隔线 `#DDDFDC`。词卡圆角 10，Android 面板上角 18，去掉面板中的玻璃、渐变和大投影。原词旁已有的玻璃定位标注继续保留。

- 单词 → 完整基础释义 → 原句 → 讲解／熟词操作。收藏在右上角，至少 48 的点击区域，保存后切换实心图标；再次保存仍调用原来的幂等保存操作。原句重点词加粗并使用墨蓝色。
- Android 顶部“本页词卡／关闭”，范围摘要打开七档列表；非英语沿用已有三档参考难度。“查看全部”只切换当前已识别词卡，选择后调用原来的 `showDetail`。内容滚动、顶部和底部操作固定；关闭面板继续原会话，“停止阅读”调用原有停止入口。
- Android 面板最大高度为屏高 72%，最大宽度 440dp；展开屏宽 ≥680dp 时放在右侧区域，避免把面板居中压在折叠屏中央。矮窗口和大字模式压缩顶栏，保留关闭、范围和停止入口。未新增折痕硬件检测或改变捕获尺寸逻辑。
- iOS 保留系统“语渡阅读／完成”。普通窗口原文／词卡切换，宽度 ≥680 且未使用辅助字号时双栏滚动。学习范围改为一个摘要入口。来源显示现有模型提供的标题／图片／文字描述，不猜测站点和选文类型。
- iOS 最大辅助字号的语言选择转入独立可滚动面板；来源文字随正文滚动，矮窗口压缩顶栏。原文、长词、释义和讲解均允许换行，不缩字强塞。
- 加载、失败和重试保留原句、基础释义和收藏。同步提示就地显示，只有原保存操作报告共享写入成功才显示“已同步到语渡生词本”；原共享降级状态显示“本次收藏尚未同步到主 App”。

## 业务边界

开始修改前保留了本地快照。本轮比对结果：

| 区域 | 边界核对 |
| --- | --- |
| Flutter 展示、控制器及服务文件 | 与开始时逐文件哈希一致 |
| iOS 分享读取、Safari 回退、OCR、`ShareReadingModel` 全部方法 | `ShareViewController.swift` 中展示组件之前的部分逐字一致 |
| iOS `OfflineLexicon.swift`、`CompanionStore.swift`、`ShareStatePlugin.swift`、Safari 预处理 | 逐文件一致；未改 App Group、格式或保存／同步方法 |
| Android 识别与捕获 | 帧接收、稳定等待、OCR 调用、筛词、翻译、坐标标注、缓存和像素指纹方法逐段一致 |
| Android 原有操作 | 收藏、熟词写入、讲解请求、关闭／重新识别／停止仍使用原有实现；范围摘要仅绑定已有偏好项和原有刷新入口 |
| Android 主入口与通道 | `MainActivity.kt`、授权和通道接口保持一致 |
| 配置和云端 | 未改请求、密钥、运行配置、云函数或付费资源 |

## 验证记录

| 项目 | 结果与边界 |
| --- | --- |
| Flutter 回归 | 19 项通过，覆盖原有阅读、收藏、分级、多语言及 UI 状态 |
| Android 构建 | 原 ARM64 debug 构建成功；沿用 `com.wang.lingfer` 和现有版本号 |
| Android 真实服务流程 | Galaxy Z Fold5 / Android 16：跨 App 识词 → 纸面词卡 → 收藏 → Flutter 生词本显示 → 标熟词排除 → 原有“重新学习”恢复；现有服务返回语境讲解 |
| Android 受控组件状态 | 3 组配置全部通过：320×568／正常字号、320×568／1.8 倍字号、829×320／正常字号。实际原生组件验证加载与失败保留原句／释义，重试调用、实心收藏、七档范围和关闭／停止回调 |
| iOS 构建 | 主 App、分享扩展及界面测试构建成功；沿用原应用及扩展标识、iOS 15.5 最低版本 |
| iOS 真实分享流程 | iPhone 18 Pro / iOS 27.2 模拟器：范围摘要 → 原文／词卡切换 → 收藏并提示同步 → 真实 AI 讲解 → 重试 → 熟词排除 → 完成 → 主 App 生词本显示；完整流程通过 |
| iOS 普通字号布局 | 竖屏、横屏、原文滚动、同语种空匹配状态、语言切换和完成流程通过 |
| iOS 最大辅助字号布局 | Accessibility XXXL：竖屏、横屏、语言设置面板、无匹配状态、原文保留和系统完成可达通过；横屏正文区域大于 80pt |
| Android 关闭／停止 | 真机关闭面板后服务继续，旋转后重新定位标注；原生面板的“停止阅读”确实结束捕获服务 |

Android 的受控状态测试使用固定展示数据和回调，不关闭手机网络、不替换服务配置，也不把固定文字当作真实模型回答；真实服务成功路径另行实测。配置中的窄窗口尺寸是原生组件的约束测试，真实 Fold 界面截图另列。iOS 验证为模拟器，不代表真机签名或 App Store 审核通过。

测试中修正了：收藏热区不足、卡片装饰层参与触摸、大字顶栏挤占正文、矮窗口的操作栏过高。自动化滚动在释放前停稳，避免把停止惯性滚动的一次点击误记为按钮操作失败。

iOS 的真实服务成功、加载和重试已操作；原生分享扩展未做实际断网和 App Group 故障注入。其错误分支保留基础释义、原句和收藏按钮的结构已核对，错误文案及共享降级信息仍来自未修改的原模型。不能将 Flutter 或 Android 的受控失败测试算作 iOS 扩展的断网实测。

## 本轮截图

以下均为实际运行截图。Android 为 Galaxy Z Fold5 真机；iOS 为 iPhone 18 Pro 模拟器。受控状态图仍是手机上的实际原生组件，使用固定词条和错误文案验证展示，不是服务返回或设计稿。

| 场景 | 截图 |
| --- | --- |
| Android 展开屏词卡、完整释义与原句重点词 | [android-fold-card.png](native-ui-screenshots/android-fold-card.png) |
| Android 现有服务返回的语境讲解 | [android-explanation.png](native-ui-screenshots/android-explanation.png) |
| Android 横屏面板与固定停止入口 | [android-landscape.png](native-ui-screenshots/android-landscape.png) |
| Android 320dp 窄组件加载（受控） | [android-narrow-loading.png](native-ui-screenshots/android-narrow-loading.png) |
| Android 320dp 窄组件失败（受控，已滚动到错误） | [android-narrow-error.png](native-ui-screenshots/android-narrow-error.png) |
| Android 1.8 倍字号失败（受控，已滚动到错误） | [android-large-error.png](native-ui-screenshots/android-large-error.png) |
| iOS 系统分享词卡 | [ios-share-words.png](native-ui-screenshots/ios-share-words.png) |
| iOS 学习范围摘要展开七档列表 | [ios-learning-range.png](native-ui-screenshots/ios-learning-range.png) |
| iOS 分享原文 | [ios-original.png](native-ui-screenshots/ios-original.png) |
| iOS 现有服务返回的语境讲解 | [ios-share-explanation.png](native-ui-screenshots/ios-share-explanation.png) |
| iOS 完成后主 App 显示收藏 | [ios-share-synced.png](native-ui-screenshots/ios-share-synced.png) |
| iOS 普通字号横屏 | [ios-landscape.png](native-ui-screenshots/ios-landscape.png) |
| iOS 当前范围无匹配词 | [ios-empty.png](native-ui-screenshots/ios-empty.png) |
| iOS 最大辅助字号竖屏 | [ios-portrait-large.png](native-ui-screenshots/ios-portrait-large.png) |
| iOS 最大辅助字号横屏 | [ios-landscape-large.png](native-ui-screenshots/ios-landscape-large.png) |
| iOS 最大辅助字号无匹配词 | [ios-empty-large.png](native-ui-screenshots/ios-empty-large.png) |

Android 完整的 3 组加载／失败／重试收藏截图位于 `artifacts/native-ui-qa/`。所有图均保留设备原始尺寸，没有裁切、重绘或调色。

## 测试交付与恢复

- Android 测试包：`artifacts/Lingfer-2.1.0-native-ui-android-arm64-debug.apk`，沿用 2.1.0+3；已核对与手机安装包 SHA-256 一致：`4d80f0ea6ff0a6816e2a45699fbbc3c8d823b461c85ea4feab69868273db2b3f`。
- 本轮临时收藏和熟词已通过已有操作恢复；不清空生词本、不重建数据库。Android 原有自动识别→中文、托福范围、1.0 字号及竖屏方向已恢复，捕获会话已停止。
- iOS 模拟器辅助字号测试结束后恢复普通字号；原有收藏及熟词恢复，未修改共享格式或应用标识。
- Flutter 界面与业务文件保留开始时版本，未覆盖其他窗口的未提交改动。未提交、推送或发布。

## 修改文件

| 文件 | 本轮内容 |
| --- | --- |
| `android/app/src/main/kotlin/com/wang/lingfer/screen/NativeReadingPanel.kt` | 新增纯展示组件、角色色、词卡、范围摘要、当前词卡选择、加载／失败／重试外观与自适应 |
| `android/app/src/main/kotlin/com/wang/lingfer/screen/ScreenReaderService.kt` | 仅替换悬浮按钮外观、面板构建和窗口布局，连接原有操作 |
| `ios/LingferShare/ShareViewController.swift` | 原生 SwiftUI 展示组件；业务模型和输入处理保持不动 |
| `android/app/src/androidTest/kotlin/com/wang/lingfer/screen/NativePanelUiInstrumentation.kt` | 实际原生组件的受控显示状态与回调测试 |
| `android/app/build.gradle.kts` | 仅增加上述测试运行器配置，未增加生产依赖或修改应用标识 |
| `ios/RunnerUITests/ReadingUITests.swift` | 更新原生分享入口、收藏、重试、熟词和同步断言，增加布局／空状态测试 |
| `docs/ui-handoff.md`、`docs/ui-verification.md`、本文 | 更新本轮接入结果与验证边界 |
| `docs/native-ui-screenshots/` | 本轮真实运行及明确标注的受控组件截图 |

## 尚需业务窗口决定

1. 原生熟词接口目前提供标记，未提供面板内撤销。本轮不新增存储或恢复接口；测试记录通过现有“重新学习”或原控制器方法恢复。若要就地“撤销”，建议以后提供与 Flutter 一致的回调。
2. 分享模型当前不保留 Safari 预处理的 `scope`，无法可靠区分“选中文字”和“可见正文”。本轮沿用模型提供的来源，不自行推断；如需明确区分，建议后续由业务层保留该字段。
3. 非居中、非标准位置的硬件折痕尚未接入专门识别；当前是窗口约束和宽屏靠边布局，不宣称拥有折痕 API 能力。

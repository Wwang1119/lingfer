# iPhone 随屏阅读首次画中画

2026-11-19。TestFlight 2.1.1（15）试用期间，用户再次报告从语渡开启随屏阅读后没有浮窗。具体阅读 App、系统是否已开始捕获、是否收到第一帧和 AVKit 是否已启动，需在同一次复现中确认。此前也发生过在外部 App 看不到结果、返回语渡才看到译文的现象。（15）与（14）的产品功能和 UI 源码一致，差异为隐私清单和书籍资源打包。

## 从正常用户入口复现

1. 在支持项目读屏接口的 iPhone 上记录系统版本、语渡构建号、原有语言及阅读方式。选“随屏阅读 → 浮窗”，先用学习辅助和可离线的英语→中文。系统读屏与联网 AI 分别授权。
2. 完成系统共享授权并按系统流程退出选择器，直接切到 Safari 的公开英文样例。保持正文可见。观察外部 App 上是否真正出现画中画，记录首次出现时间与界面状态。自动化用例观察窗口为 30 秒。记录是否能看到画面、是否有词义，这两个结果分别判定。
3. 再测试整页对照（按需启用联网 AI）、切词或段落、回语渡并重新切出、停止并再次开始。记录停止后的捕获和画中画状态，结束后恢复原语言及阅读偏好。

## 沿同一会话追踪

- `ios/Runner/LiveScreenCapture.swift` 包含 `LiveReadingSession.start`、`SystemScreenCapture` 的选择器／捕获回调、`didStart`、`receive`、`attachPreview(to:)`、`requestAutomaticPreview`、`startPreparedPreview` 和 AVKit 启停／失败代理。结合 `LivePreview` 与 `SceneDelegate.swift` 核对授权返回、前后台通知、宿主视图重复更新及窗口挂接的顺序。
- `didStart` 会清理先前的 PiP 控制器与观察，并重置就绪状态。请验证本次是否随后重新挂接，以及准备控制器、后台启动请求、首个有效帧与正文识别事件的到达顺序。这里是待验证的假设。`recordStartupDiagnostics` 已有窗口、图层、首帧计数、音频、OCR、PiP possible/active 及错误码等字段。优先复用这些字段，只保留事件时序、数值和状态，公开记录仅用随项目提供的样例。
- `ios/RunnerUITests/ReadingUITests.swift` 中 `testOneTapPresentationAndAutomaticDock` 保留历史名字，覆盖首次外部画中画。`waitForActualLivePiP` 通过截图 OCR 搜索“点浮窗”，需要用系统画面和代理状态交叉判断，避免文案识别误判。`testPiPSystemPassageNavigation` 覆盖整页翻段，`testRestoreUserReadingAfterFixtureQA` 用于恢复设置。先验证普通启动，再跑带 QA 参数的路径。
- 用 Mac 在仓库根目录运行 `python3 -m http.server 9039 --directory test/fixtures`。在测试运行器的环境变量中设置 `LINGFER_FIXTURE_BASE_URL` 为手机可访问的服务器根地址，先用 iPhone Safari 打开其中的 `stable-scroll.html` 验证网络。Xcode 可在测试方案的 Test → Arguments → Environment Variables 配置该值。命令行真机测试可通过 `TEST_RUNNER_LINGFER_FIXTURE_BASE_URL` 传给测试运行器。仅在这些公开样例页面采集验证画面。

## 既有结果与交付要求

11 月 16 日准备页／返回的模拟器用例 2/2 通过。此前真机的首次浮窗、整页段落导航用例各有一次失败，后续版本尚缺覆盖两项的真机通过结果。该版本目前仍在内测。新窗口优先找出阻止自动启动的首个环节并做针对性修复。报告复现条件、原因或剩余假设、修改文件及实际运行结果。独立注明模拟器、真机以及缺少设备时留待复核的项目。正式提交审核等待用户验收。

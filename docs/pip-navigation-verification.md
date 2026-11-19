# iOS 浮窗前后切换验证

日期：2026-11-10～12。用户授权先跑通现有项目的浮窗操作链，保留学习辅助与整页对照；不进行正式 App Store 发布。

## 本轮实现

原实现只有 AVKit 的 skip delegate，播放范围始终为正无限时长，没有独立控制时钟；原回归没有使用系统浮窗里的快进／快退按钮验证词卡。这轮继续使用公开 AVKit API：

- `LivePreviewPlayback` 为本页结果生成有限范围，每项 30 秒虚拟槽位，两端留余量，沿用原先循环前后浏览。没有内容或仅一项时关闭无效跳转。
- `AVSampleBufferDisplayLayer.controlTimebase` 使用静止的独立时钟；卡片改变时清掉待呈现队列、移动时钟并呈现新帧，再完成系统跳转回调。
- 有独立时钟时不再混用 `DisplayImmediately`；视频帧时间戳与时钟保持一致。
- 当结果数量、当前位置或暂停状态改变时刷新 PiP 播放状态。跳转仅调用原有 `moveSelection`，不调用翻译／筛词接口。
- 浮窗文字准确说明“点浮窗 · 快退上一词／快进下一词”，译文模式对应前后译文。按钮外观、显示／隐藏和系统进度条仍由 iOS 管理。
- 实际点击系统跳转及恢复浮窗后，短暂保留已有源文字，避免控制层遮挡变化被当作换页。首次读屏不增加该等待。几何快照编号变化不再提前清空手动选择，只有实际接受新源文字时才重置游标。

## 用户操作

1. 开启随屏阅读并选择“浮窗＋灵动岛”，回到文章。
2. 点一下浮窗的正文区域，显示系统播放控制。
3. 左侧“快退”是上一项，右侧“快进”是下一项；学习辅助切词，整页对照切译文。
4. 系统图标上的“10”沿用播放器样式，语渡将一次操作映射为一项；并非等待 10 秒才切换。
5. 回语渡查看完整结果后，再回文章，保留内容并恢复浮窗。停止阅读仍用语渡已有停止入口。

## 验收范围与状态

目标设备为已连接的 iPhone 15 Pro Max / iOS 27.2。所有源文章为本机自写公开样例。实际快进、快进、快退三次操作连续留在 Safari 前台，不在每次操作之间打开语渡，也不调用诊断页面上的上一项／下一项按钮。结束后核对只有 AVKit delegate 能递增的操作计数、最终游标、翻译请求次数及画面状态，并额外等待短暂保持期结束，确认没有延迟重置。

早期候选的连续操作暴露同页 OCR 快照误判导致游标重置，已修正为接受源文字时才重置。最终生产源码两文件的散列与中文、英文、译文测试时一致；没有用早期候选的通过替代最终结果。

| 最终真机用例 | 结果 | 连续导航和请求证据 |
| --- | --- | --- |
| 中文→英语词卡 | 61.367 秒，通过 | 5 项，游标 2→3→4→3；系统跳转回调 3 次；翻译请求保持 1 次 |
| 英语→中文词卡 | 57.865 秒，通过 | 6 项，游标 0→1→2→1；系统跳转回调 3 次；使用本地词表，请求保持 0 次 |
| 自动识别→英语整页译文 | 58.981 秒，通过 | 5 项，游标 0→1→2→1；系统跳转回调 3 次；正文请求保持 3 次，配套词汇请求保持 1 次 |
| 恢复阅读偏好 | 20.774 秒，通过 | 停止捕获，恢复自动识别→英语、整页对照、浮窗＋灵动岛 |

以上“请求保持”比较开始导航与结束导航的计数，不代表首次识别只请求一次。三种导航均额外等到 3 秒保持期结束后才核对游标，并覆盖回 App、再回 Safari、恢复浮窗和停止。英文／译文最终回归为 2026-11-12，中文最新生产源码回归为 2026-11-11。英文和译文复用已编译的同一生产源码测试包；本轮另补测试菜单展开的等待／按需重试，未改变生产逻辑。真机结果无运行时警告。

结果包：`pip-12-navigation-accepted-source.xcresult`（中文；后续用例在菜单准备阶段失败，分别补测），`pip-12-words-nov12-retry.xcresult`（英文），`pip-12-passages-nov12-retry.xcresult`（译文及偏好）。此前工具缓存缺失导致的构建中断、一次自动化初始化超时均保留原日志，不计为功能通过。

12 张原始真机截图位于 `docs/pip-navigation-device-screenshots/`，映射与散列见 `artifacts/pip-navigation-device-proof.json`。示例：[英文下一词](pip-navigation-device-screenshots/pip-words-after-skip-1.png)、[中文下一词](pip-navigation-device-screenshots/pip-chinese-words-after-skip-1.png)、[译文下一项](pip-navigation-device-screenshots/pip-passages-after-skip-1.png)、[返回文章后恢复](pip-navigation-device-screenshots/pip-passages-restored-after-return.png)。没有拼接、补画或替换浮窗内容。

纯策略／稳定性脚本 40 项通过，覆盖 0／1／多项、首末项可跳转范围、结果数量变少与反向时钟位置，以及已有滚动／语段策略。系统按钮、渲染、恢复和请求计数仍以真机用例为准。

## 修改文件

- `ios/Runner/LiveReadingViewport.swift`：有限范围计算。
- `ios/Runner/LiveScreenCapture.swift`：时钟、帧时间戳、系统按钮状态、导航与同页保持。
- `ios/RunnerUITests/ReadingUITests.swift`：实际系统按钮回归与测试结束停止捕获。
- `scripts/check_live_reading_stability.swift`：边界断言。
- `pubspec.yaml`：仅从 2.1.1+11 改为 2.1.1+12。
- `README.md`、本文件、`docs/ios-reading-redesign.md`、`docs/ui-handoff.md`、`docs/ui-verification.md`、`docs/app-store-release-preparation.md`：能力、验收、打包与遗留事项交接。
- `docs/pip-navigation-device-screenshots/`、`artifacts/pip-navigation-*.json`、`artifacts/testflight-2.1.1-12-*.json`／测试说明及商店准备状态：原始截图、源文件冻结和实际进度。
- Flutter 页面、Android、服务接口、密钥、数据库及收藏格式不由本轮改动。

## 保留的边界

- 不提供覆盖其他 App 的自定义可点击按钮层。灵动岛的展开和共享指示优先级仍由系统决定。
- 不据公开文章短时回归承诺所有小说 App、受保护页面和长期后台均无问题。
- 首段被浮窗遮挡、OCR 丢字、段落定位及真实网络耗时仍是后续改进项；这轮优先完成可操作的基础链路。
- TestFlight 2.1.1（12）已于 2026-11-12 晚间上传、完成苹果处理，并向原“王业翔内部测试”组两位测试员开放，测试说明已保存。（11）不含本轮修复；正式发布仍等待用户确认。

## 本机打包环境恢复

2026-11-12，原 `/private/tmp/lingfer-toolchain` 的工具源码及部分插件被临时目录清理，导致首次构建在 `device_info_plus` 缺少头文件处中断。已将 Flutter 迁到比赛目录下持久的 `.toolchain/flutter-3.47.9/flutter`，插件使用本机标准 `~/.pub-cache`；不要继续引用旧临时目录。

恢复版本仍为 Flutter 3.47.9 / Dart 3.13.7，官方 Git 提交 `c197ca5199e9ee5661e865596c9c07294dfab51c`。Dart 和完整 iOS 引擎归档核对官方校验信息及解压完整性后恢复；缺少的 `epubx 4.0.0` 按项目锁定 SHA-256 恢复。Flutter 自身的 iOS 缓存检查、离线依赖恢复和 iOS 配置生成均通过，`pubspec.lock` 未变化。运行时密钥只从原配置传入，没有改写。

（12）生产源文件冻结为 `artifacts/testflight-2.1.1-12-source-manifest.json`，165 项；相对（11）只包含本轮两个 iOS 逻辑文件和 `pubspec.yaml` 的构建号变化。`artifacts/testflight-2.1.1-12-status.json`、`artifacts/testflight-2.1.1-12-notes.txt` 分别记录归档／上传实际状态与内部测试说明。

## （12）交付进度

- 归档：`build/ios/archive/Runner-2.1.1-12-pip-navigation.xcarchive`，2026-11-12 00:44 创建，`ARCHIVE SUCCEEDED`。归档后 165 项散列再核对一致。
- 主 App、LingferShare、LingferActivity 均为 2.1.1（12）；`codesign --verify --deep --strict` 通过。
- 已通过开发工具将该归档直接安装到用户连接的 iPhone，未清空原应用数据。此安装不等于 TestFlight 已上传或可下载。
- 命令行导出上传返回 `Failed to Use Accounts`，后续通过系统界面自动化操作 Xcode Organizer，选择标准 App Store Connect 分发，成功完成签名准备与上传。未手动创建、撤销或导入证书；未选择 TestFlight Internal Only。
- 2026-11-12 21:50，苹果接收（12）；随后二进制显示“已验证”，测试组构建页显示“2.1.1 (12)／正在测试”，原内部组仍为 2 位测试员。构建标识：`6bb5644e-4cf5-4fc6-bf49-b8a6dd35475a`。
- 简体中文测试说明已显示“已保存”。正式商店草稿、宣传图和原（11）归档保留，未提交正式审核。
- 凭证：[Xcode 上传成功](../artifacts/testflight-2.1.1-12-xcode-uploaded.png)、[测试组已开放](../artifacts/testflight-2.1.1-12-available.png)、[说明已保存](../artifacts/testflight-2.1.1-12-notes-saved.png)。上传后二进制签名信息见 `artifacts/testflight-2.1.1-12-signing-verification.json`，最终源文件 165 项散列仍一致。

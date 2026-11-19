# 阅读控件与运行流程后续修订

建立于 2026-11-14，状态更新于 **2026-11-16（Asia/Macau）**。**TestFlight 2.1.1（14）已上传并处理完成，原“王业翔内部测试”两人组“正在测试”，可下载；测试说明已保存并重开核对一致**。最终归档及严格签名检查通过，见 [最终源摘要与归档记录](../artifacts/testflight-2.1.1-14/source-manifest.json)；[上传成功](../artifacts/testflight-2.1.1-14/xcode-uploaded.png)、[内部组可下载](../artifacts/testflight-2.1.1-14/available-internal-group.png)、[最终状态](../artifacts/testflight-2.1.1-14/status.json)已留档。同编号较早快照已装入物理 iPhone 做局部验证，本次恢复面板修订仍待最新真机回归；用户明确要求先推 Beta、下次再测真机。未提交正式 App Store 审核或发布。用户对运行流程的新要求优先，不能用同编号旧截图或局部测试代替当前真机验收；其他窗口未提交改动保留，未提交或推送代码。

## 当前流程与保留实现

### iOS 随屏阅读：恢复原生面板，撤回 Dock

用户已明确拒绝新加的“现在可切换／管理阅读”Dock 和授权后自动关闭面板。当前已移除整套 Dock、主页替代预览卡及自动 dismiss，恢复**授权后留在原来的 native 阅读面板**；由用户自行切换到想读的 App，原面板继续提供原有阅读、暂停、浮窗和停止操作。不要在后续接入或宣传中重新恢复已撤回的流程。

准备文案改为：“授权后可切换到想读的App。停稳页面，即可查看阅读结果。”。原生 toolbar 返回箭头使用 `buttonStyle(.plain)`，避免系统按钮玻璃与已有玻璃底叠成两层；44pt 点击热区仍是验收要求。11 月 16 日模拟器新图已确认返回只有一层系统玻璃，没有重叠；物理 iPhone 的点击几何仍待复验。

浮窗／灵动岛仍是两个独立显示方式，阅读方式与语言方向继续并列。原生面板和视频绘制保留浅色纸面、墨蓝操作色及选择胶囊，不把 iOS 画中画描述成 Android 可任意覆盖原文字词的系统悬浮层。切换幂等、音频启停串行、测量／分页缓存和重复重绘合并保留，但**首次跨 App 自动 PiP 仍有失败，不能据代码接入或局部测试宣布体验稳定**。

手选词／译段后固定几何基线，按可靠净位移恢复自动跟随，不把 OCR 抖动不断累加成滚动距离；当前词／片段仍可见时优先保留。主任务本轮 75 项稳定性检查覆盖固定锚点等边界，不能替代真机轻滑、手选与跨 App 流程的验收。

### 书内方向、原文定位与错误恢复

翻译缓存按方向隔离，核对原文和目标语言；切换方向不再复用不匹配的注释。请求按方向与代次检查，旧请求晚返回只能进入自己的缓存，不覆盖当前方向正文。既有可兼容缓存按校验规则读取，没有据此清空全部阅读记录。

分页按原文位置重新定位，注释区间与原文区间分别维护。`ReadingText` 接收显式 `annotations`，横向分页和竖向阅读均传入该列表，没有新注释时传空列表。只有真正插入的译文着墨蓝，原著自带英文括号保留普通正文颜色与字号，不再因“遇到括号就着色”被误认为英译英注释。

失败保留原文并显示“注释暂未生成 · 点此重试”；等待使用真实请求状态。工具、设置或选文面板出现时收起底部状态，避免压住菜单。

### 字体、紧凑控件与联网 AI 选择

`LingferDisplay` 只有 740 个码点，缺少“工具”等界面字。本轮保留已完成的修正：所有界面标题用 `interfaceHeading`／系统字体，首页“语渡”单独用 `brandHeading` 和原显示字体子集；原字体及 OFL 许可保留，没有新增远程字体依赖。

书内工具继续使用紧凑玻璃按钮；七档范围从单个摘要展开较小、可滚动列表，移除冗长说明，保留至少 48dp 热区、大字换行和横屏适配。公版书区与动态书名不依赖不完整的品牌字体。管理页完成文字保持横向尺寸防折行；准备页返回箭头这次新增 plain 样式，不能拿旧截图证明这项新修正已经验收。字体依据见 [字体与控件修订](reader-controls-font-refinement.md)。

可选联网 AI 许可及本机学习数据保护保留。系统读屏授权与允许把相关文字通过腾讯云中转交给 DeepSeek 是两项不同选择；不因撤回 Dock 而撤回 AI 告知，也不把旧核心阅读截图当成新许可已实机验收的证明。

### 11 月 16 日准备页 UI 与 AI 说明入口

新模拟器用例 **2/2 通过**：`testIndependentReadingSetupControls` 57.760 秒，`testReadingPreparationReturnAndOptionalConsent` 27.693 秒。后者确认打开准备页没有擅自出现 AI 说明、开始按钮和唯一返回可点，用户可主动打开联网 AI 说明、选择仅本机阅读并返回首页。四张 [真实模拟器原图及来源](ui-screenshots/native-startup-return-nov16/README.md)已保存，单层返回玻璃已目视确认；没有开始系统读屏，不将其记成 PiP 或灵动岛通过。

当前 `ShareViewController.swift` 两处 `onAppear` 只刷新许可状态，去掉自动设置 `aiConsentOpen`，防止授权回来再弹另一张 sheet 覆盖阅读。未许可默认禁用网络的行为保留，点击“联网 AI”仍可主动进入说明。最终真机测试构建已通过，但物理 iPhone 离线、重连询问未获确认，**授权后覆盖 sheet、first PiP 与灵动岛的真机结果仍待补**。

### 本地存储：已实际清理缓存，旧示例另记边界

设置保留缓存大小与“清理阅读缓存”。服务只统计／清理临时目录 `lens_cache`，不进入根链接，内部链接只解除自身，不跟随目标；不扫描或删除导入原件、扫描 OCR、SharedPreferences、生词、进度或书签／高亮。

此前真机存储用例已按授权实际点击清理，缓存 **7.8 KB → 0 B**。设备没有旧 mock，日志为 `legacyMocksRemoved=false`，所以**旧示例归档与撤销没有真机执行证据**。它仍只处理 `BookSource.mock`，备份后移出书架并允许用原 `Book` 撤销；真实导入、完整内置书和 marks 保留，相关边界由 Flutter／文件系统测试覆盖。不能将缓存清理通过外推为逐项检查了用户所有导入文件。详见 [存储清理边界](reader-storage-cleanup-verification.md)。

## 当前验证状态

| 检查 | 已得结果与边界 |
| --- | --- |
| Flutter 当前全套 | **102 项通过，0 失败**；`/private/tmp/lingfer-toolchain/release14-consent-full-tests.log`。包含方向缓存、晚返回、显式注释、数据保护及许可相关用例；不再与早先 90 项重复相加。 |
| 原生稳定性检查 | **75 项通过**，主任务本轮执行记录；对应 `scripts/check_live_reading_stability.swift`。纯逻辑／稳定性检查，不是 75 项 iPhone 系统读屏用例。 |
| 最终归档／严格签名 | **通过**；`build/ios/archive/Runner-2.1.1-14-nov16.xcarchive`，`codesign --verify --deep --strict` exit 0，见 [最终源摘要与归档记录](../artifacts/testflight-2.1.1-14/source-manifest.json)。 |
| TestFlight 内部下载 | **2.1.1（14）可下载**，原两人组“正在测试”；[状态凭证](../artifacts/testflight-2.1.1-14/status.json)。[测试说明](../artifacts/testflight-2.1.1-14/what-to-test-zh-Hans.txt)已保存并重开核对一致。 |
| 11 月 16 日原生准备／返回模拟器 UI | **2/2 通过、0 失败**：独立准备控件 57.760 秒，返回与可选许可 27.693 秒；`/private/tmp/lingfer-toolchain/return-glass-nov16.xcresult`。不开始系统读屏。 |
| 最新真机测试构建／连接 | **TEST BUILD SUCCEEDED**；`/private/tmp/lingfer-toolchain/release14-return-consent-final-build-nov16.log`。手机当前离线，尚未完成新真机回归。 |
| 11 月 15 日恢复面板测试构建 | **TEST BUILD SUCCEEDED**；`/private/tmp/lingfer-toolchain/release14-restored-panel-build-nov15.log`。构建成功不等于首次 PiP、灵动岛或完整真机流程已通过。 |
| 此前真机全页＋本地会话 | `testFullPageCaptureAndLocalSessionHistory` **67.114 秒通过**。仅公开样例，不能外推所有 App／页面均读全。 |
| 此前真机词卡 PiP 导航 | `testPiPSystemWordNavigation` **89.704 秒通过**；不代替首次自动出现和段落导航。 |
| 此前真机用户状态恢复 | `testRestoreUserReadingAfterFixtureQA` **4.955 秒通过**。 |
| 此前真机存储清理 | `testStorageCleanupAuthorizedNov14` **10.060 秒通过**；实际缓存 7.8 KB → 0 B，未执行旧 mock 归档。 |
| 未关闭的真机失败 | 首次自动 PiP **67.597 秒失败**；段落 PiP 导航 **66.908 秒失败**。同期六项合计 **4 过、2 败**，结果包 `/private/tmp/lingfer-toolchain/release14-consent-device.xcresult`，日志同前缀 `.log`。 |
| 恢复面板后的最新回归 | **仍待主任务确认，不记录为通过**。11 月 15 日的 `/private/tmp/lingfer-toolchain/release14-restored-panel-device-nov15.log` 曾因找不到 iPhone 目标未启动用例，这不是功能通过或功能失败；应以之后实际运行结果为准。历史用例名 `testOneTapPresentationAndAutomaticDock` 不代表当前产品仍有 Dock。 |
| 当前真实图像与商店素材 | 较早 [八张模拟器图](ui-screenshots/reader-controls-followup-nov14/README.md)只对应当时书内／准备页。01 已批准采用最新真实 iOS 首页，文案“随屏与资料，从这里开始”；02 使用最新正确独立准备页，不再等待 PiP 图。[03–06 核心画面](../artifacts/app-store-2.1.1-14/README.md)保留真实 iOS 来源。六张中屏／大屏图均已上传商店草稿，刷新核实两档 **6/10**、顺序正确；[状态与凭证](../artifacts/app-store-2.1.1-14/store-upload-status.json)。构建（14）已选择保存，保留手动发布，未添加以供审核。 |

上述四项物理 iPhone 通过均发生在撤回 Dock 的最新修订之前。它们保留为已得证据，不作废，也不能覆盖新流程的首开、显示方式切换或停止／恢复回归。Flutter 与原生检查分别记录，不能合并成“完整真机验收通过”。

## 较早快照：保留历史，不当作当前最终封包

11 月 14 日较早快照的全套 90 项、两项独立模拟器 2/2（书内 24.935 秒、原生准备 31.677 秒）、单独 Runner Release 及 `codesign --verify --deep --strict` 当时均通过。相关 [验证清单](../artifacts/reader-controls-nov14-followup/verification.json)、[16 项源摘要](../artifacts/reader-controls-nov14-followup/source-manifest.json)及 `/private/tmp/lingfer-toolchain/reader-followup-final-release.log` 保留原始事实，**不是本次最后修改后的最终归档、签名或完整源摘要**。

旧八图可核对当时的系统标题、紧凑控件、墨蓝中文释义及无长说明范围列表；该组 Alice 样例没有原著英文括号，括号样式由专项测试覆盖。旧准备图中的“授权后会收起此面板”已被用户撤回，不能用作当前流程或正式宣传素材。原生返回单层玻璃现由 11 月 16 日新模拟器原图核对；它仍不是物理 iPhone 或系统 PiP 的证据。

## 主要文件

| 文件 | 本轮作用 |
| --- | --- |
| `ios/Runner/LiveScreenCapture.swift` | 恢复授权后保留原 native 面板、移除 Dock；保留显示方式协调、音频串行、固定选词几何锚点、重绘合并和浅色控件。 |
| `ios/LingferShare/ShareViewController.swift` | 原生纸面、系统标题、返回 plain 样式及玻璃控件；测量／分页缓存和分享阅读。 |
| `lib/screens/reading/reading_screen.dart` | 方向与请求代次隔离、原文锚点及注释区间、失败重试和紧凑阅读工具。 |
| `lib/services/ai_translation_service.dart`、`reader_translation_cache.dart`、`reader_text_anchor.dart` | 方向校验、缓存原文绑定和原文／注释位置映射。 |
| `lib/features/companion/lingfer_theme.dart`、`companion_shell.dart` | 系统界面标题／独立品牌标题、公版书标题和设置存储入口。 |
| `lib/widgets/book_reader_presentation.dart`、`apple_glass_sheet.dart`、`reading_text.dart` | 紧凑玻璃按钮、范围列表、共享选文及正文展示。 |
| `lib/services/reader_cache_storage.dart`、`lib/features/companion/reader_storage_controls.dart`、`lib/app/app_state.dart` | 限定缓存清理、大小与错误状态、旧 mock 归档及原记录撤销。 |
| `lib/services/ai_consent_store.dart`、`lib/widgets/ai_consent_panel.dart`、原生共享许可状态 | 可选联网 AI 告知、仅本机阅读选择及许可状态同步，独立于系统读屏授权。 |
| 方向／注释／数据保护与界面测试 | 方向、晚返回、缓存、原文定位、数据保护、撤销、窄屏大字和已有流程回归；均保留原验证边界。 |

## 尚待完成

1. 在实际连接的 iPhone 上验证恢复原生面板后的 **first PiP**：授权后不自动关闭面板、不出现 Dock；正常切到其他 App，首次浮窗能自行出现，不靠回 App 再切出恢复。
2. 继续核对段落 PiP 导航、灵动岛显示与切词、手选／轻滑锚点、返回后恢复、暂停／停止，并在物理 iPhone 核对返回点击区域与管理页完成文字。返回单层玻璃已有本次模拟器新图，不据此跳过真机。
3. 旧 mock 归档／撤销若设备确有对应记录再做真机验收；不能为了补测试制造或删除用户资料。已完成的缓存清理不要再误记为“未执行”。
4. 正式审核仍待用户验收：最终归档、严格签名、TestFlight 下载以及新版六张宣传图两档上传均已完成。已选构建（14）并保存、保留手动发布，未添加以供审核；干净的 PiP／灵动岛宣传实拍以后补充，不用不合格图替代。

**本轮最新真机验收尚未完成；用户已明确授权“目前连不上，你直接推送吧，下次再做真机测试”。** 主任务已据此完成（14）内部 Beta 上传，苹果处理完成，原两位测试员可下载。已知 first PiP／段落导航失败与待测项目继续保留，不据下载状态宣布修复；正式 App Store 审核／发布未提交。六张海报中屏（1206×2622）／大屏（1320×2868）均已上传并刷新核实，每档 6/10；[上传状态](../artifacts/app-store-2.1.1-14/store-upload-status.json)与[刷新后页面](../artifacts/app-store-2.1.1-14/store-media-after-reload.png)已留档。旧大屏仅移出草稿、素材库保留，构建（14）已选择保存，手动发布，未添加以供审核。

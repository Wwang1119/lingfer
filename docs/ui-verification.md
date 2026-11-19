# UI 验证与截图

## 当前优先：11 月 17 日，候选（15）与 18 张商店图

| 项目 | 当前实得状态与边界 |
| --- | --- |
| 内部 TestFlight | **2.1.1（15）可下载**，原两人组“正在测试”；[状态](../artifacts/testflight-2.1.1-15/status.json)、[原组凭证](../artifacts/testflight-2.1.1-15/available-internal-group.png)。草稿已选（15）保存、手动发布，未添加以供审核。 |
| （15）相较（14） | 仅 `pubspec.yaml` 构建号及旧两本 EPUB／占位 PDF 退出打包，加共享隐私清单两类型声明；**UI／功能源码未变**。[包内检查](../artifacts/testflight-2.1.1-15/package-verification.json)确认三本英文书保留、旧包资源不在、清单和签名通过。下方旧回归不改称为（15）新跑。 |
| App 隐私标签 | **已发布并重载核对**；Other User Content 与 Browsing History 均 App Functionality＋Other Purposes、关联身份 Yes、跟踪 No；[凭证](../artifacts/app-store-2.1.1-14/privacy-labels-after-reload.png)。腾讯云线上实际日志／留存配置仍待登录核实。 |
| iPhone／iPad 素材 | 中屏 6＋大屏 6＋iPad 6，共 **18 张**已上传重载，每组 6/10；[上传记录](../artifacts/app-store-2.1.1-14/store-upload-status.json)、[iPad 后台凭证](../artifacts/app-store-2.1.1-14/store-ipad-after-reload.png)。图片来源如实保持 sourceBuild14，没有把手机图拉伸充平板。 |
| 真实 iPad UI 采集 | （14）生产快照 182/182 项构建前后匹配；首页／准备／公版书 53.400 秒、词卡／真实收藏复习 58.605 秒、双栏英中对照 56.221 秒，**3/3 通过**；[来源与独立 QA](../artifacts/app-store-2.1.1-14/IPAD-README.md)。仅证明 App 内 iPad 布局，不证明物理 iPad 首次 PiP／灵动岛。 |
| 未完成边界 | 用户试 Beta 后再定上架；首次 PiP 等真机测试已同意下次补。第三方内容版权声明主任务仍在处理；现有 148 可供应／27 不可供应地区未改动。未正式审核／发布，不称全部就绪。 |

当前发布资料以 [商店更新准备](app-store-release-preparation.md) 为准；以下保留（14）实际回归与既知失败，不能将（15）可下载、标签发布或素材上传当作这些失败已关闭。


## 11 月 16 日（14）功能与 UI 验证历史（最新分发状态以上方为准）

完整实现、主要文件与遗留见 [阅读控件与运行流程后续修订](reader-controls-followup-nov14.md)。**TestFlight 2.1.1（14）已上传并处理完成，原“王业翔内部测试”两人组“正在测试”，可下载；测试说明已保存并重开核对一致**。恢复面板的新修订仍待真机回归，按用户授权下次补测；未提交正式 App Store 审核或发布。

用户最新要求优先：已移除新增阅读 Dock 和授权自动收起，恢复授权后保留原 native 阅读面板。准备文案为“授权后可切换到想读的App。停稳页面，即可查看阅读结果。”；toolbar 返回箭头使用 plain 样式，避免按钮与系统玻璃叠两层。字体、紧凑控件、方向缓存、原文锚点、显式译文区间、失败重试、限定缓存清理及可选联网 AI 许可保留。

| 检查 | 已得结果与快照边界 |
| --- | --- |
| Flutter 当前全套 | **102 项通过，0 失败**；`/private/tmp/lingfer-toolchain/release14-consent-full-tests.log`。较早 90 项已被此全套包含，不重复相加。 |
| 原生稳定性检查 | **75 项通过**，主任务本轮执行记录；脚本 `scripts/check_live_reading_stability.swift`。纯检查不等同于 iPhone 系统 PiP 已通过。 |
| 最终归档／严格签名 | **通过**；最终归档 `build/ios/archive/Runner-2.1.1-14-nov16.xcarchive`，`codesign --verify --deep --strict` exit 0，见 [最终源摘要与归档记录](../artifacts/testflight-2.1.1-14/source-manifest.json)。 |
| TestFlight 内部下载 | **2.1.1（14）可下载**，原两人组“正在测试”；[上传凭证](../artifacts/testflight-2.1.1-14/xcode-uploaded.png)、[内部组凭证](../artifacts/testflight-2.1.1-14/available-internal-group.png)、[状态](../artifacts/testflight-2.1.1-14/status.json)。[测试说明](../artifacts/testflight-2.1.1-14/what-to-test-zh-Hans.txt)已保存并重开核对一致。 |
| 11 月 16 日模拟器原生 UI | **2/2 通过、0 失败**：独立准备控件 57.760 秒，返回与可选许可 27.693 秒；`/private/tmp/lingfer-toolchain/return-glass-nov16.xcresult`。只验证准备页、唯一返回及主动打开 AI 说明／选择仅本机阅读，不启动系统捕获。 |
| 最新真机测试构建／连接 | **TEST BUILD SUCCEEDED**；`/private/tmp/lingfer-toolchain/release14-return-consent-final-build-nov16.log`。当前物理 iPhone 离线，重连询问未获确认，最新真机回归未运行。 |
| 11 月 15 日恢复面板测试构建 | **TEST BUILD SUCCEEDED**；`/private/tmp/lingfer-toolchain/release14-restored-panel-build-nov15.log`。只是测试构建，不是当前全部真机流程通过或最终分发归档。 |
| 此前真机全页与本地会话 | `testFullPageCaptureAndLocalSessionHistory` **67.114 秒通过**。公开样例，不外推所有 App／页面。 |
| 此前真机词卡 PiP 导航 | `testPiPSystemWordNavigation` **89.704 秒通过**。不代替首次自动浮窗与段落导航验收。 |
| 此前真机状态恢复 | `testRestoreUserReadingAfterFixtureQA` **4.955 秒通过**。 |
| 此前真机存储清理 | `testStorageCleanupAuthorizedNov14` **10.060 秒通过**；实际点击清理，缓存 **7.8 KB → 0 B**。`legacyMocksRemoved=false`，设备无旧 mock，未执行归档／撤销的真机验收。 |
| 尚未关闭的真机失败 | 同期首次自动 PiP **67.597 秒失败**，段落 PiP 导航 **66.908 秒失败**；上述六项合计 4 过、2 败，来自 `/private/tmp/lingfer-toolchain/release14-consent-device.xcresult`。恢复原生面板后的最新回归待补，不能沿用失败前或旧版结论宣布修复。 |
| 最新重跑边界 | 11 月 15 日的 `/private/tmp/lingfer-toolchain/release14-restored-panel-device-nov15.log` 曾因找不到 iPhone 目标未启动用例，不计作功能通过或功能失败；后续真机重跑由主任务继续。历史用例名中的 `AutomaticDock` 不代表产品仍保留 Dock。 |
| 截图／海报 | 较早 [八张模拟器原图](ui-screenshots/reader-controls-followup-nov14/README.md)仅证明当时的书内／准备控件。01 已批准采用最新真实 iOS 首页“随屏与资料，从这里开始”，02 使用最新正确独立准备页，不再等待 PiP 图；03–06 保留真实核心画面；两档六图已上传，刷新后中屏／大屏均 **6/10**、顺序正确，[上传状态与凭证](../artifacts/app-store-2.1.1-14/store-upload-status.json)。构建（14）已选并保存、手动发布，未添加以供审核。 |

11 月 16 日[四张模拟器原图](ui-screenshots/native-startup-return-nov16/README.md)已逐图核对：单层返回玻璃无重叠，准备文案及仅本机阅读状态可见。`ShareViewController` 两处 `onAppear` 当前只刷新许可状态，不自动打开 AI sheet；默认未许可仍禁止联网，点击“联网 AI”可主动查看说明。准备页模拟器通过不证明系统授权回来后没有覆盖 sheet，更不能替代 first PiP／灵动岛真机证据。

用户已明确“目前连不上，你直接推送吧，下次再做真机测试”，主任务据此完成内部 Beta 上传；苹果处理结束，原两位测试员现可下载（14）。已知失败与待测项继续保留，Beta 可下载不等同于最新真机验收通过；正式 App Store 审核／发布未提交。六张新海报的中屏／大屏两档均已上传商店草稿并刷新核实；01／02 使用真实首页／独立准备页，不合格 PiP 图源排除。旧大屏仅移出草稿，素材库保留；构建（14）已选择保存，保留手动发布，尚未添加以供审核。

此前真机四项通过与两项失败的原始日志为 `/private/tmp/lingfer-toolchain/release14-consent-device.log`。缓存实际清理已经执行，不再写成“用户手机清理未执行”；旧示例归档及所有用户文件的逐项对照没有据此冒称真机通过。限定清理范围和数据保护仍由相应文件系统／Flutter 测试覆盖。

较早的 `/private/tmp/lingfer-toolchain/reader-followup-final-release.log`、[16 项源摘要及验证清单](../artifacts/reader-controls-nov14-followup/verification.json)记录的是恢复面板之前的快照。其当时 Release／签名有效，但不能代替本次最后修改后的归档、签名和源文件重新核对。两项旧模拟器用例 2/2 通过（24.935 秒、31.677 秒）不能证明新修正；单层返回现由 11 月 16 日新 UI 回归与原图核对，跨 App 启动仍未通过最新真机回归。

`ReadingText.annotations` 的横／竖布局、原著英文括号普通正文样式和紧凑七档列表继续保留；原著英文括号由专项测试覆盖，不能冒称旧八图含该样例。**首次 PiP 和灵动岛仍是当前真机重点，尚不宣称原生体验稳定或本轮真机验收完成；内部 Beta 按用户授权先行，正式发布另记。**

---

## 历史轮次：11 月 14 日读屏对照、本地记录与书内阅读

日期：2026-11-14（Asia/Macau）。实现与完整边界见 [阅读细化综合记录](reading-refinements-nov14.md)，当前交接见 [ui-handoff.md](ui-handoff.md)。本轮候选为 `2.1.1+13`，已在本机安装验证、尚未上传；最后确认可下载的 TestFlight 仍为（12），本轮没有提交 App Store 审核。

浮窗与灵动岛改为独立选择。浮窗取消 `LINGFER LIVE` 标题，保留功能性自识别提示；整页对照按同组原文／译文上下显示，分别按实际高度续页，保留句组和续页编号。学习词卡继续显示原句片段与目标词高亮，识别／筛词／翻译／补充内容使用真实加载状态。全帧识别、二维遮挡过滤和同页补读已接入，但只显示本机已经读到的可见正文，未滚动到、持续被遮或受保护的内容不承诺完整。

最近一次会话在本机累计最多 60 个页面记录，并另限源文 12 万字符与 JSON 2 MB；停止后查看原文和匹配词，不将历史词混进当前浮窗，不自动收藏。新用户“本地资料”为空，下方单独提供三本完整英文公版原著；点开才加入这一本。书内范围／语言／排版方向用摘要入口展开受屏高约束的列表，注释统一墨蓝，沿用已有六个主题和进度／书签／缓存。

### 本轮验证状态

| 检查 | 已确认结果与范围 |
| --- | --- |
| Flutter 集成全套 | 56 项通过、0 失败；日志 `/private/tmp/lingfer-integrated-flutter-tests-nov14.log`。 |
| Swift 阅读稳定性 | 58 项通过，包含后补右上小状态簇排除的两项检查。 |
| Swift 历史／源文覆盖 | 44 项通过；包含跨页去重、容量、Unicode、完整源文分组和损坏缓存。 |
| 公版书整理后专项 | 6 项通过；三本正文连续空行／独立插图占位已清理，来源清单散列更新。不与集成全套相加。 |
| 全新 iOS 模拟器 | `testFirstLaunchLibraryAndReaderNov14` 通过，91.358 秒（最终修复后）；确认本地 0 份、三本独立书入口、Alice 正文及七档范围列表。 |
| 真机全页＋本地会话 | stable `testFullPageCaptureAndLocalSessionHistory` 66.560 秒通过；公开页面上下部正文锚点及停止后的两页累计。 |
| 真机整页对照 PiP 导航 | stable `testPiPSystemPassageNavigation` 84.667 秒通过；三次实际系统回调，主请求数 3 保持不变。 |
| 真机学习词卡 PiP 导航 | stable `testPiPSystemWordNavigation` 72.151 秒通过；三次实际系统回调，主请求数 0 保持不变。 |
| 测试后恢复用户状态 | stable `testRestoreUserReadingAfterFixtureQA` 4.886 秒通过；没有导出该用例的用户界面。 |
| stable 后最终资产／状态簇微调 | 最终资产构建成功；最终 `FullPage` 62.839 秒、`RestoreUser` 5.219 秒通过，18:14:15 结束。增量结果包 `/private/tmp/lingfer-toolchain/reading-nov14-device-final.xcresult`；过滤后仍有短小 OCR 杂项遗留。 |

首次真机运行曾有三项失败、一项恢复通过：底部锚点断行、两类 PiP 导航少一次实际回调。稳定按钮几何等待及前台音频就绪调整后，以上 stable 四项全部通过，首轮问题已复验关闭；首轮时长、失败及调整过程保留在综合记录。stable 结果包为 `/private/tmp/lingfer-toolchain/reading-nov14-device-stable.xcresult`，日志同前缀 `.log`。

### 真实图像与来源

| 证据 | 位置与性质 |
| --- | --- |
| iPhone 跨 App 原文／学习浮窗／原译导航／本地会话 | [真机截图清单与来源](ui-screenshots/nov14-live-reading/README.md)，2026-11-14：导航来自 stable 18:01–18:03，原文／浮窗／历史来自最终增量 18:13–18:14（698 字、2 页记录、14 词）。仅三个公开 fixture 的命名 PNG，无像素修改；[逐图时间与 SHA-256](ui-screenshots/nov14-live-reading/provenance.json)。 |
| 全新模拟器资料／书内真实应用页面 | `docs/ui-screenshots/nov14-library-reader/`，含 [空书架与内置书](ui-screenshots/nov14-library-reader/nov14-fresh-install-public-domain-library.png)、[Alice 正文](ui-screenshots/nov14-library-reader/nov14-public-domain-reader.png)、[范围列表](ui-screenshots/nov14-library-reader/nov14-reader-level-sheet.png)。 |
| 书内组件窄屏／大字／横屏 | [组件验证](book-reader-ui-verification.md) 与 `docs/book-reader-ui-renderings/`；属于真实 Flutter Widget 渲染，不能当作真机截图。 |

真机截图中的“微信”是仓库公开测试页的页头，未使用用户的真实公众号或私人书架。追加过滤后的最终原文／历史图已没有 `55+`，仍可见一小段 `1X1à` 状态栏误识别，作为遗留保留；保守规则不是完美正文分类，不宣称页头／页脚全部清除。PiP 图保留 AVKit 控制层的暂时遮挡；系统切换结论结合回调、游标和请求数确认。上述样例验收不扩写为所有 App、所有语言或灵动岛状态均已验证；Flutter 共用书内／资料仍需 Android 真机回归。

本轮未提交、推送或发布，商店草稿和其他窗口未提交改动保留。

---

## 上一轮：悬浮球、原词标记、读屏准备页与资料操作

日期：2026-11-08（Asia/Macau）。以下记录对应 `refined-ui-screenshots/`，后面的轮次保留为历史。当前规范见 [ui-handoff.md](ui-handoff.md)。

本轮直接调整 Flutter 与原生展示层：圆形悬浮球使用居中线性阅读图标，原服务的待机、加载、暂停、重试状态继续保留；菜单靠近小球展开，收紧留白，磨砂底板取样自已有本机清晰帧。修正了材质重绘后透明度下降的问题。原词取消整块着色，按已有逐字 / 词框画细线；译义只在原词紧邻的空白处出现，短线说明对应关系，密集处直接点按原词细线进入原词卡。

iOS 开启前统一为稳定居中的准备页，已有结果从单独入口查看；阅读中的状态、暂停、浮窗、停止和预览收为操作层，短窗口使用紧凑操作条。首页导入工具固定两列，Safari 分享说明并入同组；本地资料改用格式标记、衬线标题与圆角玻璃操作面板，置顶、移除和撤销沿用原回调。受管理副本的内部编号只在显示时隐藏，原模型标题、资料标识与进度键保持不变。

### 验证与范围

| 验证 | 结果 |
| --- | --- |
| Flutter 全量 | 最终标题调整后全量 36 项通过 |
| Dart 静态检查 | 本轮主界面、共享组件、展示标题扩展和界面测试无诊断；两个旧阅读器无错误，其中 `reading_screen.dart` 另有 8 项警告和 2 项提示，涉及既有空值判断及未使用组件，本轮未改动这些代码 |
| Android 构建 | Debug 与原生测试包成功，保留数据安装至 Galaxy Z Fold5 |
| Android 原生回归 | 320×568、1.8 倍字号和 829×320 三组通过；原句 / 释义保留、加载 / 错误 / 重试、收藏、范围、菜单返回及语言选择回调均通过 |
| 几何与材质 | 不同高度字符与跨行词框分别保留；标签不漂至页边；圆球四种状态透明圆角；磨砂层连续重绘的颜色和透明度保持一致 |
| Android 实际操作 | 使用只含公开文字的独立测试应用，选择单应用共享；实际 OCR、离线词义、重排、悬浮菜单和词卡均已操作；另完成公开 TXT 的导入、置顶和移除，撤销由 Flutter 界面用例验证 |
| iOS 界面验收 | iPhone 18 Pro / iOS 27.2 模拟器；`testRefinedReadingDesign` 通过，0 失败、0 运行时警告；首页 → 居中准备页 → 语言 / 方式菜单 → 返回 → 试读 |
| 原业务边界 | 未由本轮修改授权、捕获、OCR 引擎、筛词、接口请求、控制器、存储格式、云函数或密钥配置；保留功能窗口同期改动 |

Android 实际验收只共享独立公开测试页，没有进行全屏共享。测试页仅在 Android 测试包中，不进入正式应用。iOS 的系统授权、自动画中画、灵动岛及后台捕获仍由功能窗口验收，本轮不以模拟器准备页截图代替真机证明。

最终 Android 与 iOS 模拟器构建均成功。验收结束已停止 Android 读屏，恢复原语言选择，移除本轮导入的公开 TXT 及其副本；未清空应用数据。资料列表的截图保留验收过程中的公开样例。

本次实际词卡的 AI 请求显示原服务“详解暂未响应”，基础释义和原句保留；真实错误画面如实收录，没有替换为模拟回答。加载、错误、成功重试及收藏的展示回调另通过受控原生用例验证。OCR 返回的字框若本身有误，仍需功能窗口处理；本轮修复绘制、位置约束和关联方式，没有扩大遮罩掩盖误差。

### 最新真实截图

| 页面 | 截图 |
| --- | --- |
| iPhone 首页 / 两列工具 | [ios-home.png](refined-ui-screenshots/ios-home.png) |
| iPhone 读屏准备页 | [ios-live-ready.png](refined-ui-screenshots/ios-live-ready.png) |
| iPhone 阅读选项 | [ios-live-options.png](refined-ui-screenshots/ios-live-options.png) |
| iPhone 试读 | [ios-reading.png](refined-ui-screenshots/ios-reading.png) |
| Android 圆球 | [android-orb.png](refined-ui-screenshots/android-orb.png) |
| Android 菜单 | [android-menu.png](refined-ui-screenshots/android-menu.png) |
| Android 子菜单 | [android-menu-settings.png](refined-ui-screenshots/android-menu-settings.png) |
| 原词细线 / 紧邻释义 | [android-annotations.png](refined-ui-screenshots/android-annotations.png) |
| 文字再次重排后 | [android-annotations-reflow.png](refined-ui-screenshots/android-annotations-reflow.png) |
| 实际词卡与原服务错误 | [android-word-card.png](refined-ui-screenshots/android-word-card.png) |
| 本地资料与置顶 | [android-library.png](refined-ui-screenshots/android-library.png) |
| 资料玻璃操作面板 | [android-library-actions.png](refined-ui-screenshots/android-library-actions.png) |

### 本轮直接修改文件

以下仅列本轮直接触及文件，不将工作区其他窗口的业务改动计入本轮：

- `lib/features/companion/companion_shell.dart`：两列工具、Safari 同组入口、资料列表及玻璃操作面板；原业务回调保留。
- `lib/features/companion/companion_components.dart`：浮层长标题最多两行，防止挤压操作。
- `lib/widgets/book_display_title.dart`：新增纯展示标题扩展，仅隐藏受管理副本的内部前缀。
- `lib/screens/reading/reading_screen.dart`、`lib/screens/reading/pdf_reader_page.dart`：仅将阅读标题改为展示名称，不改变原 Book 或缓存键。
- `android/app/src/main/kotlin/com/wang/lingfer/screen/NativeFloatingOrb.kt`：新增圆形图标控件、状态与无障碍描述，兼容原 TextView 状态调用。
- `android/app/src/main/kotlin/com/wang/lingfer/screen/NativeGlassBackdrop.kt`：现有清晰帧的局部磨砂取样，不发起捕获或存储。
- `android/app/src/main/kotlin/com/wang/lingfer/screen/GlassAnnotations.kt`：逐框细线、近词标签、对应短线、原词点击区域及重绘稳定性。
- `android/app/src/main/kotlin/com/wang/lingfer/screen/NativeReadingMenu.kt`：原四项菜单与子页的字体、圆角、图形和间距。
- `android/app/src/main/kotlin/com/wang/lingfer/screen/NativeReadingPanel.kt`：共用原生颜色 / 字体 / 材质、词卡展示与控件。
- `android/app/src/main/kotlin/com/wang/lingfer/screen/PageTranslation.kt`：仅调整原生对照面板展示样式。
- `android/app/src/main/kotlin/com/wang/lingfer/screen/ScreenReaderService.kt`：仅替换球形展示控件、面板尺寸 / 位置、背景取样及展示资源释放；原捕获和业务调用保留。
- `ios/LingferShare/ShareViewController.swift`：准备页展示组件、精简阅读控件、纸面词卡和玻璃控件。
- `ios/Runner/LiveScreenCapture.swift`：仅本窗口的 `LiveReadingHost` 展示部分；会话、驱动、捕获、画中画和状态逻辑保留功能窗口实现。
- `android/app/src/androidTest/AndroidManifest.xml`、`android/app/src/androidTest/java/com/wang/lingfer/screen/ReadingFixtureActivity.java`：独立公开测试页，仅测试包。
- `android/app/src/androidTest/kotlin/com/wang/lingfer/screen/NativePanelUiInstrumentation.kt`：补充几何、材质重绘、圆球状态及语言回调验收。
- `test/companion_ui_test.dart`：两列位置及资料置顶、移除、撤销验证。
- `ios/RunnerUITests/ReadingUITests.swift`：仅追加本轮设计验收测试，保留已有测试。
- `docs/ui-handoff.md`、`docs/ui-verification.md`、`docs/refined-ui-screenshots/`：本轮规范、记录及截图。

参考 [Apple 材质规范](https://developer.apple.com/design/human-interface-guidelines/materials) 的操作层分工，以及 [AssistiveTouch](https://support.apple.com/en-us/111794) 的浮动控制与展开层级；延续前轮已列明的 Common Reader、Apple Books 等参考。图标由代码绘制，未复用第三方品牌素材。

本轮未提交、推送或发布。功能窗口后续打包时应保留本轮展示部分，继续独立处理原授权、OCR、请求、同步和系统后台能力。

---


## 上一轮：阅读结构与启动界面重设计

日期：2026-11-08。本节及其后的记录为历史验收；本轮最新实现、截图与原生接入状态以上方“最新轮次”为准。

本轮移除了底部三图标导航和宽屏侧栏，阅读成为唯一主工作区；生词本、设置从顶部进入独立页面。去掉首页方形“渡”标，使用衬线标题、白色正文纸面与克制的玻璃控件；重排首页入口、空资料试读、词卡与讲解层级。没有增加虚假书封、推荐列表或阅读进度。

设计书和 9 组官方公开参考、具体采用与舍弃的部分，见 [当前交接说明](ui-handoff.md)。字体离线打包，保留 OFL 许可，没有远程字体依赖。

### 最新验证

| 项目 | 结果与边界 |
| --- | --- |
| Flutter 测试 | 最新 22 项全部通过，包含功能窗口同期新增的复习测试；界面测试覆盖 320×568、键盘 240、690×820 双栏、1.8 倍字号、长文、空内容、讲解加载 / 错误 / 重试、独立页面返回和减少动效 |
| Dart 静态检查 | 本轮 7 个展示文件及 2 个 Flutter 测试文件，0 诊断 |
| Android 构建 | ARM64 Debug 成功，安装到 Galaxy Z Fold5；没有清空应用数据 |
| Android 冷启动 | 实际录屏逐帧核对；原生启动为 #F6F6F3 浅色底，不再引用旧位图或回退显示旧启动图标，随后进入本轮首页 |
| iOS 构建及原生操作 | iPhone 18 Pro / iOS 27.2 模拟器，`testAppleGlassReview` 1 项通过、0 失败、0 运行时警告；实际打开语言 / 范围、文字输入、试读原文、词卡、现有 AI 讲解、生词本及设置 |
| iOS 冷启动 | LaunchScreen 与主视图初始化背景统一，不增加启动延时；Xcode 本地签名构建录屏确认浅色原生启动背景，随后进入首页 |
| 文字对比 | 辅助文字在页面底色上约 4.7:1，主按钮白字约 6.94:1 |
| 格式检查 | `git diff --check` 通过 |

真实 AI 讲解仍调用现有服务；加载与失败恢复通过受控响应测试。这里不把离线释义可用误写为离线 AI 可用，也不把模拟器验收替代 iPhone 真机分享、签名或系统捕获验收。

Android 手机同期被功能窗口用于系统读屏授权验证，本轮后续没有操作其授权弹窗。下表 Android 画面直接提取自本轮真实冷启动录屏，保留原帧，不用旧截图代替新界面。

iOS 最初的未签名测试包触发了系统 SplashBoard 对启动资源的校验错误（-67056），表现为启动前黑底。最终以 Xcode 本地签名构建重新安装、录屏，核对原生浅色背景和随后出现的首页。未加入额外启动遮罩、计时器或生命周期业务代码；`SceneDelegate.swift` 保持本轮开始时的实现。

### 本轮真实画面

| 页面 | 最新截图 |
| --- | --- |
| iPhone 首页 | [ios-home.png](apple-ui-screenshots/ios-home.png) |
| 语言与通用难度 | [ios-language.png](apple-ui-screenshots/ios-language.png) |
| 粘贴文字 | [ios-text-input.png](apple-ui-screenshots/ios-text-input.png) |
| 试读原文及现有原位标注 | [ios-reading.png](apple-ui-screenshots/ios-reading.png) |
| 词卡（切换动画完成后） | [ios-word-cards.png](apple-ui-screenshots/ios-word-cards.png) |
| 语境讲解 | [ios-explanation.png](apple-ui-screenshots/ios-explanation.png) |
| 生词本（含功能窗口接入的复习入口） | [ios-saved-words.png](apple-ui-screenshots/ios-saved-words.png) |
| 设置 | [ios-settings.png](apple-ui-screenshots/ios-settings.png) |
| Fold5 展开首页 | [android-home.png](apple-ui-screenshots/android-home.png) |
| Android 原生冷启动 | [android-cold-launch.png](apple-ui-screenshots/android-cold-launch.png) |
| iOS 原生冷启动 | [ios-cold-launch.png](apple-ui-screenshots/ios-cold-launch.png) |

### 本轮直接修改清单

工作区中有其他窗口的大量未提交改动；以下只列本次直接触及的文件，不将控制器、原生 OCR / 捕获、服务或云函数的同期修改计入本轮。

| 文件 | 本轮修改 |
| --- | --- |
| `lib/features/companion/lingfer_theme.dart` | 角色色、衬线标题、正文与系统组件样式 |
| `lib/features/companion/lingfer_glass.dart` | 独立玻璃控件，辅助功能下退为实底 |
| `lib/features/companion/companion_shell.dart` | 移除三栏导航、顶部次级入口、重排首页与空资料试读；保留同期平台业务入口与回调 |
| `lib/features/companion/companion_components.dart` | 共用纸面、玻璃浮层、范围 / 语言摘要、标题与布局 |
| `lib/features/companion/companion_reader.dart` | 原文、词卡及单双栏呈现；保留现有 OCR 与原位标注调用 |
| `lib/features/companion/companion_sheets.dart` | 难度、文字输入、讲解面板的样式与布局 |
| `lib/features/companion/reading_controls.dart` | 语言、难度和玻璃控制层的共用样式 |
| `assets/fonts/lingfer-display-semibold.ttf` | 约 333KB 的 Noto Serif SC 静态界面字形子集 |
| `assets/licenses/NotoSerifSC-OFL.txt` | 字体许可 |
| `pubspec.yaml` | 注册字体；移除会重新生成旧启动图片的过时 splash 配置；应用身份及版本号未由本轮修改 |
| `ios/Runner/Base.lproj/LaunchScreen.storyboard` | 移除启动位图，改为与首页一致的原生背景 |
| `ios/Runner/Base.lproj/Main.storyboard` | Flutter 主视图初始化背景与首页统一 |
| `android/app/src/main/res/drawable/launch_background.xml`、`drawable-v21/launch_background.xml` | 纯色启动背景 |
| `android/app/src/main/res/drawable/lingfer_launch_empty.xml` | Android 12 透明启动图标，避免旧图回退 |
| `android/app/src/main/res/values/lingfer_launch.xml` | 共用启动背景色 |
| `android/app/src/main/res/values/styles.xml`、`values-night/styles.xml`、`values-v31/styles.xml`、`values-night-v31/styles.xml` | 各系统启动 / 主窗口主题背景统一 |
| `test/widget_test.dart`、`test/companion_ui_test.dart` | 适配新导航和标题，新增次级页面与大字 / 减少动效验证 |
| `ios/RunnerUITests/ReadingUITests.swift` | 追加 `testAppleGlassReview` 及真实截图；保留其他窗口原生测试 |
| `docs/ui-handoff.md`、`docs/ui-verification.md`、`docs/apple-ui-screenshots/*.png` | 本轮设计交接、验证和真实画面 |

### 功能窗口配合

- Android 悬浮词卡与 iOS 分享 / 实时阅读原生面板需同步本轮角色色、字体层级和控制层材质，按 [ui-handoff.md](ui-handoff.md) 接入。上轮纸面样式的接入不等于已完成本轮新风格。
- 原生授权、捕获、OCR、筛词、语言请求、收藏同步、复习规则和存储由功能窗口维护。本轮保留其同期变更，没有重置、提交、推送或发布。
- 原本地 TXT / EPUB / PDF 的入口和阅读进度保留；旧阅读器深层弹窗的全面统一仍需后续分批处理。搜索、熟词管理等新增功能仅作建议。

---

## 第一轮及原生接入历史记录

最新原生轮次：Android 悬浮面板和 iOS 分享面板的接入、实际流程、修改文件及边界见 [原生接入与验证](native-ui-verification.md)。本页原有表格和截图保留为前一轮 Flutter 界面的验收记录，不代表后续原生面板仍未修改。

日期：2026-11-08（Asia/Macau）。截图均来自本轮代码在设备上的真实运行，没有使用设计稿或替代渲染。

## 验证结果

| 项目 | 结果与范围 |
| --- | --- |
| Flutter 测试 | 13 项全部通过，含现有词表、服务、阅读收藏测试和新增 5 项 UI 场景 |
| 本轮 Dart 文件静态检查 | 无诊断；检查主题、主页面及其展示组件、阅读页、面板、两个 Flutter 界面测试文件 |
| Android 开发构建 | 成功；安装到 Samsung Galaxy Z Fold5，沿用 `com.wang.lingfer` |
| iOS 模拟器开发构建 | 成功；沿用 `com.wang.yudu` |
| iOS 原生界面验收 | `ReadingUITests.testUIDesignReview` 1 项通过，0 失败，0 运行时警告；截图 OCR → 四级词卡 → 现有 AI 服务中文讲解 → 生词本 → 设置 |
| Android 真机操作 | 难度面板打开/关闭、展开双栏试读、原句讲解加载与成功、返回、生词本、设置均已实际操作 |
| 兼容边界复核 | 文件选择、导入、旧阅读器导航、读屏授权及 OCR 加载代码与开始时快照逐字比较一致；控制器、接口、存储和服务配置未由本轮修改 |

小屏测试尺寸为 320×568，模拟键盘占高 240；长文本测试为 100 段、1.8 倍字号；展开阅读测试为 690×820。真机屏幕为 1812×2176、420dpi，约 690dp 宽。窄屏使用原文/词卡切换，宽屏独立双栏滚动，大字模式回退单栏。

加载、AI 503 失败及成功重试使用受控服务响应验证；空原文、无匹配词、小屏键盘与熟词撤销通过 Flutter UI 测试。两端真实 AI 讲解截图使用现有配置的服务，未替换为模拟回答。

## 实际截图

| 平台 / 页面 | 截图 |
| --- | --- |
| iPhone 首页 | [ios-home.png](ui-screenshots/ios-home.png) |
| iPhone 学习范围 | [ios-levels.png](ui-screenshots/ios-levels.png) |
| iPhone 截图识别后的原文 | [ios-original.png](ui-screenshots/ios-original.png) |
| iPhone 词卡 | [ios-word-cards.png](ui-screenshots/ios-word-cards.png) |
| iPhone AI 讲解结果 | [ios-explanation.png](ui-screenshots/ios-explanation.png) |
| iPhone 生词本 | [ios-saved-words.png](ui-screenshots/ios-saved-words.png) |
| iPhone 设置 | [ios-settings.png](ui-screenshots/ios-settings.png) |
| Fold5 首页 | [android-fold-home.png](ui-screenshots/android-fold-home.png) |
| Fold5 学习范围 | [android-levels.png](ui-screenshots/android-levels.png) |
| Fold5 原文 / 词卡并排 | [android-fold-reading.png](ui-screenshots/android-fold-reading.png) |
| Fold5 AI 加载状态 | [android-ai-loading.png](ui-screenshots/android-ai-loading.png) |
| Fold5 AI 讲解结果 | [android-explanation.png](ui-screenshots/android-explanation.png) |
| Fold5 生词本 | [android-saved-words.png](ui-screenshots/android-saved-words.png) |
| Fold5 设置 | [android-settings.png](ui-screenshots/android-settings.png) |

## 修改文件清单

以下为本轮直接修改或新增的文件，不把功能窗口原有和同期改动归入本轮：

| 文件 | 内容 |
| --- | --- |
| `lib/features/companion/lingfer_theme.dart` | 纸面与墨蓝主题、字体、系统组件样式 |
| `lib/features/companion/companion_shell.dart` | 首页、导航、生词本、设置；保留原业务辅助函数 |
| `lib/features/companion/companion_components.dart` | 共用纸面、布局、范围摘要、状态和面板标题 |
| `lib/features/companion/companion_reader.dart` | 原文、截图预览、双栏 / 单栏词卡、收藏和熟词反馈 |
| `lib/features/companion/companion_sheets.dart` | 难度、文字输入、使用指南、AI 讲解及重试 |
| `test/widget_test.dart` | 更新改名的页面标题、导航标签，保留原阅读收藏流程 |
| `test/companion_ui_test.dart` | 新增 5 项界面与状态测试 |
| `ios/RunnerUITests/ReadingUITests.swift` | 更新入口标签，增加 1 项真实设备流程及截图测试 |
| `docs/ui-handoff.md` | 设计说明、原生面板接入、状态矩阵和后续建议 |
| `docs/ui-verification.md` | 本验证记录与修改清单 |
| `docs/ui-screenshots/*.png` | 上表 14 张真实截图 |

## 验证边界与功能窗口事项

- iOS 验证使用 iPhone 18 Pro / iOS 27.2 模拟器，未代替 iPhone 真机签名、分享扩展同步与审核验证。
- Android 悬浮面板及 iOS 分享面板的原生样式未改；完整接入要求在 [ui-handoff.md](ui-handoff.md)。本轮没有重新申请读屏授权或修改 OCR / 筛词算法。
- 旧本地资料阅读页仍由原页面打开，原进度与缓存机制保留。本轮没有声称已重做旧阅读器所有弹层。
- 本次图片 OCR 原文仍可见硬换行和局部粘连。展示层保留原文；后续归一化由功能窗口处理。
- 工作区同时有功能窗口在增加多语言和坐标标注，相关源文件未由本轮重置或覆盖。新能力的界面接入需与该窗口继续合并。
- 没有提交、推送或发布。

2026-11-08 功能轮次：iOS 27 实时读屏／画中画、Android 阅读菜单与缓存修复、生词复习和学习备份的当前进度及边界，见 [随屏功能验证](live-reader-verification.md)。本轮保留上方最新 Flutter 导航与视觉设计，原生角色色同步当前主题。

2026-11-08 Beta 交付：2.1.1（5）已向原内部测试组开放下载；安卓同版本已保留数据安装。原生主题角色色已同步当前 Flutter 风格。真机基础流程截图、最终补验边界、文件清单与发布凭证见 [随屏功能验证](live-reader-verification.md)。

2026-11-08 后续功能轮次：学习辅助／整页对照模式、段落缓存与恢复、Fold5 零宽启动及 iOS 停止画中画修复，进度与直接修改文件见 [整页对照验证](page-translation-verification.md)。保留当前 Flutter 导航、字体与角色色。

2026-11-08 最终真机验证：两台手机已安装 2.1.1（7）；35 项 Flutter 测试、Android 原生回归及最终（7）两项 iPhone 界面测试通过。TestFlight（6）已向原两位测试员开放，（7）已上传等待苹果处理。最新实拍、修改文件与待办见 [整页对照验证](page-translation-verification.md)。

2026-11-08 后续功能交接：Android 悬浮菜单已分类为本页结果、暂停／继续、阅读设置和更多，详细模式／范围／语言移入设置，每层保留返回；iPhone 增加自动画中画、实时活动和首次授权提示。保留界面窗口的启动说明与原生按钮改动。实拍、修改文件和尚待解锁的最终验收见 [阅读浮窗与菜单分类验证](reading-controls-verification.md)。

2026-11-08 最终验收更新：（8）已向原两位 TestFlight 测试员开放，说明保存。iPhone 自动浮窗／实时活动操作与自动换页／收藏回主 App 两项最终真机测试均通过，系统分享／重开恢复另项通过；35 项 Flutter 测试、Android 菜单与原生回归通过。此前等待解锁的状态已解除，最终证据见 [阅读浮窗与菜单分类验证](reading-controls-verification.md)。

2026-11-09 功能窗口更新：已合入本页最新 UI 快照，并完成 iPhone 原句高亮浮窗、画面位置提示、同页轮换／暂停与恢复、短时遮挡排除。36 项 Flutter 测试、23 项截取／词序断言、最新 UI 真机用例及最终上下文浮窗真机用例通过。TestFlight 2.1.1（9）已于 2026-11-09 00:20 核实向原两位内部测试员开放下载，新版说明已保存；最终状态与本轮修改清单见 [原句高亮浮窗验证](context-preview-verification.md)。

2026-11-09 后续功能验收：2.1.1（10）的 iPhone 真机集成用例通过（130.685 秒），覆盖后台恢复、轻滑保位、目标离屏后换词、实时活动导航、真实服务多句译文、缓存分页和停止；独立语言恢复用例通过（23.147 秒），已恢复“自动识别 → 英语”。23 项稳定性断言与 12 项原句截取断言通过。当前 UI 与发布源文件冻结核对见 [iOS 阅读稳定性验证](ios-reading-stability-verification.md)，下载状态待苹果处理后核实。

2026-11-09 22:15 Beta 最终状态：2.1.1（10）已核实向原两位内部测试员开放下载，测试说明已保存并重载复核。真机截图、修改清单、运行警告与系统边界、签名及下载凭证见 [iOS 阅读稳定性验证](ios-reading-stability-verification.md)。未提交正式 App Store 更新。

2026-11-10 灵动岛功能窗口：已实现明确的灵动岛／浮窗选择、系统还原时序修复、测量分页和更大字号。Flutter 页面与 Android 保留。29 项策略断言及 8 组组件排版通过；晚间 iPhone 真机实际前后翻词、顶部留白、浮窗返回 App 后恢复及灵动岛／浮窗切换均通过。补完自动识别整段翻译后重新归档候选（11），下载状态以专项文档为准。详见 [灵动岛与浮窗切换验证](island-presentation-verification.md)。


2026-11-10 22:45 功能窗口交接：Beta 2.1.1（11）已向原两人内部测试组开放，验收说明已保存。最终 iPhone 共存回归 65.134 秒、偏好恢复 21.942 秒通过；准备页模式／语言独立，完整语段浮窗与独立词卡活动同时运行。正式归档为 `Runner-2.1.1-11-coexist-final.xcarchive`，保留 Flutter／Android 现有改动。最新用户实测发现 **PiP 内没有可用翻页入口、首段覆盖不明确、真实公众号等待与定位不佳**，当前不适合正式发布；之前活动按钮回归不能当作 PiP 按钮回归。详见 [专项验证](island-presentation-verification.md)、[重做分析与待验证方向](ios-reading-redesign.md)、[商店草稿及遗留项](app-store-release-preparation.md)。六张 iPhone 宣传图已保存后台草稿，正式上架仍等待修复和用户验收。


浮窗导航开发记录（2026-11-10，最终结果见下方 11 月 12 日记录）：用户已要求执行系统 PiP 前后切换验证。已在现有实现补有限播放范围、独立时钟和帧时间戳；使用真实系统“快进／快退”切词及译文的早期候选已通过，连续操作又发现 OCR 快照提前重置游标，已补接受源文字时才重置和短暂过渡保持。当日候选构建及 40 项策略检查通过，最终真机回归当时等待 iPhone 解锁；11 月 12 日已完成补测，见下方更新。请保留本轮 `LiveScreenCapture.swift`、`LiveReadingViewport.swift` 与测试改动，不能据旧（11）包宣称已含修复。专项记录见 [浮窗导航验证](pip-navigation-verification.md)。


2026-11-12 浮窗导航最终真机验收：同一最终生产源码的英文词卡（57.865 秒）、中文→英语词卡（61.367 秒）、整页译文（58.981 秒）及偏好恢复（20.774 秒）通过；每种导航均在 Safari 前台实际点系统快进、快进、快退，保持期结束后游标不回退，导航不增加正文或词汇请求。返回 App 后再回文章的浮窗恢复和停止也通过，40 项策略检查通过。原始截图、结果包与限制见 [浮窗导航验证](pip-navigation-verification.md)。已停止读屏，恢复自动识别→英语、整页对照、浮窗＋灵动岛。准备（12）内部测试，未提交正式审核；保留其他窗口的 Flutter／Android UI 改动。旧（11）包不含本轮修复。

2026-11-12 打包交接：（12）已归档、签名核验通过，165 项源文件冻结一致，并已直接安装到连接的 iPhone。构建工具已迁到比赛根目录 `.toolchain/flutter-3.47.9/flutter`，插件使用 `~/.pub-cache`，锁定版本未变。TestFlight 上传被 Xcode 团队账户认证阻挡，已打开正确归档等待用户分发；网页已登录，正式审核未提交。下载状态以 `artifacts/testflight-2.1.1-12-status.json` 为准，不能将本机安装写成 TestFlight 可下载。


2026-11-12 晚间最终上传状态：2.1.1（12）已通过 Xcode Organizer 的 App Store Connect 分发上传成功，苹果处理完成。已核实原“王业翔内部测试”组仍为 2 位测试员，（12）状态为“正在测试”，简体中文测试说明显示“已保存”。之前的命令行账户错误及等待用户代分发状态已解除。构建 ID 为 `6bb5644e-4cf5-4fc6-bf49-b8a6dd35475a`；凭证 `artifacts/testflight-2.1.1-12-available.png`，最终状态 `artifacts/testflight-2.1.1-12-status.json`。165 项源文件冻结仍一致，正式 App Store 审核未提交，继续等待用户试用验收。

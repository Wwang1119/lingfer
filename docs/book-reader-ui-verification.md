# 书内阅读界面统一与空内容处理

日期：2026-11-14。本轮在现有书籍阅读器上修改，没有改建项目，也没有提交、推送或发布。

同日后续的字体缺字与控件紧凑修订见 [阅读控件字体与紧凑布局修订](reader-controls-font-refinement.md)。下文的真实模拟器验收属于前一轮，不能用来替代后续修订的设备验收。

## 已完成

- 书内学习范围、翻译方向、排版方向改为统一的纸面选择列表。七档范围用单个入口打开，当前项带勾，列表受屏幕高度约束并可滚动。
- PDF、扫描和书内选文共用的 `AppleGlassPanel` 同步改为一个玻璃范围摘要入口，避免七档同时挤在窄面板中；返回后仍调用原 `_setLevel`。
- 原文中的括号注释统一为墨蓝，深色主题使用浅墨蓝；旧缓存中的等级颜色仍可读取，但不再把正文混排为绿、蓝、紫、橙。注释用适度字重区分，原文字串、括号和顺序保持不变。
- 阅读工具和字号／纸面面板采用现有玻璃控件与墨蓝操作色，窄屏和大字自动换行，横屏面板限制高度并可滚动。保留六种原有阅读主题及其持久化值。移除只显示“即将开放”的自定义主题占位按钮。
- 打开阅读工具、字号设置或选文面板时收起右下角的 AI 解析指示，避免遮住菜单；解析任务和计数继续运行，关闭面板后按既有状态恢复显示。
- 空正文、不可访问资料进入明确的错误终态，可重新读取或返回资料入口后重新导入，避免一直显示“空文件”加载；不删除旧书架记录。
- 首次载入英文为主的书籍时默认英译中；之后仍由用户手选方向。采用首次正文样本判断，不变更翻译服务或请求格式。

正文的分页测量行高、字号范围、进度键、书签／高亮键、缓存格式和既有 AI／收藏回调保留。旧 `ReadingScreen` 的单段翻译缓存和阅读范围冻结逻辑继续沿用。

## 直接修改文件

- `lib/screens/reading/reading_screen.dart`
- `lib/widgets/reading_text.dart`
- `lib/widgets/apple_glass_sheet.dart`（仅共用范围入口与展示配色）
- `lib/widgets/book_reader_presentation.dart`（新增纯展示组件）
- `test/book_reader_ui_test.dart`
- 本文与 `docs/book-reader-ui-renderings/`
- 验收阶段仅扩展 `ios/RunnerUITests/ReadingUITests.swift` 中的 `testFirstLaunchLibraryAndReaderNov14` 方法；未修改同文件的其他测试。
- `docs/ui-screenshots/nov14-library-reader/`（六张原始模拟器截图及来源记录）

## 验证

`flutter --suppress-analytics test --no-pub test/book_reader_ui_test.dart --dart-define=LINGFER_CAPTURE_READER_UI=true`：7 项通过。

1. 旧缓存的不同等级颜色不再改变注释配色，原文与括号内容完整保留。
2. 320pt 窄屏、2 倍字号下，七档范围均能滚动到并选择，关闭回调可用。
3. 横屏、长内容、大字的选择列表不溢出。
4. 错误页在窄屏大字下仍能执行重试和返回重新导入。
5. PDF／扫描／书内共享范围摘要在大字下保持紧凑，并能打开列表选中托福范围。
6. 实际临时英文 TXT 载入后，书内控制显示英译中。
7. 实际空 TXT 载入后，出现含“正文”说明的错误终态，旋转加载指示消失。

最终测试日志：`/private/tmp/lingfer-book-reader-ui-tests-nov14-badge-final.log`。此轮包含解析指示的展示修正，沿用已有七项专项测试，没有新增复刻实现的测试。

`dart analyze lib/widgets/book_reader_presentation.dart lib/widgets/reading_text.dart lib/widgets/apple_glass_sheet.dart test/book_reader_ui_test.dart`：无问题。`ReadingScreen` 全文件仍有原有未使用旧辅助控件／方法及空判断等警告；本轮分析没有编译错误，未为清零警告删除既有业务方法。

## 渲染图与验证边界

以下为实际 Flutter Widget 测试渲染，**不是 iPhone／Android 设备截图**。可选截图模式在本机临时加载已有系统字体供视觉检查；系统字体没有复制进应用或仓库。

- [书内范围，大字号](book-reader-ui-renderings/ranges-large-type.png)
- [共享范围摘要，大字号](book-reader-ui-renderings/shared-range-summary-large-type.png)
- [横屏列表，大字号](book-reader-ui-renderings/layout-landscape-large-type.png)
- [统一墨蓝注释](book-reader-ui-renderings/quiet-inline-annotations.png)
- [不可用资料，大字号](book-reader-ui-renderings/unavailable-book-large-type.png)

最终 iOS 构建和真机验收由主任务统一进行。操作路径：主页公版书入口 → 打开书籍 → 轻点正文中部 → 四级考点／中译英或英译中／字号与外观；选文面板进入词汇页后可点新的范围摘要。上述测试没有真实调用 AI 后端，也不替代真实书籍长期阅读、真机选择手势与后台读屏验证。

## 独立 iOS 模拟器真实验收

2026-11-14 在新建的 iPhone 18 Pro／iOS 27.2 模拟器 `Lingfer First Launch Nov14` 验收，UDID 为 `DE3F7E7D-5530-4A21-93B8-C8CD7BFB4C96`。只移除了这个专用模拟器中的测试安装，以验证首次启动；没有清理用户真实手机或原有模拟器的资料。

`RunnerUITests/ReadingUITests/testFirstLaunchLibraryAndReaderNov14` 最终 **1 项通过、0 失败，91.358 秒**。结果包为 `/private/tmp/lingfer-toolchain/reading-nov14-first-launch-badge-final.xcresult`，日志为 `/private/tmp/lingfer-toolchain/reading-nov14-first-launch-badge-final.log`。此轮包含下述解析指示遮挡修正。中途一轮 XCTest 对加载文字查询 `isHittable` 时出现 SDK 命中点错误；仅调整本方法为检查 `exists`，最终重跑通过，没有因此修改业务代码。

确认结果：

- 新安装首页显示“本地资料 0 份”，并说明只展示用户主动导入／保存／加入阅读的资料，不扫描手机其他文件。
- 独立“内置公版书”入口显示三本完整英文原著：《爱丽丝梦游仙境》《福尔摩斯历险记》《傲慢与偏见》。三本规范后的 TXT 已逐字节核对进入该次安装包，不是旧资产缓存。
- 实际打开 Alice，阅读工具显示“英译中”，七档学习范围列表完整呈现。关闭选择列表、左滑翻页后定位到 Chapter I 的实际小说正文。
- 正文截图包含墨蓝释义注释，加载结束后截图。测试输出 `501 characters; gloss visible true`。
- 本条 UI 测试实际打开了 Alice；另两本在 UI 中验证入口存在，并验证完整资产进入安装包，未把“入口存在”写成另两本的逐本真机阅读验收。

以下六张均为该次通过的 XCTest 通过 `XCUIScreen.main.screenshot()` 保存的原始 PNG，未合成、裁切或加字。来源附件、时间、尺寸与 SHA256 见 [provenance.json](ui-screenshots/nov14-library-reader/provenance.json)。此前用于临时检查的录像截帧已从此正式截图目录移除。

- [首次首页，本地资料为空](ui-screenshots/nov14-library-reader/nov14-fresh-install-home.png)
- [三本内置公版书](ui-screenshots/nov14-library-reader/nov14-fresh-install-public-domain-library.png)
- [实际打开 Alice](ui-screenshots/nov14-library-reader/nov14-public-domain-reader.png)
- [书内阅读工具与英译中方向](ui-screenshots/nov14-library-reader/nov14-public-domain-reader-controls.png)
- [七档学习范围](ui-screenshots/nov14-library-reader/nov14-reader-level-sheet.png)
- [Chapter I 正文与墨蓝释义](ui-screenshots/nov14-library-reader/nov14-public-domain-prose.png)

真实截图检查发现的解析指示重叠已修正：阅读工具、设置或选文面板出现时隐藏原右下角指示，原解析计数、任务和请求均未改变；回到正文后仍依原状态显示。最终模拟器继续保留启动状态，由主任务统一检查和清理。本轮未操作真实设备、提交、推送或发布。

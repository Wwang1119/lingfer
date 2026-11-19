# 11 月 14 日阅读细化与综合验证

日期：2026-11-14。**四项 stable 真机复验、最终资产构建和后续两项增量真机复验均通过；正文杂项过滤仍有明确遗留。**

工作区构建号为 `2.1.1+13`，本轮已在本机安装验证，尚未上传。本轮继续修改现有语渡，没有新建项目。已开放的 TestFlight（12）是 11 月 12 日的包，不能据其旧验收宣称已经覆盖本轮功能；本轮没有新的 App Store 审核提交。

## 对用户疑问的结论

| 疑问 | 已确认的原因／边界 | 本轮处理 |
| --- | --- | --- |
| 为什么原文看起来不全？ | 原生“原文”页本身是完整 `model.text` 的可滚动显示，没有 `prefix` 或行数截断。上游旧读屏会固定裁去上下边缘，又把浮窗相交高度上的整条横带排除，连窗口旁边可见的列也可能漏掉。 | OCR 范围覆盖整帧，改用实际二维相交区域排除浮窗；先取得稳定正文再打开首个浮窗，降低首次遮挡影响。 |
| 移开浮窗后为什么还没补全？ | 旧视口合并主要补前后行，中间新显露的行可能没有插回原文；旧 `stillReading` 判断还会在原词仍可见时继续推迟新源文。 | 增加同页中间行合并和显著新增正文判定，翻译在途时暂缓，后续稳定画面再补读；轻微重排继续复用位置和结果。 |
| 为什么这一屏只有一个词？ | 多语言筛词原先只发送前 36 个 OCR 行，可能漏掉后半屏。即使文字已读全，AI 候选最多 12 个，仍要经过考试词表、原文对齐、去重和熟词排除，结果也可能只有一个。 | 以约 600 字的无损分组覆盖模型已经接受的最多 12000 字，保留 UTF-16 偏移；显示识别字数与匹配数，明确“无匹配词”不等于“没识别”。筛词规则和候选上限没有为凑数放宽。 |
| 中文太短、英文很长，对不上？ | 旧浮窗主要展示原文短摘要，再单独翻译文页；中文摘要不能说明这一长段英文具体覆盖到哪里。 | 实时原文按两句／约 240 字分组，原文和译文都按实际渲染高度分页，保留句组号及各自续页计数。 |
| 停止以后为什么只剩最后一个词？ | 每页覆盖 `lastText/lastHits`，旧版没有累计本次读屏会话。与没有接入云数据库无关。 | 新增本机会话累计、去重、容量限制和离线恢复；不把历史词混进当前浮窗，也不自动加入生词本。 |
| 新用户本地资料里有什么？ | 导入书架来自本机持久记录；应用不会枚举手机所有符合格式的文件。 | 新用户的“本地资料”为空，下方单列三本内置英文原著；用户点开某本后才加入书架。 |

这里的“页面记录”指已接受的视口正文，不等于整篇公众号、小说章节或 PDF 的实际页数。系统只交付当时可见画面；未滚动到、此前一直被遮住或受保护的内容仍可能缺失。**本轮实现不能保证所有 App 的每一屏都已识别完整。**

## 读屏范围、正文与加载反馈

- 去掉固定上下裁剪，先在本机执行全帧 OCR；只保守排除边缘的时钟、明确导航按钮及组合控件、地址栏等。章节标题和正文中的同名词不会仅因词语相同被全局删除。
- 本轮没有新增一轮 AI“先理解页面再提正文”的请求。先使用本机 OCR、位置和控件规则处理明显杂项；复杂网页广告、正文标题与脚注仍可能需要后续调校。
- 浮窗会挡住它下面的新像素。二维遮挡排除能保留窗口旁边可见内容，但无法补出从未实际采集的文字；移动浮窗或滚动后会在稳定画面中补读，不编造被遮部分。
- 首屏需先读到稳定正文，避免一开启就用浮窗遮住尚未识别的首段；图标／菜单画面不直接当正文提交。公开样例已完成真机识别与导航复验，具体页面覆盖仍受实际可见范围限制。
- 浮窗删除独占一行的 `LINGFER LIVE` 标题，把空间用于原文。底部“点浮窗…”功能提示继续用于本机自我识别排除；兼容识别旧标记，不能只删排除代码。
- 浮窗显示“正在识别首屏／正在筛选词汇／正在翻译 已完成段数/总段数／正在补充新内容／等待页面停稳”等实际状态，并显示加载动效。没有伪造百分比或剩余秒数。
- 原文页显示本次识别字数、范围说明；上次会话显示页面记录数。仅展示原句片段的词卡会标明“原句片段”，完整已接受文字仍在原文页。

## 原译对照与显示方式

浮窗里的原文在上、译文在下。实时翻译以同一输入句组为对应单位，默认两句／约 240 字；原有系统分享阅读保留三句／900 字的默认分组。超长单句继续进行有界拆分和显示分页。

原文与译文分别根据实际字体、宽度和可用高度测量续页。两边长度不同时分别标“原文续页 a/n”“译文续页 b/m”，保留同一“句组 x/y”与“对照页”编号。较短一侧到末页后继续保留该侧末页，便于查看对应句组；这不是逐字逐行翻译对齐。翻译源文和已得到的译文均不应因显示空间而被静默裁掉。

准备页选择简化为两个并列入口：**浮窗**、**灵动岛**。浮窗模式不再同时额外请求另一套生词放进实时活动；切换灵动岛会停止浮窗呈现并保留读屏，切回浮窗会结束原活动再准备画中画。两者共用原捕获会话及已有结果。

灵动岛的展开、收起、共享指示优先级和可用空间仍由 iOS 决定，应用不能强制常驻展开。没有灵动岛的设备仍可选择支持的画中画，或使用 App 内原文／词卡及系统分享阅读。本轮公开样例已确认系统 PiP 前后按钮和切回 App 后恢复；不把这些结果扩写为所有 App 或所有灵动岛状态已验证。

跨 App 实时读屏继续要求 iOS 27 或以上及用户主动授权；较早系统保留分享、截图和 App 内阅读。

## 本地会话记录

新增的累计状态与当前实时页面模型、生词本分开。停止时保留最近一次会话中最近最多 60 个页面记录，同时限制源文 12 万字符、JSON 2 MB；超限淘汰最早记录。同一视口扩展归到同一记录，已匹配词去重保留，并核对原文偏移。

原 `lastText`、`lastHits`、`translationSegments` 等载荷和收藏格式继续保留，新状态以兼容追加字段提供。原生“查看上次结果”和 Flutter“上次阅读”可使用累计快照；重启、离线仍可看已完成内容，打开缓存不重新发起翻译。明确点击重试时只请求未完成的原译组，已译内容和原始分组保留。

新会话没有接受任何新文字就停止时保留旧结果；较新的系统分享文档优先，避免旧读屏缓存覆盖新分享。旧包已覆盖丢掉的前几页无法补回，累计从新版新会话开始。

详细数据流、限制、兼容与独立测试见 [本地会话验证](local-reading-history-verification.md)。账号、服务器、密钥和云同步没有由本轮修改。

## 本地资料、空书与内置原著

首次使用时，“本地资料”只显示用户主动导入、保存或已加入阅读的资料；没有导入记录时为空，并提供一段英文试读和下方三本独立的内置书入口。枚举应用资产清单只涉及随包资源，不会搜索手机其他目录，也不会看到其他用户的书架或测试文件。

三部新增书籍为完整英文原著正文，来源目录页、原始下载和资产散列记在 [来源清单](../assets/licenses/public-domain-books.json)。目录来源将这些英文原著标为美国公版；本轮没有使用现代中文译本或现代封面。

| 内置书 | 作者／初版 | 原著词数（约） | 来源 |
| --- | --- | --- | --- |
| 爱丽丝梦游仙境 | Lewis Carroll，1865 | 26,524 | [Project Gutenberg #11](https://www.gutenberg.org/ebooks/11) |
| 福尔摩斯历险记 | Arthur Conan Doyle，1892 | 104,506 | [Project Gutenberg #1661](https://www.gutenberg.org/ebooks/1661) |
| 傲慢与偏见 | Jane Austen，1813 | 127,274 | [Project Gutenberg #1342](https://www.gutenberg.org/ebooks/1342) |

移除下载站的外部页头／页尾包装，统一换行、连续空行上限，并删除无说明文字的独立 `[Illustration]` 占位；原著自身卷首、章节、插图说明及结尾保留，并非短节选伪装全本。来源清单已更新正文计数和资产散列，清理后资料专项 6 项通过。点击内置书时明确加入这一本，不自动灌入整套书架。原有中文资产保留。

用户提到的“李明博自传”“艾隆之书”没有出现在当前内置目录或随包资产中。**尚未核对其具体设备记录，不能断言它们就是测试导入，也不能宣称已修复这两份特定文件。** 本轮处理了已确认的通用故障路径：

- 空文件、缺失文件和旧无正文占位记录给出明确错误及重新选择入口，不再用书名／作者冒充正文，也不会因读取失败删除记录和进度。
- iOS 容器路径变动时，仅按应用自身 `Lingfer/ImportedBooks` 的原相对位置寻找已托管副本；不全盘搜索、不随意替换原书身份。
- EPUB 3 没有 NCX 目录时先按 OPF spine 顺序取正文，略过导航文档；旧章节解析仍作兼容回退。解析为空或损坏时给可恢复提示。

资料专项结果见 [本地资料验证 JSON](../artifacts/library-improvements-nov14-verification.json)。特定旧书若仍打不开，需要以设备中那一条记录的来源与文件可读性继续核对。

## 书内阅读风格

书内范围、翻译方向、排版方向统一为受屏高约束的可滚动纸面列表，当前项带勾；七档范围只留一个摘要入口。PDF／扫描／书内选文共用的玻璃面板也改为同样的范围入口，不平铺七档。

括号注释统一为墨蓝，深色主题用浅墨蓝；不再把旧等级颜色直接铺进正文。原文、括号和注释顺序保留，字号和字重区分正文与辅助注释。工具栏和字号／外观面板沿用现有玻璃与纸面风格，大字、窄屏和横屏支持换行／滚动；六种既有阅读主题和持久化值保留。

英文为主的书首次载入默认英译中，随后仍由用户选择方向。进度、书签／高亮、翻译缓存格式和原 AI／收藏回调保留。详细清单见 [书内界面验证](book-reader-ui-verification.md)。其中的图片是实际 Flutter Widget 渲染，**不是 iOS／Android 真机截图**。

## 已完成的自动检查

| 检查 | 已确认结果 | 证据与范围 |
| --- | --- | --- |
| 最终集成 Flutter 全套 | 56 项通过，0 失败 | `/private/tmp/lingfer-integrated-flutter-tests-nov14.log`；包含本轮资料、书内 UI、历史，以及原有阅读／翻译／复习回归。 |
| 阅读稳定性纯 Swift 策略 | 58 项通过 | `scripts/check_live_reading_stability.swift`；日志 `/private/tmp/lingfer-toolchain/reading-nov14-stability-final.log`；全帧过滤、遮挡恢复、同页合并、无损分页及 PiP 范围策略，含后补的两项右上状态簇排除检查。 |
| 本地历史／源文覆盖纯 Swift | 44 项通过 | `scripts/check_live_history.swift`；跨页、去重、容量、损坏状态、Unicode、120 行尾部及偏移。 |
| 真机测试包构建 | `TEST BUILD SUCCEEDED` | `/private/tmp/lingfer-toolchain/reading-nov14-verified-build.log`、`reading-nov14-device-build-final.log`；这是构建通过。 |
| 模拟器测试包构建 | `TEST BUILD SUCCEEDED` | `/private/tmp/lingfer-toolchain/reading-nov14-simulator-build.log`；不能代替跨 App 真机读屏。 |
| 全新模拟器资料／书内真实页面 | `testFirstLaunchLibraryAndReaderNov14` 通过，91.358 秒（最终修复后） | 全新状态“本地资料 0 份”，下方三本独立内置书；打开 Alice 和新版七档范围。截图目录 `docs/ui-screenshots/nov14-library-reader/`。 |
| 公版 TXT 清理后资料专项 | 6 项通过 | 原著全文、占位清理、空行与来源清单散列已复验；为既有 Flutter 全套中资料用例的后续定向复验，不与全套相加。 |

书内 UI 的 7 项、历史＋段落翻译的 14 项和资料相关的子集检查已包含或交叉在 Flutter 回归中，不能再简单相加成更多互不重叠的用例。

以下为该全新 iOS 模拟器的真实应用页面，区别于前述 Widget 组件渲染；同样不当作 iPhone 跨 App 读屏的证据：

- [首次首页](ui-screenshots/nov14-library-reader/nov14-fresh-install-home.png)
- [本地空书架与内置书](ui-screenshots/nov14-library-reader/nov14-fresh-install-public-domain-library.png)
- [Alice 开篇](ui-screenshots/nov14-library-reader/nov14-public-domain-reader.png)
- [Alice 正文与墨蓝释义](ui-screenshots/nov14-library-reader/nov14-public-domain-prose.png)
- [书内操作](ui-screenshots/nov14-library-reader/nov14-public-domain-reader-controls.png)
- [七档范围列表](ui-screenshots/nov14-library-reader/nov14-reader-level-sheet.png)

## 真机首轮失败与已完成复验

首轮测试包：`/private/tmp/lingfer-toolchain/reading-nov14-device.xcresult`；日志：`/private/tmp/lingfer-toolchain/reading-nov14-device.log`。**首轮 3 失败、1 通过的历史保留，以下三项失败已在 stable 四项复验中关闭。**

| 首轮用例 | 结果 | 已观察到的事实／下一步 |
| --- | --- | --- |
| 全页识别与本地会话 | 失败，50.683 秒；已复验关闭 | 下部可见段落的连续锚点断言遇到 OCR 断行；修正锚点核对后重新验证上下部正文与两页累计。不能仅凭上部文字已出现就宣称整屏完整。 |
| 整页对照系统 PiP 前后切换 | 失败，69.895 秒；已复验关闭 | 初轮三次触碰只收到两次回调。补足系统控件几何稳定等待并调整前台音频准备时序后，stable 实收三次回调。 |
| 学习辅助系统 PiP 前后切换 | 失败，57.254 秒；已复验关闭 | 初轮同样少一次实际回调；stable 已核对三次系统跳转及最终游标。不能把脚本发出点击当作按钮已真正响应。 |
| 测试后恢复用户阅读状态 | 通过，5.740 秒 | 首轮恢复用例通过；后续轮次仍须确认停止读屏并恢复用户原状态。 |

复验前已调整：开始读屏／切换浮窗时先在 App 前台激活画中画音频会话，视频仍等待两次稳定正文；系统按钮测试观察按钮位置连续三次稳定后再触碰，避免系统控制层入场／退场动画干扰点击。

stable 结果包：`/private/tmp/lingfer-toolchain/reading-nov14-device-stable.xcresult`；日志同前缀 `.log`。公开页面导航截图来自 2026-11-14 18:01–18:03（Asia/Macau），原文／浮窗／历史截图已替换为 18:13–18:14 的最终增量结果，见 [真机截图与来源](ui-screenshots/nov14-live-reading/README.md)。stable 四项均通过：

| stable 真机用例 | 结果 | 已核对内容 |
| --- | --- | --- |
| `testFullPageCaptureAndLocalSessionHistory` | 66.560 秒，通过 | 公开页面上下部锚点、首屏筛词、第二页及停止后累计；当轮为 699 字、2 个页面记录、14 个匹配词，后续增量图为 698 字。 |
| `testPiPSystemPassageNavigation` | 84.667 秒，通过 | 外部页面保持前台，前进／前进／后退实收 3 次 AVKit 回调；最终 focus=3；主请求数始终 3，没有因切换重翻译。 |
| `testPiPSystemWordNavigation` | 72.151 秒，通过 | 词卡同样实收 3 次 AVKit 回调；最终 focus=4；主请求数始终 0，离线词义复用。 |
| `testRestoreUserReadingAfterFixtureQA` | 4.886 秒，通过 | 停止测试读屏并恢复用户原阅读状态；不导出该用例的用户界面截图。 |

截图按测试名和自定义附件名前缀用苹果公开的 `xcresulttool export attachments` 导出，未修改像素、没有导出用户真实公众号、额外系统截图或全 UI hierarchy。导航截图保留 AVKit 自身控制层，系统按钮会临时覆盖部分文字；界面没有被后期补绘。

**stable 之后的最终增量：**原文曾混入右上角电量／信号 OCR 杂项 `55+ / 1X1à`，因此补了小状态簇保守排除和两项策略检查（总 58 项）。最终资产构建成功；`/private/tmp/lingfer-toolchain/reading-nov14-device-final.xcresult` 及同前缀日志记录 `testFullPageCaptureAndLocalSessionHistory` 62.839 秒通过、`testRestoreUserReadingAfterFixtureQA` 5.219 秒通过，18:14:15 结束。最终源文／浮窗／历史图取自这一轮，首屏 346 字、8 个匹配词；停止后累计 698 字、2 个页面记录、14 个匹配词。

**遗留：**最终公开原文已去掉 `55+`，但仍残留一小段 `1X1à` 状态栏 OCR 杂项。当前保守规则不等于完美正文分类，也没有声称页头／页脚和广告全部清除；这类误识别仍需结合更多实际页面继续调校。原图如实保留该残留，没有后期擦除。

上述真机结果基于仓库内三份公开 fixture，不等同于用户每篇真实公众号／小说均已扫全，也未穷尽所有语言、移动遮挡、受保护页面或系统灵动岛状态。Android 共用书内／资料展示尚需对应设备回归。

本轮没有新的正式 App Store 提交凭证。现有商店草稿、旧归档和用户未提交的工作区改动应继续保留。

## 主要修改区域

- iOS 读屏／浮窗：`LiveScreenCapture.swift`、`LiveReadingViewport.swift`、`LivePreviewExcerpt.swift`、`LingferShare/ShareViewController.swift`，以及对应真机测试和公开样例。
- 本地会话与完整源文分组：`ios/Shared/CompanionStore.swift`、`NativeReadingModel.swift`、`ReadingPassages.swift`；Flutter `live_reading_history.dart`、`companion_controller.dart`、`page_translation.dart`、`companion_reader.dart` 的历史／重试接入。
- 资料：`asset_books_service.dart`、`book_text_service.dart`、`imported_file_store.dart`、`companion_shell.dart` 相关入口、三本 TXT、来源清单与资产声明。
- 书内展示：`reading_screen.dart`、`reading_text.dart`、`apple_glass_sheet.dart`、新增 `book_reader_presentation.dart`。
- 自动回归：`test/library_samples_test.dart`、`test/book_reader_ui_test.dart`、`test/live_reading_history_test.dart`、纯 Swift 检查及本轮 `ReadingUITests` 用例。

上述功能并非一次性重写原项目。Android 原生读屏、服务器、密钥、收藏格式和账号云同步不由本轮更改；Flutter 共有的资料与书内展示变更仍应在 Android 真机补相应回归。

## 最后展示修正与安装

书内操作栏展开时隐藏底部 AI 加载角标，避免压住“字号与外观”；原解析任务继续运行。既有书内 UI 专项 7/7、独立全新模拟器实际流程 1/1 通过（91.358 秒），六张截图已换成此轮原始 PNG。最后 Release 构建和完整代码签名验证通过，已保留数据覆盖安装到连接的 iPhone；原用户阅读结果、设置已在样例测试结束后恢复。包中三本 TXT 与当前资产逐字节一致。[本机包核验](../artifacts/reading-refinement-nov14/final-package-verification.json)记录构建、资产、展示源文件散列及安装状态；本轮仍未上传 TestFlight 或提交审核。

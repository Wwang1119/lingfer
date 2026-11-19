# 阅读控件字体与紧凑布局修订

2026-11-14，接续书内阅读界面统一后的用户反馈。本轮只调整 Flutter 展示，没有修改识别、翻译、筛词、收藏、进度、缓存或操作回调。

## 标题混用字形的实际原因

已读取现有 TTF 的 Unicode `cmap` 表：`assets/fonts/lingfer-display-semibold.ttf` 为 332,988 字节，包含 740 个码点，SHA256 为 `2211ef427da16f5d5cd2ef8c0076228f9170de652b082d5d04cd02b795da9e88`。

| 显示文字 | 当前子集缺少的字 |
| --- | --- |
| 阅读工具 | 工、具 |
| 字号与外观 | 观 |
| 爱丽丝梦游仙境 | 丽、丝、梦、游、仙 |
| 福尔摩斯历险记 | 尔、摩、斯、历、险 |
| 内置公版书、傲慢与偏见 | 无 |

这与界面上一部分字为衬线、另一部分字回退到系统字体的表现一致。现有字体许可为 `assets/licenses/NotoSerifSC-OFL.txt`；字体和许可均保留，没有下载新字体、改名冒充完整字体或打包系统字体。

新增 `LingferType.interfaceHeading` 与 `interfaceText`：采用当前 Flutter 工具链 `packages/flutter/lib/src/cupertino/text_theme.dart` 中实际使用的系统文本别名 `CupertinoSystemText`，并保留完整系统中文后备字体。`inherit: false` 避免从上层继续继承子集显示字体。最终主任务将所有界面标题及 `heading` 别名统一到该样式，只有首页“语渡”通过单独的 `brandHeading` 使用原显示字体。

公版书区标题和三本书名、共享范围列表和错误页标题使用新界面字体。书内“阅读工具”“字号与外观”已由主任务在 `reading_screen.dart` 接入 `LingferType.interfaceHeading`，字号 18；四项工具也由主任务接入紧凑玻璃按钮。此文件未由本轮子任务修改。

## 控件尺寸

- 提供 `BookReaderActionChip` 供书内工具复用，与主页使用同一个 `LingferGlassSurface`，14sp 文字、18dp 图标，保留至少 48dp 点击区域；内容随系统字号换行。
- PDF／扫描／书内选文的范围入口改为单行玻璃摘要，不再用两行文字撑高整块面板，仍执行原选择结果回调。
- 范围列表最大宽度 420dp，普通选项最小高度 48dp、15sp 文字，标题 18sp；减少原有内边距和空白。390×844、普通字号渲染中七档能同时显示。
- 面板高度受屏高约束，大字和横屏仍可滚动；关闭入口固定可见。较长的说明放在可滚动部分，避免大字体说明占满固定标题区。

## 验证与边界

- `test/book_reader_ui_test.dart`：7 项通过；保留原有窄屏／大字、横屏、范围选择、空资料和英语方向验证。仅在原滚动用例中等待动画稳定后点击，补普通字号可选渲染，没有新增复刻实现的测试。
- `test/companion_ui_test.dart`：8 项通过，未修改该测试文件。
- 修改文件的分析没有错误；整份 `companion_shell.dart` 有一条范围外 `if` 花括号提示，已交主任务处理。

日志：`/private/tmp/lingfer-reader-compact-ui-nov14-final-font.log`、`/private/tmp/lingfer-reader-compact-companion-nov14.log`、`/private/tmp/lingfer-reader-compact-analyze-nov14.log`。

以下为真实 Flutter Widget 测试渲染，**不是手机截图**。可选渲染使用本机现有中文系统字体供测试字体别名解析，没有把系统字体复制到应用。

- [普通字号紧凑范围列表](book-reader-ui-renderings/ranges-compact-normal-type.png)
- [窄屏两倍字号范围列表](book-reader-ui-renderings/ranges-large-type.png)
- [两倍字号单行范围摘要](book-reader-ui-renderings/shared-range-summary-large-type.png)
- [横屏大字号](book-reader-ui-renderings/layout-landscape-large-type.png)

`docs/ui-screenshots/nov14-library-reader/` 是前一轮已通过的模拟器记录，不能当成本次字体与控件修订后的设备截图。本轮未构建模拟器／真机包，也未操作设备、提交、推送或发布；最终设备截图和版本整理由主任务统一进行。

直接修改文件：`lib/widgets/book_reader_presentation.dart`、`lib/widgets/apple_glass_sheet.dart`、`lib/features/companion/lingfer_theme.dart`、`lib/features/companion/companion_shell.dart`（仅公版书标题区）、`test/book_reader_ui_test.dart`（仅原有用例等待与可选渲染）、本文及上述 Widget 渲染图。

随后按主任务授权补充的设置内缓存／旧示例清理见 [本地存储清理验证](reader-storage-cleanup-verification.md)，不混入本次字体修改的范围。

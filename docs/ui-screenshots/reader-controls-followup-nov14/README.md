# 候选（14）最终模拟器原始截图

> **以下八张均来自同一份最终测试结果。** 显式注释区间、返回箭头和移除范围长说明已进入本次模拟器构建。单独 Runner Release 构建与严格签名验证已由主任务完成，见 [最终清单](../../../artifacts/reader-controls-nov14-followup/verification.json)；图片仍不能证明物理 iPhone 已安装、执行清理或已分发。

2026-11-14，`2.1.1（14）`。设备为独立的 iPhone 18 Pro／iOS 27.2 模拟器 `Lingfer Controls Nov14`，UDID `12656C7B-177E-410E-AA92-E3D4EE23A582`。

| 用例 | 结果与来源 |
| --- | --- |
| `testFirstLaunchLibraryAndReaderNov14` | 1 项通过、0 失败，24.935 秒。 |
| `testIndependentReadingSetupControls` | 1 项通过、0 失败，31.677 秒；原生 Host 明确强制浅色，只验证准备界面和独立选择回调。 |

两项合计 **2 项通过、0 失败**，均来自 `/private/tmp/lingfer-toolchain/reader-followup-final-simulator.xcresult`，日志为同前缀 `.log`。八张 PNG 均从该结果的 XCTest `XCUIScreen.main.screenshot()` 附件逐字节复制，没有裁切、修饰、加字或合成。更早版本的截图目录未覆盖。每张的原附件名、捕获时间、尺寸及 SHA256 见 [provenance.json](provenance.json)。

| 实际界面 | 原图 |
| --- | --- |
| 首次首页，本地资料 0 份 | [nov14-fresh-install-home.png](nov14-fresh-install-home.png) |
| 三本公版书、统一书名字体 | [nov14-fresh-install-public-domain-library.png](nov14-fresh-install-public-domain-library.png) |
| 实际打开 Alice 初始页与生成状态 | [nov14-public-domain-reader.png](nov14-public-domain-reader.png) |
| 系统标题与紧凑玻璃阅读工具 | [nov14-public-domain-reader-controls.png](nov14-public-domain-reader-controls.png) |
| 七档紧凑范围列表 | [nov14-reader-level-sheet.png](nov14-reader-level-sheet.png) |
| Chapter I 正文与 `peeped(偷看)` 墨蓝释义 | [nov14-public-domain-prose.png](nov14-public-domain-prose.png) |
| 系统深色下的浅色原生准备页：整页对照 | [store-ios-live-ready-independent-controls.png](store-ios-live-ready-independent-controls.png) |
| 系统深色下的浅色原生准备页：学习辅助 | [store-ios-live-ready-learning.png](store-ios-live-ready-learning.png) |

目视确认“内置公版书”、三本书名和“阅读工具”字形统一；七档列表完整可见且冗长说明已删除，原生准备页使用浅纸面和墨蓝，没有小“语渡”副标题，左上已为单个返回箭头，没有原来的返回文字折行。正文显示蓝色中文释义 `peeped(偷看)`；工具图保留加载指示淡出的实际瞬间。

这组 Alice 段落没有原著自带英文括号样例，不能据此声称已目视验证英文括号样式。该项由最终 90 项 Flutter 测试中的 [显式注释测试](../../../test/reading_text_annotations_test.dart) 验证：原著英文括号保持正文样式、只有新增中文译文着色、分页区间不丢失字符。管理页完成文字也未出现在本组准备页截图中。

本目录是模拟器证据，不是真实 iPhone 截图。原生用例没有开始系统读屏，不能证明画中画启动、音频、跨 App 恢复或切换流畅；没有对用户设备执行缓存或资料清理。书内用例实际打开 Alice，另两本只验证入口可见。没有导出原生用例中重复的 `store-ios-current-home` 附件。

此前 26.020 秒／36.845 秒的快照说明与原附件来源保存在 [历史来源记录](historical-pre-final-provenance.json)，仅供追溯；其旧 PNG 文件名已由本次最终原图替换，原始旧附件仍由历史结果包定位，不能按当前 PNG 校验旧哈希。

# 11 月 14 日 iPhone 随屏阅读真机证据

截图时间：2026-11-14（Asia/Macau）。导航图取自 `reading-nov14-device-stable.xcresult`，18:01:41–18:03:04；源文／浮窗／历史图取自其后最终 `reading-nov14-device-final.xcresult`，18:13:51–18:14:08。两个结果包均位于 `/private/tmp/lingfer-toolchain/`，来自同一物理 iPhone 上的 XCTest 命名附件，对应工作区 `2.1.1+13` 候选。stable 四项测试通过，最终增量 FullPage 62.839 秒和 RestoreUser 5.219 秒通过；（13）仅本机安装验证、尚未上传，不能用本目录宣称 TestFlight（13）已可下载或 App Store 已提交审核。

仅对三个公开 fixture 用例运行苹果公开命令 `xcrun xcresulttool export attachments --test-id ... --filter 'nov14-*'` 或 `--filter 'pip-...-*'`。附件逐字节复制，仅重命名；没有裁剪、拼接、生成内容或修改像素。映射、精确时间和 SHA-256 见 [provenance.json](provenance.json)，其中不记录设备唯一标识。

没有导出恢复用户状态用例的截图、真实公众号／私人书架、额外系统截图或 UI hierarchy。页面上“微信”等文字是仓库的公开测试 fixture，不是用户的公众号内容。三份来源为 `test/fixtures/full-page-reading.html`、`island-chinese.html`、`stable-scroll.html`。

| 截图 | 实际显示与限制 |
| --- | --- |
| [公开页面源图](nov14-visible-source-fixture.png) | 第一页全部可见正文；此帧没有 PiP，不当作浮窗已经打开的证据。 |
| [首屏已识别原文](nov14-complete-first-page-source.png) | 最终增量已识别 346 字与 8 个当前范围词；原文可滚动。55+ 已排除，仍有短小 1X1à 状态簇杂项。 |
| [下一页学习浮窗](nov14-next-page-learning-float.png) | 实际跨 App PiP 显示词卡、原句高亮及 3/9 编号；AVKit 控制层已展开。 |
| [停止后累计原文](nov14-local-session-history-source.png) | 最终增量 698 字、2 个页面记录；本地会话累计，不依赖云数据库。 |
| [停止后累计词卡](nov14-local-session-history-words.png) | 累计 14 个匹配词；不代表自动收藏了这些词。 |
| [原译组 3／7](nov14-paired-before-skip.png) | 同组中文在上、英文在下，实际系统前后按钮可见。 |
| [前进两次到组 5／7](nov14-paired-after-two-forward.png) | 外部页面仍在前台，同组原译同时变化。 |
| [后退到组 4／7](nov14-paired-after-back.png) | 系统控制层保留；日志实收三次 AVKit 回调，主请求数始终为 3。 |
| [词卡切换前](nov14-word-before-skip.png) | occasional，4/9，原句目标词高亮。 |
| [词卡前进两次后退一次](nov14-word-after-back.png) | original，5/9，目标词高亮；日志实收三次回调，主请求数始终为 0。 |

系统 PiP 控制层会暂时覆盖部分文字，截图如实保留；实际导航结论同时根据 AVKit 回调计数、最终游标及请求数确认，不仅凭一张静态图判断。stable 曾见 `55+ / 1X1à` 状态栏杂项，追加右上小状态簇排除后，最终原文和历史图已去掉 `55+`，仍残留短小 `1X1à`。最终增量复验已通过，但此保守规则并非完美正文分类；遗留没有后期擦除，也不宣称页头／页脚全部清理。

本目录不证明所有 App 的每屏、被遮内容或受保护页面已完整识别，也不证明所有灵动岛状态。全新模拟器资料／书内真实页面另见 `../nov14-library-reader/`；Flutter 组件渲染不与本目录混用。

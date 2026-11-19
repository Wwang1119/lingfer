# iOS 随屏阅读稳定性验证 · 2.1.1（10）

日期：2026-11-09。本轮针对切换 App 后浮窗黑屏、多句译文、全部词卡访问、原词高亮及滚动时的位置稳定性。保留工作区最新 Flutter UI 与其他窗口的未提交改动；没有提交、推送或发布正式 App Store 更新。

## 本轮行为

- **后台浮窗恢复**：保留有效的画中画源视图，拒绝离屏／零尺寸替代视图；后台持续补帧，处理解码失败和需刷新状态。绘制完成并解锁像素缓冲后再送入异步渲染器。主 App 内原画中画按钮在浮窗已运行时执行重绘，保留原文、缓存和当前位置，不重新请求翻译。
- **多句译文**：合并 OCR 的视觉换行，按语义句子及段落组织，每组最多 3 个完整句子；极长句有长度上限。浮窗优先显示译文，保留原文摘要；超出容量的内容分页而非丢弃。画中画的前后按钮切换词卡或译文页，切换缓存页不会重新调用服务。
- **选词定位**：显示包含目标词的短原句，目标词加粗高亮，下面显示该词和基础释义；增加“上／中／下部 · 距顶 N%”提示。原句截取随可用空间缩短，尽量保留目标词及附近语境。
- **轻滑不跳词**：把稳定原文与不断移动的 OCR 坐标分开维护。目标仍在距顶约 12%～85% 的阅读区时保持该词；离开阅读区并连续确认后，选择靠近距顶约 35% 的可读目标。短时漏识别、微小移动及选词菜单遮挡保留当前位置，不把每帧变化都提交给服务。实际内容变更经过连续两次观察确认。
- **手动切词**：用户选中的词在明显滚动前保持；移除旧的每 10 秒自动轮换。菜单／遮挡恢复和重绘也不清空当前词。
- **实时活动**：一张可读词卡配“上一项／当前位置与总数／下一项”，保留暂停、停止和回到词卡入口；可访问当前结果中的所有项，不再仅显示前 3 个词。下一项为真实 Live Activity AppIntent，在后台更新当前会话。
- **避免识别自己**：画中画与实时活动带有独立拉丁识别标记，排除自身卡片及系统选词操作条。修复展开自身卡片后 OCR 把卡片读回正文、导致词数缩减和再次请求的问题。
- **语言提示**：原文与译文语言相同时明确提示修改译文语言；浮窗保留实际错误提示。测试结束已将手机恢复为用户指定的“自动识别 → 英语”。

## 实际验证

| 检查 | 结果与证据 |
| --- | --- |
| 稳定正文、滚动、遮挡、改页、OCR 重排／范围、句子分组、无损分页 | `scripts/check_live_reading_stability.swift`：23 项断言通过 |
| 高亮词附近原句截取 | `scripts/check_live_preview_excerpt.swift`：12 项断言通过 |
| iPhone 15 Pro Max / iOS 27.2，真实系统读屏、画中画与网络服务 | `testStableReadingAndTranslation`：130.685 秒，0 失败；`/private/tmp/lingfer-toolchain/reading-stability-10-device-9.xcresult` |
| 语言恢复 | `testRestoreAutomaticEnglishPreference`：23.147 秒，0 失败；`/private/tmp/lingfer-toolchain/reading-stability-10-preferences.xcresult` |
| 发布包 | Release archive 构建通过；三个 bundle 的最终签名与分发状态记录在 `artifacts/testflight-2.1.1-10-signing-verification.json` 及本文件末尾 |

真机集成用例验证：切到 Safari 后持续后台显示、重绘不发新服务请求、轻滑保留目标与请求数、目标真正离开后再换词、通知中心实时活动的下一项实际生效且不污染正文、真实服务的完整段落译文、缓存译文分页不重复请求、正常停止读屏。测试使用公开英文样例，不读取个人聊天内容。

真机结果还记录了 1 条非失败运行警告：音频会话在主线程同步激活／停用可能影响响应速度；本轮未观察到相应卡死，留作后续改为异步音频会话调用。语言恢复用例无运行警告。

最终通过用例之后只补充了“原文与译文相同”的两处错误呈现；这些最终生产源已通过 Release archive 编译。早期调试运行中的等待时间、系统菜单遮挡及小字 OCR 断言失败不计为通过：最终断言结合会话状态、可测区域的真实像素与人工截图核对，避免用小标题 OCR 作为唯一渲染依据。本轮没有重复改动既有 Flutter UI 或扩大 Android 范围；前轮 36 项 Flutter 测试记录仍见原交接文档。

用户原先那一次黑屏没有保留下足够现场日志，因此不能认定唯一根因。本轮修复了可确认的源视图生命周期、后台补帧及像素缓冲释放时序问题，最终真机后台与重绘检查未见黑屏；不能据此保证所有系统中断、受保护内容及其他设备都不会出现黑屏。

## 真机截图

- [后台恢复后的浮窗与原词高亮](ios-reading-stability-screenshots/stable-ios-background-recovered.png)
- [原句与位置提示](ios-reading-stability-screenshots/stable-ios-highlight-and-location.png)
- [小幅滚动保持位置](ios-reading-stability-screenshots/stable-ios-small-scroll-keeps-anchor.png)
- [滚动离开原位置后切换目标](ios-reading-stability-screenshots/stable-ios-scroll-moves-anchor.png)
- [多句完整译文浮窗](ios-reading-stability-screenshots/stable-ios-multiline-page-translation.png)
- [主 App 中的完整段落结果](ios-reading-stability-screenshots/stable-ios-complete-passage-in-app.png)
- [实时活动分页与全部结果计数](ios-reading-stability-screenshots/stable-ios-activity-paging.png)
- [已恢复自动识别 → 英语](ios-reading-stability-screenshots/stable-ios-restored-automatic-english.png)

全部来自最终通过的真机测试。实时活动截图只保留语渡自身卡片；主 App 的部分测试截图包含 `--lingfer-live-qa` 专用诊断入口，正常 Beta 不展示这些入口。

## 边界与下一轮交接

- iOS 仍使用系统画中画及实时活动；无法像 Android 一样在其他 App 的原文位置任意叠加词框或划线。坐标提示基于 OCR 行框，是近似阅读位置，不能当成逐字像素级定位。
- 灵动岛展示优先级由系统决定，录屏／共享提示可能占据岛位置；不能保证每次都直接显示语渡。当前可在通知中心自己的实时活动卡片访问上一项／下一项。实时活动不提供任意滚动长列表。
- “整页对照”处理当前屏幕与已识别的缓存内容，不是一次抓取整份 PDF／整本小说。译文分页保存全部已返回文字；源文仅在浮窗显示摘要，完整内容仍可回主 App 查看。
- 超长单词或释义仍受系统卡片大小约束，完整词卡从“词卡”入口查看。实时活动新增可选 `position`／`total` 字段以兼容旧状态；未修改后端请求结构、App Group 名称、现有收藏格式、密钥、Safari 预处理及同步协议。
- **UI 窗口注意**：`LINGFER LIVE`（画中画）与 `LINGFER CARD`（实时活动）是 OCR 自身排除标记。若修改或删除，必须同时调整 `LiveScreenCapture.swift` 的屏蔽识别，避免译文再次被读入正文。主题角色色继续使用当前温白纸面和墨蓝色。
- 主 App 随屏页的测试截图中，标题与部分辅助状态文字在当前浅色背景上对比度偏低；保留现有 UI 窗口实现，作为后续统一原生样式的展示事项，当前正文与浮窗译文另有可读样式。
- 未新增收费云资源或购买方案。测试结束已停止读屏及本地样例服务器；用户可恢复原自动锁屏时间。

## 本轮直接修改文件

- `ios/Runner/LiveScreenCapture.swift`：渲染恢复、稳定读屏、位置策略、选词／译文分页、排除自身及诊断入口。
- `ios/Runner/LiveReadingViewport.swift`（新增）：稳定原文、几何位置映射、菜单识别及 OCR 重排投影。
- `ios/Runner/LivePreviewExcerpt.swift`：保留短语境截取，移除定时轮词游标。
- `ios/Shared/ReadingPassages.swift`（新增）：句子／段落分组和无损展示分页。
- `ios/Shared/NativeReadingModel.swift`：多句译文分组、只读请求计数和同语言错误反馈。
- `ios/Shared/ReadingActivityAttributes.swift`、`ReadingActivityIntents.swift`：单卡状态、位置与总数、前后导航操作。
- `ios/Runner/ReadingActivityManager.swift`、`ios/LingferActivity/ReadingActivityWidget.swift`：状态去重、可读单卡、全部结果分页与自身排除标记。
- `ios/Runner.xcodeproj/project.pbxproj`：新文件加入原有 Runner／分享扩展目标。
- `ios/RunnerUITests/ReadingUITests.swift`、`scripts/check_live_reading_stability.swift`（新增）、`scripts/check_live_preview_excerpt.swift`、`test/fixtures/stable-scroll.html`（新增）：必要回归及公开样例。
- `pubspec.yaml`：版本更新到 2.1.1+10；文档、真实截图、源文件清单和发布凭证。

## TestFlight 状态

2.1.1（10）已于 2026-11-09 22:01 上传成功，22:15 核实原“王业翔内部测试”组（2 位测试员）中状态为“正在测试”，可以通过 TestFlight 下载。测试说明保存后重新进入页面复核，内容保留且保存按钮禁用。

- [原测试组可下载凭证](release-screenshots/testflight-2.1.1-10-ready.jpg)
- [已保存的测试说明](release-screenshots/testflight-2.1.1-10-notes.jpg)
- 构建 ID：`f9ecb943-8007-4da2-b727-ca444dbdf4bf`；群组 ID：`ac061d25-1fd2-4dea-9da1-fe826a661834`。
- 主 App、分享扩展、实时活动扩展均通过分发签名与版本核验；上传日志、导出包及三组件签名凭证已保留。165 个生产源／资源文件与归档前冻结清单一致。
- 发布状态见 `artifacts/testflight-2.1.1-10-status.json`，本机留存包为 `artifacts/Lingfer-2.1.1-10-TestFlight.ipa`；导出包 SHA-256 为 `27f819cf2427410618db491ec5b8734d43b0ffd3e5723b3faf7b22536fb746c3`。上传使用同一归档重新导出签名，未宣称上传 ZIP 与本机 ZIP 的逐字节哈希相同。
- 仅分发内部 Beta，没有提交正式商店审核或修改线上正式版本。

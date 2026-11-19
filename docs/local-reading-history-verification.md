# 随屏阅读本地会话结果

日期：2026-11-14。该记录只覆盖本地会话、已接受原文的请求覆盖和历史重试；屏幕遮挡恢复、正文识别及实际浮窗排版另由本轮 iOS 集成验收确认。

## 原因与行为

旧版每次换页都会覆盖 `lastText`、`lastHits` 与段落译文；原生“查看上次结果”直接展示最后一页的模型。Flutter 原来也只持久保存偏好、生词和复习进度，没有累计随屏会话。跨几页后只剩一个词，与没有开通云数据库无关。

新版从已接受的文字和实际完成的词卡／译文累计本次会话，不把历史词加入当前浮窗的分页。停止后仍能查看本机记录，App 重启后 Flutter 也可恢复；再次打开已有结果不会自动重发 AI 请求，词卡不会自动加入生词本。

本地会话保留最近最多 60 个页面记录，同时限制源文 12 万字符、序列化 2 MB；超出时移除最早记录。页面记录是已接受的视口内容，不等于整篇文章或 PDF 的实际页数。同一 `liveHistoryPageKey` 补充文字归入同一记录并保留已有词，词位置会重新核对；无法唯一定位时保留词卡原句而移除不可靠的偏移。

显示上次结果时合并最近同一语言方向、阅读模式和学习范围的页面；其他配置的记录仍留在本机会话 JSON 中。首次开启但没有接受任何新文字就停止，不会用空会话抹掉旧结果。较新的系统分享文档也不会被较旧读屏记录覆盖。

旧包已丢掉的前几页无法事后补回，累计从本次修复之后的新会话开始。

## 请求与兼容性

- 原 `lastText`、`lastHits`、`translationSegments`、收藏及已知词格式保留。原生 status 追加 `liveReadingHistory` 摘要与计数，本地存储追加 `liveReadingHistoryV1`，旧消费者可忽略。
- 新的 600 字左右源文分组替代前 36 行硬截断，覆盖模型已经接受的最多 12000 字，并保留 UTF-16 偏移。没有改变请求的 `segments`／响应 `items` 格式或筛词 prompt。
- “只显示一个匹配词”仍不等于只识别一个词。非英语→中文方向最多先取 12 个候选，还会经过考试词表、原文对齐、去重和熟词排除；本轮没有为了凑数量放宽筛词。
- 实时双语分组可由 `liveTranslationSentenceLimit=2` 开启，按两句／约 240 字组织；分享阅读默认三句／900 字不变。超长单句由原有有界拆分与展示分页继续处理，不丢弃后半句。
- 历史译文原始分组和已完成内容会被记住。明确点击“重试”时才请求未完成组，沿用每批 24 段／2400 字协议；损坏的超长组给出错误而不陷入空批次请求。
- 历史中的实际识别语言随快照保存，自动识别模式下重试不会丢掉原有语言信息。凭据、服务器和账号同步均未由本轮改变。

## 集成调用

`LiveReadingSession` 开始时调用 `model.beginLiveHistory()`；在每次接受稳定源文前写 `model.liveHistoryPageKey="epoch:viewportPage"`；停止时先调用 `model.finishLiveHistory()`。历史入口调用 `restoreLastLiveHistory()`，退出历史返回准备页时重新配置原偏好。没有启用历史的分享／词汇伴随模型不会写入会话。

`ShareReadingView` 原文区本来就是可滚动的完整 `model.text`，没有 `prefix` 或行数截断；不完整的源文需要在上游读屏环节确认。恢复历史的 `model.source` 说明页面记录数和字符数，供集成界面的范围说明使用。

## 自动验证

- `scripts/check_live_history.swift`：44 项通过，涵盖多页累计、重复页面、同视口扩展、旧词重定位、UTF-16／表情、容量淘汰、损坏 JSON、部分译文更新，以及 120 行原文尾部不会被请求截掉。
- `test/live_reading_history_test.dart` 与既有 `test/page_translation_test.dart`：14 项通过，涵盖停止恢复、离线重启、活跃页与累计结果隔离、新分享优先、旧载荷／损坏缓存、多语言元数据，以及只重试未完成译文且不重请求已完成部分。
- `NativeReadingModel.swift` Swift 语法解析通过；完整 iOS 编译和真机集成结果以主窗口的最终验收为准，不用这些纯策略测试替代真机证明。

## 本轮文件

- `ios/Shared/CompanionStore.swift`
- `ios/Shared/NativeReadingModel.swift`
- `ios/Shared/ReadingPassages.swift`
- `lib/features/companion/live_reading_history.dart`
- `lib/features/companion/companion_controller.dart`
- `lib/features/companion/page_translation.dart`
- `lib/features/companion/companion_reader.dart`：只改译文重试回调，使明确重试绕过只读历史缓存。
- `scripts/check_live_history.swift`
- `test/live_reading_history_test.dart`

没有提交、推送或发布。

# 灵动岛与浮窗 · 2.1.1（11）内部测试

日期：2026-11-10。本轮修改现有语渡 iOS 原生实现，保留 Flutter 页面、Android、服务端、密钥、读屏授权方式及 App Group 收藏格式。Beta（11）已上传并核实向原两人内部测试组开放，组内状态为「正在测试」，说明已保存。用户最新试用反馈暴露浮窗缺少可操作翻页、首段覆盖不明确和真实文章重复等待，**当前不适合正式发布**。回归通过只说明下列覆盖路径通过，不代替产品验收；重做方向见 [iOS 阅读重做分析](ios-reading-redesign.md)。

## 目前实现

| 用户动作 | 实现行为 |
| --- | --- |
| 选“灵动岛” | 同一读屏会话继续，收起画中画；从灵动岛或通知中心操作 |
| 选“翻译浮窗” | 保留原文与结果，准备源视图和音视频会话，App 内显示内嵌预览，回到文章后台后浮出；App 内不再用系统浮窗盖住设置 |
| 从系统浮窗返回语渡 | 记录为临时还原，界面展示完成后才完成系统回调，保留再次浮出的意图 |
| 再切回文章 | 浮窗模式重新检查可用性并恢复显示，不因返回操作清空结果或重译 |
| 主动关闭系统浮窗 | 读屏继续，记录为主动收起，不反复弹回；可重新显示或切换灵动岛 |
| 活动右侧切换图标 | 打开既有语渡阅读页并设置另一种显示方式 |
| 停止阅读 | 停止捕获、结束实时活动、释放浮窗与音视频资源 |

代码中已确认两处问题：原 `didStopPictureInPicture` 对所有停止事件无条件关闭自动再次浮出；原还原回调没有等待界面展示完成。现在区分临时还原与主动收起，并等待真正展示完成。AVKit 不提供每次停止的明确原因；临时还原依系统还原回调／前台状态判定，其余后台停止静默收起，中断恢复细节仍需真机验收。策略测试及真机系统还原路径均已通过；主 App 前台统一显示内嵌预览，退出前台后再自动浮出。

首次显示建议参考 iPhone 可见安全区几何，这只是初始建议，不是硬件能力或授权检测；用户始终可以选择浮窗。没有灵动岛也保留浮窗及通知中心入口。跨 App 捕获继续使用原 iOS 27 可用性检查，旧系统保留分享／截图阅读。

## 内容和字号

- 顶部保留小标识、当前位置／总数和必要状态，计数不再占按钮行。最新真机调整：两侧内容向内 8／10pt、向下 5pt，避开上方系统区域。按钮区为前后、暂停、停止与切换显示，操作区域 44pt。
- 常用词头正常 22pt，释义 16pt，译文 17pt；辅助功能大字提高正文后减少当前页行数，不缩字强塞全部文字。极长词使用有界字号并继续分页。
- 发送活动前按实际字体测量词头、释义和译文，长内容用前后按钮继续；短词短义有空间时补一行原句并加粗目标词。
- 主程序与扩展共用字号类别和完整词头的排版预算，防止后台／WidgetKit 字号不同或长词末页变化导致裁字。新增的是可选活动展示字段，旧状态仍可解码；未改后端或收藏 JSON。
- `LINGFER CARD`、`LINGFER LIVE` 是排除自身 OCR 的标记，不能只为视觉删除。

苹果说明高度超过 160pt 的实时活动可能被裁切。本轮实际内容区约 92～115pt，为系统上方区域留空间；无法通过应用强制增加系统窗口，也不能保证语渡优先于共享指示占据灵动岛。[Apple 展示说明](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

## 翻译与滚动

- 实时翻译先请求第一组完整语段，再最多三组一批继续；分享阅读保持原批次和服务接口，不等一屏 JSON 全部生成才给首段。
- OCR 间隔从 1.25 秒调为 0.8 秒，仍只处理已授权、未暂停、App 位于后台的会话，不并行重叠识别。
- 新露出几行时先映射到稳定原文；已知内容约占 45% 以上且有可用目标，或请求仍在处理时，不取消请求和重译整屏。明显离开已知区域后再提交。
- 同语言／范围的在线词卡更新中保留旧结果并标明更新；换语言／范围不沿用不匹配词卡。旧坐标必须与词形一致，否则重新匹配。
- 灵动岛模式不持续生成 800×500 浮窗视频帧；切回浮窗再准备。音视频激活与停用使用 iOS 27 异步接口，避免前轮同步主线程调用。
- 已用公开中文样例在真机测试自动识别 → 英语：一次请求返回三项符合当前范围的词；轻滑后请求计数及当前选词不变。该次请求耗时约 1.9 秒，从打开样例到测试器读到结果约 5.9 秒（含测试等待），不是所有页面的延时保证。整段翻译另行验收，不据单次样例宣称固定提速倍数。

## 验证记录

| 检查 | 状态 |
| --- | --- |
| 展示策略与稳定阅读规则 | `scripts/check_live_reading_stability.swift`：32 项断言通过，覆盖还原、关闭、两模式切换及原滚动规则 |
| 实际 UIKit 字体无损分页 | 模拟器执行 `scripts/check_activity_text.swift`：167 页多语言／emoji 内容无遗漏且逐页高度通过；旧状态可解码，加粗长词分页通过，极限 emoji 载荷 3067 字节（小于 4KB） |
| 正式组件渲染 | 普通词、长英文词、长中文词组、译文 × 正常／辅助功能大字，共 8 组；内容区最大 115pt |
| 构建 | 主程序、分享扩展、实时活动及 UI 测试目标构建通过；生产归档通过 |
| 真机前后翻词 | iPhone 15 Pro Max / iOS 27.2，实际长按灵动岛、下一词、收起重开保持选词、上一词、停止：通过，47.723 秒；Safari 始终保持前台 |
| 真机显示切换 | 系统浮窗“恢复全屏幕” → App 内预览 → Safari 恢复浮窗 → 选择灵动岛 → 实际展开与翻词 → 岛内切回浮窗 → 停止：通过，84.447 秒（最新显示切换回归） |
| 语言偏好恢复 | 独立真机用例通过，恢复自动识别 → 英语、整页对照、浮窗＋灵动岛 |

以下是正式 `ReadingActivityWidget` 内容与按钮组件的模拟器渲染。测试工具只调整 Swift 访问级别以调用组件，使用测试文字，不开启捕获或调用翻译服务。**不是系统灵动岛的真机截图**，不能代替系统优先级、还原回调和活动链接验证。

- [普通词卡](island-presentation-layout-screenshots/word-normal.png)
- [长英文词](island-presentation-layout-screenshots/long-word-normal.png)
- [长中文词组](island-presentation-layout-screenshots/long-source-normal.png)
- [多句译文](island-presentation-layout-screenshots/translation-normal.png)
- [大字词卡](island-presentation-layout-screenshots/word-large-type.png)
- [大字译文](island-presentation-layout-screenshots/translation-large-type.png)
- [高度与字号测量](island-presentation-layout-screenshots/measurements.json)

## 修改与后续

本轮直接修改：`ios/Runner/LiveScreenCapture.swift`、`LiveReadingViewport.swift`、`ReadingActivityManager.swift`、`SceneDelegate.swift`；`ios/LingferActivity/ReadingActivityWidget.swift`；`ios/Shared/ReadingActivityAttributes.swift`、`ReadingActivityIntents.swift`、`NativeReadingModel.swift`；`ios/LingferShare/ShareViewController.swift`；`ios/RunnerUITests/ReadingUITests.swift`；`scripts/check_live_reading_stability.swift`、`check_activity_text.swift`、`check_activity_layout.swift`；`pubspec.yaml` 与验证／交接文档。UI 测试目标曾临时加入活动排版源，随后撤回，恢复原测试器框架设置。

最新：翻词操作显式指定 iOS 26+ 的 `.background` 运行模式，保留旧系统 `openAppWhenRun=false`；不再依赖默认运行模式。旧会话已失效时，点击会结束遗留活动并提示重新开启，而不是静默卡住；本地活动内容不变时每 45 秒续期，避免持续阅读同页两分钟后被标为过期。该失效提示尚未单独真机强制杀进程验收，不把它记为通过。后台运行模式依据 [Apple 运行方式说明](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)。

最终共存回归已通过：65.134 秒，自动识别中文→英语、整段译文完整、词卡活动 4 词、真实活动下一词、Safari 恢复浮窗、轻微滚动不增加请求、App 停止。该样例主翻译 3 次请求、词卡 1 次请求、最后单次请求 575ms；不是全程或所有内容的速度保证。独立偏好恢复 21.942 秒通过。结果 `/private/tmp/lingfer-toolchain/island-11-coexist-ui-final.xcresult`。其中词卡操作发生在通知中心，不能当作 PiP 系统翻页按钮已验证。

早先候选归档：`build/ios/archive/Runner-2.1.1-11-final.xcarchive`。字体和组件检查的当时源文件摘要见截图目录 `source-verification.json`；这 8 组是组件渲染，最新顶部间距以实际真机截图为准。此归档是早先候选，晚间真机修复后已过期，不用于上传；最终归档及源文件冻结需要重新生成。


## 本轮实际真机截图

以下均为真实系统灵动岛／AVKit；背景为本机公开测试文章，没有使用私密页面。

| 检查 | 截图 |
| --- | --- |
| 翻词前、下一词、上一词恢复 | [前](island-presentation-device-screenshots/word-before-next.png)、[后](island-presentation-device-screenshots/word-after-next.png)、[恢复](island-presentation-device-screenshots/word-after-previous.png) |
| 最新顶部留白与按钮 | [实际系统卡片裁图](island-presentation-device-screenshots/activity-cropped.png) |
| 浮窗返回 App 后再次恢复 | [恢复后的浮窗](island-presentation-device-screenshots/floating-restored.png) |
| 从灵动岛切回浮窗 | [切换后的浮窗](island-presentation-device-screenshots/floating-after-switch.png) |
| 自动识别中文 → 英语词卡 | [实际结果](island-presentation-device-screenshots/auto-english-words.png) |

测试器早期有连接／解锁／系统动画等待、按错缩小图标的可访问性坐标及诊断文字挤动控制区的问题。动画等待绕行只编译进 UITest runner；诊断行仅 `--lingfer-live-qa` 显示且高度固定，Beta 正常启动不显示。失败轮次没有记为通过；测试始终以最终真实动作验证为准。


## 最终共存角色与发布状态

- `浮窗 + 灵动岛`：两条通道同时运行；整页对照浮窗显示语段，词卡实时活动按范围筛词，使用独立游标。切模式共用进程内词汇缓存。首次默认共存，保存过的选择保留。
- `仅灵动岛`：不生成浮窗视频帧，活动仍可从岛或通知中心操作。无灵动岛设备使用通知中心或浮窗。
- 准备页阅读方式与语言方向独立并列，窄屏／辅助功能大字上下排列。独立控件真机 31.177 秒通过；iPhone 模拟器 54.603 秒、iPad 模拟器旧轮次 78.882 秒通过。
- 主动关闭 PiP 后保持读屏及活动，停止无用视频帧与音频；可重新开启。此关闭分支最新修正已编译／归档，但没有独立最终系统 X 按钮回归，不能写成验收完成。
- 该 iPhone 15 Pro Max 上共存时共享红色指示可能占用整个灵动岛，词卡仍在通知中心；仅灵动岛能实测展开前后翻词。公开 API 不能强制固定展开或抢占系统优先级。
- 最终归档 `build/ios/archive/Runner-2.1.1-11-coexist-final.xcarchive`，21:16 创建，165 个源文件／资源冻结无漂移。其余（11）候选归档已过期，不用于下一次上传。已有云管理发布签名完成上传，未新建或撤销证书。
- TestFlight 构建标识 `abd75070-7619-44e0-844f-dac928db2be5`，原组「王业翔内部测试」2 人，已保存中文验收说明。凭证 `../artifacts/testflight-2.1.1-11-available.png`；当前机器状态 `../artifacts/testflight-2.1.1-11-status.json`。未提交正式审核。
- 最新 iPad 自动化重跑未能开始执行，模拟器进程返回 IPC server died；停止挂起任务。既有真实 iPad 首页／准备页素材仍在 `artifacts/app-store-2.1.1/raw/`，本轮未上传新版 iPad 宣传图。

新增真实证据：[共存词卡](island-presentation-device-screenshots/coexist-vocabulary-card.png)、[下一词](island-presentation-device-screenshots/coexist-vocabulary-next-word.png)、[展开收起后保留的浮窗](island-presentation-device-screenshots/coexist-floating-after-collapse.png)、[最终准备页](island-presentation-device-screenshots/coexist-ready-final.png)。通知中心只保留本 App 卡片裁图，未对外展示其他通知。

本轮早期失败包括诊断参数未传入、系统动画等待和停止按钮的控制中心查找；均保留失败日志，没有计入最终通过。测试已把真实界面断言与可选诊断指标分开；最后一轮指标实际可用且请求计数保持断言通过。**尚未验证 PiP 的可操作前后按钮**，这正是用户最新反馈的主要缺口。

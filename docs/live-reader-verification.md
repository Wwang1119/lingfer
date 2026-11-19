# 随屏阅读、复习与备份验证

日期：2026-11-08。本文保留 2.1.1（5）的历史验证记录，含当时未完成事项。后续（7）已补验自动变化、收藏和分享恢复，并实现独立整页对照；最新结果、真实截图和发布状态见 [整页对照验证](page-translation-verification.md)。

## 本轮功能

- iOS 27+ 主 App 新增系统屏幕共享入口，复用系统分享扩展的词表、筛词、讲解、收藏和 App Group。较早系统保留原来的分享与截图阅读。
- 未开启／已停止读屏时，主 App 保留 App Group 中更新的系统分享记录，避免空的读屏模型覆盖“上次阅读”。
- iOS 使用 ScreenCaptureKit 的真实授权会话，在后台运行 Apple Vision；相同原文不重新分析。实际屏幕画面和当前三个词义组成视频画中画，完整词卡仍在语渡查看。它不提供 Android 那样的任意跨 App 交互浮层。
- 原图不自动存盘、不上传；其他翻译方向与主动请求的讲解仍使用现有文字服务。捕获中保留系统指示；暂停、收起画中画、返回词卡和停止捕获分别处理。
- Android “渡”按钮改为阅读菜单，保留拖动和长按停止；菜单提供暂停、七档范围、原文／译文语言、本页全部词卡、重新识别和回到主 App。
- Android 词卡和菜单均支持点外收起。关闭面板保留当前分析与请求；成功讲解按词、语言和原句缓存，并合并同一讲解的重复请求。
- Android 翻译按原文行缓存，重新出现时将词的位置映射到新的 OCR 坐标；熟词过滤在缓存之后执行，撤销排除不会丢掉缓存结果。主体不变的短工具栏变化不重新请求整页。
- Android 蓝色下划线改为低对比圆角原词提示。放不下完整玻璃词义的词，仍可从菜单的“本页词卡”查看。
- 中文自动识别且目标仍为中文时，学习辅助使用英语方向，继续执行所选考试范围；不会切换为通用难度。语言设置中增加明确说明。
- 生词本新增翻卡自测：先回忆、再看释义和原句；“没记住”10 分钟后再复习，认识后按间隔再出现。复习状态与手动熟词排除分开，重启后保留。
- 生词本可通过系统文件界面导出／合并 JSON 学习备份，包含词条、熟词和复习状态，不包含服务配置或凭证。导入不清空已有词条，校验文件格式与大小。

## 已验证与边界

| 项目 | 结果 |
| --- | --- |
| Flutter 回归 | 24 项通过；包含自动中文方向、原文严格对齐、已知词过滤、离线阅读收藏、复习重启保存、备份重复合并与损坏格式、窄屏大字复习、现有 UI 场景 |
| Android 原生测试 | Fold5 真机通过；缓存不因短目录重请求、缓存坐标重映射、中文保持英语考试范围、熟词排除与撤销；另含三个尺寸／字体场景的原句保留、加载／失败／重试、收藏、范围与停止回调 |
| Android 手动真机 | 展开菜单、点外收起、打开原词词卡、点外回到相同页面标注、真实 AI 讲解均已操作；最终 2.1.1（5）已原位安装并核对版本，数据未清空。最终安装时手机处于锁屏，未把它记为最终交互复测 |
| iOS 真机基础会话 | iPhone 15 Pro Max、iOS 27.2：系统共享整个屏幕、后台识别 Safari 英文、9 个词卡、视频画中画、停止后释放会话，已通过实际测试 |
| iOS 自动变化与主 App 收藏 | iPhone 连接中断，最终自动变化页面／回主 App 回归尚待补验；基础后台与画中画真机已通过。无签名模拟器未注册 App Group，不能代替此验证 |
| iOS 模拟器 | 主 App 与共享词卡可以构建；该 SDK 未向模拟器提供 ScreenCaptureKit，不用模拟结果代替真机读屏验证 |
| 旧系统 | 通过可用性判断与弱链接保留 iOS 15.5 起的分享／截图入口；尚未在旧 iPhone 真机回归 |
| 费用与账号 | 现有 AI 代理正常；本轮未购买、创建数据库或开通短信，尚未接入账号云同步 |

## 真实设备截图

以下截图来自本轮基础流程验证的真实 iPhone 与 Fold5，未做设计稿替换。截取后还同步了原生主题角色色、增加了画中画说明，并修复了未开启读屏时的分享记录显示；最终（5）外观与补充流程截图因手机断连／锁屏尚待补齐。

- [iPhone 后台画中画](live-reader-screenshots/ios-live-preview-verified.png)
- [iPhone 读到的原文](live-reader-screenshots/ios-live-original-verified.png)
- [iPhone 停止读屏](live-reader-screenshots/ios-live-stopped-verified.png)
- [Fold5 阅读菜单](live-reader-screenshots/android-reading-menu-verified.png)
- [Fold5 原词词卡与实际 AI 讲解](live-reader-screenshots/android-word-card-verified.png)
- [Fold5 点外收起并保留标注](live-reader-screenshots/android-word-dismissed-verified.png)

## 腾讯云核对

- 当前账号 CloudBase 可选的上海、广州、新加坡环境列表均为空。只能确认本账号当前未列出旧环境，不能据此认定过去的数据已经删除。
- 北京区域 `yudu-proxy` 显示正常，运行时 Node.js 18.15；本轮实际词卡讲解也收到现有 AI 服务响应。
- 短信显示申请开通页；没有勾选新协议或开通资源。
- 免费体验环境目前需要兑换码，每月 3000 资源点，允许在到期前一个月内手动续六个月，不支持自动续期；付费个人版当前优惠价 19.9 元／月，最终价格以官方购买页为准。来源：[腾讯云计费说明](https://cloud.tencent.com/document/product/876/127357)。
- 用户正在考虑长期维护成本；数据库与账号的后续接入等待方案及开通条件，不能把当前本机持久化或 App Group 同步称为云同步。

## 文件范围

- iOS：`Runner/LiveScreenCapture.swift`、`Runner/ShareStatePlugin.swift`、`Shared/NativeReadingModel.swift`、`LingferShare/ShareViewController.swift`、`Runner/Info.plist`、Xcode 项目、`scripts/add_ios_live_capture.rb`。
- Android：`ScreenReaderService.kt`、`NativeReadingMenu.kt`、`NativeReadingPanel.kt`、`ReadingOptions.kt`、`MultilingualTranslator.kt`、`GlassAnnotations.kt`、原生回归测试。
- Flutter：控制器、原生桥、自动语言处理、阅读入口与说明、生词复习和学习备份组件；没有恢复旧底部三栏，没有覆盖另一窗口的新字体、玻璃控件、导航或启动界面。
- 版本、Flutter 功能测试和 iOS 真机测试；测试页面仅为仓库中不含个人资料的英文样例。

## 发布状态与待办

- TestFlight：2.1.1（5）于 14:58 上传成功，苹果处理完成；原“王业翔内部测试”组显示“正在测试”，保留原 2 位测试员。测试内容显示“已保存”。两人现在可在 TestFlight 更新至（5）。2.1.1（4）是过渡构建，最终交付以（5）为准。没有提交正式 App Store 更新。
- [TestFlight 开放测试凭证](release-screenshots/testflight-2.1.1-5.jpg)；[构建详情](https://appstoreconnect.apple.com/teams/7c6bdc98-9222-4f8e-b45d-f4bca56946d9/apps/6760685092/testflight/ios/5d3d68bd-16e9-4dc8-8a72-ad93c11d6f75)。
- 已校验导出 IPA 主 App 与扩展的版本、签名、分发描述文件和 App Group。安装包、SHA-256、测试说明、签名记录和分发状态保存在本机 `artifacts/`；未加入源码提交。
- 待补：最终自动翻页／收藏与 Safari 分享后冷启动恢复的真机结果、两端最终画面截图。iPhone 后续连接不可用；Android 最终安装后仍锁屏。没有绕过手机锁屏。签名校验已经完成，不能代替这些交互验证。
- 整页翻译需独立于学习辅助，不应把段落译文混进生词 JSON；显示方式已向用户确认，尚未作为本次版本的已完成功能。
- 账号与跨设备云同步等待资源方案；当前以本机数据和显式备份保证基本阅读、收藏与复习不依赖服务器。

本轮不提交或推送 Git；Beta 上传仅使用用户已授权的原内部测试组两位测试员。

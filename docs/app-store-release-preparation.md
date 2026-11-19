# 2.1.1 商店更新准备

## 当前状态：2026-11-17，候选（15）可下载，仍等待用户试用后提交

**TestFlight 2.1.1（15）已上传、处理完成，原“王业翔内部测试”两位测试员的组中显示“正在测试”，可下载**；[状态](../artifacts/testflight-2.1.1-15/status.json)、[内部组凭证](../artifacts/testflight-2.1.1-15/available-internal-group.png)及[上传凭证](../artifacts/testflight-2.1.1-15/xcode-uploaded.png)已留档。App Store 草稿已选择（15）并保存，保留手动发布；**未添加以供审核、未提交审核或正式发布**，等待用户试用 Beta 后再决定上架。

（15）只有两个生产文件相较（14）变化：`pubspec.yaml` 升构建号并将两本旧老舍 EPUB／占位 PDF 退出打包；`ios/Shared/PrivacyInfo.xcprivacy` 补充 Other User Content 与 Browsing History 收集声明。原磁盘文件未删除，三本英文公版书保留，UI 与功能代码未改变。[包内资源／隐私清单／签名核验](../artifacts/testflight-2.1.1-15/package-verification.json)、[（15）源快照](../artifacts/testflight-2.1.1-15/source-manifest.json)及[独立差异复核](../artifacts/app-store-2.1.1-14/privacy-manifest-packaging-review-nov17.json)已保存。商店图片仍准确记录为实际运行（14）的来源，不改写成（15）已运行实拍。

**App 隐私标签已实际发布并重载确认**：Other User Content（其他用户内容）和 Browsing History（浏览历史）两类均为 App Functionality＋Other Purposes，关联用户身份 Yes，跟踪 No；[发布后页面](../artifacts/app-store-2.1.1-14/privacy-labels-after-reload.png)及[状态记录](../artifacts/app-store-2.1.1-14/privacy-labels-status.json)。原“未收集数据”不再是当前标签。标签发布与二进制审核／正式发布是独立事项，腾讯云线上日志实际留存仍未核实。

**新版商店图共 18 张已上传**：iPhone 中屏 6 张、大屏 6 张、iPad 13 寸 6 张，重载后各为 6/10。iPad 为真实 2064×2752 宽屏布局，采集 3/3 通过、182 项（14）源码资源在构建前后匹配，独立视觉 QA 通过；[iPad 原图与来源](../artifacts/app-store-2.1.1-14/IPAD-README.md)、[后台重载凭证](../artifacts/app-store-2.1.1-14/store-ipad-after-reload.png)、[三组上传记录](../artifacts/app-store-2.1.1-14/store-upload-status.json)。没有用手机图拉伸充当平板，13 张不合格 PiP QA 图片继续排除，不能据素材完成宣称首次 PiP 真机已验收。

年龄问卷已按实际内置原著的偶发成熟主题、暴力、恐怖和烟酒提及等填写并保存，重载后一般分级为 **13+**，巴西／越南16+、韩国12+；低于26的系统有旧分级展示。名称、副标题及年龄的[重载凭证](../artifacts/app-store-2.1.1-14/app-information-after-reload-nov17.txt)已留档。问卷不把用户任意导入资料等同于应用内社交或发布平台。

仍待完成：用户试用 Beta；按用户同意下次补首次 PiP／段落导航等真机测试；登录核实腾讯云实际日志与留存配置；完成第三方内容版权声明。版权核对已形成[具体范围、法源与证据缺口](../artifacts/app-store-2.1.1-14/content-rights-review-nov17.md)：现有美国公有领域来源不自动证明148地区均已核实，旧“No第三方内容”声明未改、未把它当成可提交状态。现有 **148 个可供应／27 个不可供应**地区未改动；中国大陆ICP字段仍空，保留真实材料待核而不编造编号。[机器可读发布清单](../artifacts/app-store-2.1.1-14/release-readiness-nov17.json)明确区分已完成与待核项目，不将目前记录标为全部上架条件已齐。

## 11 月 16 日（14）素材与发布准备历史

以下保留当时实际记录；涉及草稿选（14）、旧 No Data 标签及未补 iPad 的状态，均已由上方（15）和 18 图／新标签记录更新，不能作为当前状态。


2026-11-16 App 信息已保存并重载核对：名称“语渡 Lingfer”、副标题“随屏翻译、双语阅读与生词复习”，将在下一版发布时生效。

2026-11-16 商店草稿更新完成：新版真实 iOS 海报已上传中屏、大屏两档，各6张；重新载入媒体管理后均为6/10，新图顺序已目视核对。[后台凭证](../artifacts/app-store-2.1.1-14/store-media-after-reload.png)、[上传记录](../artifacts/app-store-2.1.1-14/store-upload-status.json)、[最终海报预览](../artifacts/app-store-2.1.1-14/poster-contact-sheet.jpg)。草稿已选择同一2.1.1（14）候选并保存，保持手动发布，未添加以供审核。01改用实际新版首页，02为正确阅读准备页；本轮没有合格PiP宣传原图，相关QA图片已排除，不当作最新首次浮窗已经通过的证据。

当前 App 信息只读核对发现：原副标题为空；原内容版权选择为“不包含、显示或访问第三方内容”，但新版包含有来源与许可记录的公版书，需在正式提交前核对并如实更新。现有年龄分级为4+，ICP/数字服务法等账户状态应按实际销售地区核对，不编造备案号或资质。本轮没有代签版权、法律或备案声明。

2026-11-16 最新发布准备：用户已明确授权手机暂时连不上时先推内部 Beta、下次再做真机测试。候选（14）已完成归档 `build/ios/archive/Runner-2.1.1-14-nov16.xcarchive`，主任务确认 `codesign --verify --deep --strict` 退出码 0；[Xcode 上传凭证](../artifacts/testflight-2.1.1-14/xcode-uploaded.png)与 ASC 上传记录 `1ddce610-e18f-4d95-ad14-e244445aa828` 已留存。苹果处理完成，原两人内部组的（14）明确显示“正在测试”，[原组可用凭证](../artifacts/testflight-2.1.1-14/available-internal-group.png)及[最终状态](../artifacts/testflight-2.1.1-14/status.json)由主任务保存；680 字中文测试说明重新进入后已核对内容一致、保存按钮禁用。**（14）现已向原两位内部测试员开放，未提交正式 App Store 审核或发布。** [本轮测试说明](../artifacts/testflight-2.1.1-14/what-to-test-zh-Hans.txt)与[182 项生产源码／资源散列](../artifacts/testflight-2.1.1-14/source-manifest.json)单独保存，不能拿旧（12）的下载凭证替代（14）。

本包恢复系统授权后保留原 native 阅读面板，移除 Dock，修正返回双层玻璃与首次浮窗启动生命周期。11 月 16 日两项模拟器准备／返回 UI 用例通过；最新跨 App 真机回归因设备连接未完成，首次 PiP／段落导航的已知失败继续保留。此前 102 项 Flutter 与 75 项纯 Swift 回归是对应此前快照的证据，不宣称新包已经完整真机验收。

公开隐私政策已于 **2026-11-16** 更新至原有 [腾讯文档地址](https://docs.qq.com/doc/DRnZUeGhsY2JraXJD)。主任务先保存“更新前备份 · 2026-11-16 · 原820字政策”，再替换在线正文；[发布后导出](../artifacts/app-store-2.1.1-14/privacy-policy-published-export.md)包含 11 月 16 日日期及八节内容，[核对凭证](../artifacts/app-store-2.1.1-14/privacy-policy-published-verification.json)记录 `normalizedMatch=true`。ASC 隐私页已实际核实：政策 URL 为同一 QQ 文档，现有已发布标签仍是“未收集数据”。主任务只读查看数据类型编辑后已取消，未改标签或 Publish。**现有 No Data 标签与新增文字 AI 处理及已知默认缓存／上游留存证据不一致；正式提交前须根据 Other User Content、使用目的及关联性完成准确申报。腾讯／DeepSeek 当前账户和日志实际配置仍未知，不能猜测。** 线上政策更新不等于隐私申报已全部完成。

以下保留 11 月 14 日素材制作阶段的范围与历史；当前上传／政策状态以上方 11 月 16 日记录为准。

2026-11-14：按当前 iOS 功能重做宣传图与简体中文说明，独立保存在 [本轮素材包](../artifacts/app-store-2.1.1-14/README.md)。[版式预览](../artifacts/app-store-2.1.1-14/draft-contact-sheet.jpg) 为明确标注的草稿；App 内真实英语→中文逐段对照、公版书入口、公共样例词卡和复习四张已完成目视检查，其余等待本轮 PiP、灵动岛／修正后的原生准备页。不使用旧 Android 风格展示充数，也不把占位图当最终素材上传。公共样例→实际收藏→查看复习答案的独立模拟器用例通过（1/1，50.134 秒）；不把该结果当成稍后新增 AI 许可或真机随屏捕获的验收。

用户已明确要求去掉新加的阅读 Dock，恢复授权后保留原生阅读面板。相关卖点／审核说明已撤回，旧“授权后会收起此面板”的准备页仅保留历史来源，已撤销本轮最终截图资格。PiP 与灵动岛以恢复流程后的真实画面为准。

中文字段已准备在 [metadata-zh-Hans.json](../artifacts/app-store-2.1.1-14/metadata-zh-Hans.json)，[长度检查](../artifacts/app-store-2.1.1-14/metadata-lengths.json) 全部通过。说明中区分 iOS 27+ 用户授权后的系统画中画或灵动岛、较早系统分享与 App 内阅读、本机学习记录与显式文件备份；没有宣传其他 App 原文上的 Android 式贴词、灵动岛常驻展开或账号云同步。数据流写明本机 OCR 与腾讯云中转至 DeepSeek 的文字处理。政策／供应商规则核对见同素材包的 [数据流核对](../artifacts/app-store-2.1.1-14/review-data-flow.md)；政策本地准备稿阶段已由 11 月 16 日线上替换记录更新，供应商实际配置与 ASC 标签仍待核对。

11 月 14 日该素材子任务未覆盖旧已上传资产、未操作 App Store Connect，也未上传或发布。后续主任务已上传（14）二进制，详见本文件顶部最新记录；商店最终原图来源、1320×2868 RGB 成图及人工检查结果仍需按素材清单分别核对，不能据二进制上传推定海报或正式审核完成。

## 2026-11-16 商店草稿保存结果

主任务已将本轮真实 iOS 六图分别上传至中屏（1206×2622）与大屏（1320×2868）两组，每组 6/10；重新载入后数量和新文件名保持，原旧大屏图仅从更新草稿移除，素材库原件保留。首图为当前真实首页，第二图为修正后的阅读准备页，不使用带测试地址和播放器遮挡的旧 PiP QA 图。12 张图的来源、尺寸、色彩与 SHA 检查及独立视觉复核通过。[总览](../artifacts/app-store-2.1.1-14/poster-contact-sheet.jpg)、[后台重载凭证](../artifacts/app-store-2.1.1-14/store-media-after-reload.png)、[上传状态](../artifacts/app-store-2.1.1-14/store-upload-status.json)。

中文介绍、推广文字、关键词、更新内容和审核说明已在 2.1.1 草稿保存；AI 试用说明已明确从“联网 AI”主动打开并允许，不会自动弹说明页。候选构建选择同一（14），保留手动发布。未点击“添加以供审核”，未发布正式更新。

正式提交前仍需用户试用确认，并完成与 AI 文字处理相符的 App 隐私标签，以及尚未换新的 iPad 素材等核对；不能把本次 Beta 可下载或海报上传当成这些项目已验收。


---

# 2.1.1（11）商店更新准备（历史记录）

更新日期：2026-11-10。此文件区分本机已准备、苹果后台已保存和正式发布。正式审核／发布等待用户完成 Beta 验收并确认；未提交审核，未修改现有线上 1.2.9。

## 本机交付

- 最终候选归档：`build/ios/archive/Runner-2.1.1-11-coexist-final.xcarchive`，21:16 创建，归档成功。`artifacts/testflight-2.1.1-11-source-manifest.json` 冻结 165 个生产源文件／资源，最后一次核对无差异；后续仅改测试、文档和宣传素材。
- 简体中文介绍、推广文本、关键词、更新内容和审核备注：`artifacts/app-store-2.1.1/metadata-zh-Hans.json`。
- 六张 iPhone 截图：`artifacts/app-store-2.1.1/screenshots-iphone/`，1320×2868，RGB、不含透明通道；索引 `screenshots-manifest.json` 记录实际界面来源和哈希。
- 预览：`artifacts/app-store-2.1.1/poster-contact-sheet.jpg`。界面来自真实截图，只缩放／裁切，未用 AI 重绘界面或伪造系统能力。第六张采用最新真机设置页，阅读模式与语言方向并列。
- AI 只用于无文字的温白纸面背景，已复制到项目 `design/paper-background-ai.png`；制作方式与提示说明见同目录 `design/provenance.json`。原生组件排版样张与系统真机截图明确分开，不混作真机证据。
- 两张可选标题图：`store-title-5244x2950.png`、`store-title-3840x1646.png`；在视觉检查和后台尺寸确认前不当成已上架素材。

## 后台准备

已建立 iOS 2.1.1「准备提交」草稿，保存了新版中文介绍／更新内容等资料，选择手动发布。六张 iPhone 截图已上传；旧 6.5 英寸版本截图仅从该草稿移除，仍保留在素材库和原线上版本。6.9 英寸新素材供较小尺寸自动适配。

第六张最新版已在 22:35 前后替换并核实回到 6/10；凭证 `artifacts/app-store-2.1.1/store-six-screenshots-updated.png`。文案新增的系统共享指示优先级说明已保存，正式审核未提交。Beta（11）已出现在 TestFlight 并关联原两人内部测试组；已核实原组 2 人、构建（11）「正在测试」，可下载凭证 `artifacts/testflight-2.1.1-11-available.png`。用户新增实测反馈后，正式发布候选尚未通过产品验收，详情见 `docs/ios-reading-redesign.md`。

## 真实功能边界

- iOS 27+ 的主动授权跨 App 捕获；较早系统保留分享／截图／App 内阅读。
- 灵动岛不能由 App 强制常驻展开，系统控制大小及共享指示优先级。词卡实时活动与浮窗同时运行，但不能保证同时占据可见灵动岛；共享指示占位时从通知中心访问词卡。
- 整页对照的浮窗显示语段，独立词卡通道保留学习范围内词汇；词卡选择与轻微滚动复用已有结果。
- 生词、熟词、复习进度保存在本机，支持显式文件备份；没有账号云同步。宣传资料不能写已实现腾讯账号数据库同步。
- 原图／屏幕画面在本机 OCR；联网翻译及讲解发送相应文字到腾讯云中转和 DeepSeek。只宣称已验证的离线英语→中文基础释义，不泛化为所有语言离线翻译。

## 正式提交前遗留

1. 用户试用 Beta（11），确认浮窗恢复、词卡翻页、语言／模式入口和真实阅读体验。
2. 将实际验收通过的同一构建版本绑定商店草稿；不另换未经验收的二进制。记录下载组、测试说明和构建标识。
3. 补 iPad 新版真实界面素材并核对展示；本轮 iPad 宽屏词卡用例曾因测试假设存在窄屏「词卡」页签而失败，不能写成全部 iPad 阅读流程已通过。
4. 核对 App 信息的副标题、分类、支持链接及公开隐私政策链接。保留已有审核联系人，不用推测填写个人字段。
5. 旧 `privacy_policy.html` 日期为 2026 年 3 月，未说明主动共享后的连续 OCR／自动发送文字；“匿名文本”“阅后即焚”“任何形式的持久化存储”超出当前已核实证据。提交前应补充实际流程，并核实腾讯云日志及 DeepSeek 处理／留存配置后更新公开政策和 App 隐私申报，不继续照搬旧承诺。当前代理源文件未写阅读文本日志，但这不等于已核实所有云平台留存。
6. 强制结束 App 后遗留实时活动的失效提示尚未独立真机验收；长时间后台、第三方受保护内容和所有辅助功能字号仍需针对性试用，不能由短样例外推。

发布前的用户确认是对完整候选的确认；本文件和后台草稿的准备不代表已获正式发布许可。


2026-11-12 功能修复交接：候选（12）的真实 PiP 系统按钮连续切词／切译文、返回恢复与停止已通过真机验收，正式归档和签名验证通过，已直接装到连接的 iPhone。TestFlight 上传仍等待 Xcode 团队账户认证／用户在已打开的归档中分发；网页已重新登录。下载状态见 `artifacts/testflight-2.1.1-12-status.json`。六张商店宣传图和草稿不由本轮改写，正式发布仍等待用户验收与此前隐私披露、iPad 截图事项；不能用内部导航回归替代这些条件。


2026-11-12 晚间最终上传状态：2.1.1（12）已通过 Xcode Organizer 的 App Store Connect 分发上传成功，苹果处理完成。已核实原“王业翔内部测试”组仍为 2 位测试员，（12）状态为“正在测试”，简体中文测试说明显示“已保存”。之前的命令行账户错误及等待用户代分发状态已解除。构建 ID 为 `6bb5644e-4cf5-4fc6-bf49-b8a6dd35475a`；凭证 `artifacts/testflight-2.1.1-12-available.png`，最终状态 `artifacts/testflight-2.1.1-12-status.json`。165 项源文件冻结仍一致，正式 App Store 审核未提交，继续等待用户试用验收。

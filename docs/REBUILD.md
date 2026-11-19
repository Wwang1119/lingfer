# 语渡 2.0：现有项目改造

本次改造继续使用 `Wwang1119/novel_reader`，保留 Flutter、应用标识以及旧书架、阅读进度的本地存储键。没有新建产品或替换既有仓库。

## 双端入口

- Android：用户开启屏幕捕获会话，授权悬浮窗后，点按悬浮按钮截取当前可见内容。ML Kit 在本机 OCR，按离线词表筛词，原地显示词卡。没有申请无障碍服务，也没有点击或操作其他 App 的能力。
- iOS：`LingferShare` 系统分享扩展接收文字和截图。Safari 通过官方 JavaScript 预处理取得选中文本或当前视口文字。Apple Vision 在本机 OCR。分享面板内选难度、看释义、收藏、按需调用 AI。
- 两端共享同源词表、筛选规则、熟词排除逻辑和服务接口。主 App 保留图片、文字、TXT/EPUB/PDF/DOCX 阅读。

## 数据和旧版兼容

- 旧书架仍使用 `lens_shelf_v2`，旧阅读进度、批注和导入文件没有迁移或删除。
- 新生词使用本地 `companion_saved_v1` / `companion_known_v1`。
- iOS 通过 `group.com.wang.yudu` 在主 App 和分享扩展之间同步难度、生词和服务配置。共享 JSON 文件经文件协调和原子写入更新，避免两个进程各自缓存设置而看不到新收藏；兼容读取早期偏好设置。真机签名和 App Store 更新前，需要在原 Apple Developer 团队为主应用及扩展启用该 App Group，并注册 `com.wang.yudu.LingferShare`。没有共享容器时，分享面板仍可独立离线阅读，其记录暂不与主 App 同步。
- ECDICT 衍生词表包含 11,441 条有明确考试标签的词条，MIT 许可全文位于 `assets/licenses/ECDICT-LICENSE.txt`。分级是按词表范围初筛，不宣称等同于个人能力测量。

## AI 服务

`cloudbase/deepseek_proxy/index.js` 兼容原来的 HTTP 云函数和聊天格式。新增无模型调用的 GET 健康检查，返回服务可达性及配置状态；健康检查成功不代表已验证模型响应。

模型 API key 只放服务端环境变量。Flutter 用 `--dart-define-from-file=config/runtime.json` 注入代理 URL 和客户端访问令牌；参考 `config/runtime.example.json`。本地运行代理可使用：

```sh
node --env-file=.env.local cloudbase/deepseek_proxy/dev-server.js
```

没有云服务时，文字识别、难度筛词、基础释义和本地收藏仍可使用，AI 讲解明确显示未连接状态。

## 验证

保留原生启动图资源，移除了代码中未调用的旧版 `flutter_native_splash` 运行时插件，解决其与 Android 8 系列构建工具的 namespace 不兼容。需要重新生成启动图时，可独立运行生成工具，避免把工具插件打进 App：`dart pub global activate flutter_native_splash 2.4.8`，然后在项目目录执行 `dart pub global run flutter_native_splash:create`。

```sh
flutter analyze
flutter test
node --test cloudbase/deepseek_proxy/test/*.test.js
flutter build apk --debug --dart-define-from-file=config/runtime.json
flutter build ios --simulator --debug --dart-define-from-file=config/runtime.json
```

安卓读屏应额外验证：拒绝授权、正常识别、重复识别不识别自己的浮层、横竖屏切换、停止会话、锁屏后的资源释放、被保护页面的失败提示，以及前后台切换后的收藏同步。

苹果分享应额外验证：Safari 网页、选中文字、截图、只提供链接的第三方 App，以及 App Group 真机签名后与主 App 的双向同步。

2026-11-07：iPhone 18 Pro / iOS 27.2 模拟器实际通过“选择英文截图 → 本机 OCR → 四级词卡 → 收藏 maintain → 原云函数返回语境讲解 → 生词本显示收藏”的界面测试。截图中的视觉换行会在讲解上下文中连回完整句子。测试代码位于 `ios/RunnerUITests/ReadingUITests.swift`，可通过 `RunnerUITests` scheme 运行；测试用截图和 Safari 英文页面需要预先放入模拟器。模拟器验证不代表已完成 iPhone 真机签名或 App Store 审核。

Safari 分享也已实际通过“系统共享 → 语渡 → 当前页词卡 → 收藏 → 分享面板内 AI 讲解 → 返回主 App 查看收藏”。测试素材在 `test/fixtures/`；可用 `xcrun simctl addmedia booted test/fixtures/reading-sample.png` 添加英文截图，并用本地 HTTP 服务打开 `reading.html`。使用未签名的模拟器构建时，测试前要给主 App 和嵌入扩展补上各自 entitlement 的临时签名并安装最新产物，避免复用旧扩展；该步骤只供模拟器测试，不替代正式开发者签名。

Samsung Galaxy Z Fold5 / Android 16 真机：通过首次说明取消、系统捕获授权取消、授权整个屏幕、跨到浏览器点悬浮按钮识词、离线释义、语境讲解、熟词排除、悬浮收藏同步回主 App，以及停止后服务释放。普通英文样例首轮筛出 9 个词耗时 584ms，标记 SAMPLE 为熟词后再次识别为 8 个词、422ms；耗时包含本次画面等待和本机识别，不代表所有页面性能。重复识别未把自身词卡作为原文。

最终安装包也已在真机复测：四级范围 8 个词 / 534ms，切换六级后 10 个词 / 364ms；悬浮面板内收藏 maintain 和请求讲解正常，更新后既有 researcher 收藏和熟词记录保留。结束测试时停止了捕获服务，并将学习范围恢复为四级。Flutter 的 8 项测试、云函数的 4 项测试通过；新增 Dart 模块静态检查无问题。完整旧读书器仍有历史未使用代码等提示，未将其计为本次新功能检查通过。

2026-11-06 云端排查：当前账号 CloudBase 开发平台无环境，但独立 SCF 北京地域有正常的 `yudu-proxy`（Node.js 18.15），原函数 URL 仍可用。复用现有客户端令牌，用普通英语例句实测得到 HTTP 200 和正确中文讲解。没有更改云函数或购买新资源。当前线上函数尚未部署此仓库新增的 GET 健康检查，GET 返回 401 不等于 AI 服务失效。

短信控制台当前显示“申请开通”，没有看到可用短信服务；仅凭该页面无法确认历史释放原因。本仓库未发现账号、短信登录或远程数据库依赖，现有阅读数据保存在本机，阅读服务可独立运行。未开通短信、未创建数据库或收费环境。

## 2026-11-08 TestFlight Beta

经用户授权，语渡 **2.1.0（3）** 已上传 App Store Connect 并完成苹果处理。原“王业翔内部测试”组的构建版本页显示“正在测试”，该组保留原有 2 位测试员；用户已明确同意两人均可下载。测试内容已保存。没有提交 App Store 正式审核，线上正式版仍为 1.2.9。

- 使用原团队 `8MRN4PZDSG`、主应用 `com.wang.yudu`、扩展 `com.wang.yudu.LingferShare` 与 `group.com.wang.yudu`。苹果新版许可协议由用户本人处理；Xcode 自动完成本机开发签名与托管发布签名。
- 发布模式构建、完整签名归档、分发导出和上传均通过。主 App 与分享扩展的版本一致；最终 IPA 的签名和分发描述文件均包含正确 App Group、应用标识及 TestFlight 权限，关闭调试权限。Safari 预处理、扩展词表和隐私清单均随包保留，运行服务配置与当前 `config/runtime.json` 一致。
- 初次由未签名归档导出的中间包没有 App Group，不曾上传。最终从完整签名归档重新导出、核对后才上传；以后也应使用完整签名归档，不能只以“导出成功”判断共享权限有效。
- 归档：`build/ios/archive/Runner-TestFlight.xcarchive`。已验证安装包：`artifacts/Lingfer-2.1.0-3-TestFlight.ipa`，同目录保留 SHA-256、测试内容和 `testflight-release-status.json`。这些构建产物不纳入版本管理；未提交或推送源码。
- iPhone 使用原测试账号打开 TestFlight → 语渡 → 安装／更新。安装后先打开一次语渡，再用 Safari 或截图的系统分享入口测试收藏同步与 AI 讲解。真机试用结果仍待用户反馈。

[TestFlight 内部组凭证](release-screenshots/testflight-2.1.0-3.png)；[构建版本后台](https://appstoreconnect.apple.com/teams/7c6bdc98-9222-4f8e-b45d-f4bca56946d9/apps/6760685092/testflight/ios/cb258fcf-e859-48d3-8c0a-e07756aad6d4)。

## 2026-11-08 随屏阅读 Beta 2.1.1（5）

本节保留（5）的发布历史；最新进展见下方（7）及整页对照验证。2.1.1（5）已上传并完成苹果处理，原“王业翔内部测试”组的 2 位测试员可下载，组内状态为“正在测试”。测试内容已保存；没有提交正式 App Store 审核。请在 TestFlight → 语渡更新到 **2.1.1（5）**。

iOS 27+ 的系统屏幕共享、后台 OCR 和视频画中画已在 iPhone 15 Pro Max / iOS 27.2 通过基础真机验证。画中画显示真实缩略画面与当前三个词义，完整原句、词卡、讲解在语渡内；它不提供 Android 式任意跨 App 可点击浮层。开启系统共享后返回语渡点“画中画预览”，再切换阅读应用；点“停止”才结束捕获。较早系统保留分享和截图入口。

Android 增加阅读菜单、点外收起和按原文缓存；中文自动识别保留所选英语考试范围；蓝色线改为低对比原词提示。生词本新增本机间隔复习与导入／导出学习备份，未开通账号云同步。最终 Android 2.1.1（5）已保留数据安装到 Fold5。

Flutter 24 项测试、相关静态检查及 Android 真机原生回归通过。iPhone 后续连接中断，最终自动变化页面／主 App 收藏和分享后冷启动恢复的补充回归尚待真机确认；不能用无 App Group 的模拟器代替验证。具体截图、直接修改文件与遗留事项见 [随屏功能验证](live-reader-verification.md)。

- 已验证归档：`build/ios/archive/Runner-2.1.1-5-final.xcarchive`。
- 已上传包：`artifacts/Lingfer-2.1.1-5-TestFlight.ipa`，SHA-256：`312902ae302b9d9ae5b21a4a79a14a4acf60790a5297bd636ac1614df0c2503c`。
- 主 App 与扩展均为 2.1.1（5），最终签名与分发描述文件都含 `group.com.wang.yudu`；状态和校验记录在 `artifacts/testflight-2.1.1-5-*.json`。
- [原内部组开放测试凭证](release-screenshots/testflight-2.1.1-5.jpg)。未提交／推送 Git，未发布正式版。

## 2026-11-08 整页对照与重新连接回归 2.1.1（7）

最终代码为 2.1.1（7），已保留数据安装到 Fold5 与 iPhone。新增独立“整页对照”，与按范围筛词的“学习辅助”分开，复用现有文字服务、本机缓存与 App Group；失败保留原文，重试只请求缺失段落。修复快速更改语言时旧响应污染新方向缓存、Fold5 窄屏启动空白、少量中文浏览器提示干扰主语言，以及停止 iOS 画中画后面板再次打开。保留当前 Flutter 导航、字体和角色色。

35 项 Flutter 测试、Android 原生回归通过；最终（7）在 iPhone 15 Pro Max / iOS 27.2 的实时变化／收藏和 Safari 分享／完整翻译／重新打开两项界面测试均通过。截图、直接修改文件与边界见 [整页对照验证](page-translation-verification.md)。Android OCR 跨行段落和工具栏过滤仍待优化，账号云同步尚未开通。

（7）于 19:17 上传苹果成功，19:48 仍在处理，尚不能宣称 TestFlight（7）可下载。原内部组 2 人当前可下载（6），包含本轮完整对照模式，说明已保存；手机已安装（7），不必退回（6）。[（6）组内凭证](release-screenshots/testflight-2.1.1-6.jpg)。正式 App Store 仍为 1.2.9，未提交正式审核或推送源码。最终归档、IPA、签名与源码校验记录见 `artifacts/testflight-2.1.1-7-*.json`。

## 2026-11-08 自动翻译浮窗与菜单分类 Beta 2.1.1（8）

（8）已完成苹果处理，原“王业翔内部测试”组 2 人可在 TestFlight 下载，测试说明已保存。包含授权后自动开启的翻译画中画、独立的实时活动扩展及首次“允许／始终允许”说明；Android 菜单分类为本页结果、暂停／继续、阅读设置和更多，每层可返回。安卓（8）已保留数据安装，后续外观更新由界面窗口继续。

新自动浮窗／实时活动暂停、继续、停止和捕获释放的 iPhone 真机流程已通过；系统分享与重开恢复也通过。重复回归受到个人手机通知横幅遮挡时未算通过，具体补验与截图见 [阅读浮窗与菜单分类验证](reading-controls-verification.md)。35 项 Flutter 测试及 Android 原生回归通过。签名校验覆盖主 App、原分享扩展、新实时活动扩展，两个原包的 App Group 保留。没有提交正式 App Store 审核、Git 提交或推送。

[（8）原测试组开放凭证](release-screenshots/testflight-2.1.1-8-ready.jpg)。归档为 `build/ios/archive/Runner-2.1.1-8.xcarchive`；已上传包和签名／源码校验记录在 `artifacts/*2.1.1-8*`。iOS 仍通过系统画中画和实时活动展示，不能把任意可点击词卡覆盖到别的 App 原词；读屏时系统可能优先显示共享标识，操作可从下拉通知中心进入。

（8）最终补验已完成：新自动浮窗／实时活动操作与自动换页／收藏返回两项真实 iPhone 测试通过（2 项、0 失败），Safari 分享／重开恢复另项通过。临时样例服务与测试捕获已停止，详细结果以 `docs/reading-controls-verification.md` 的最终验收段落为准。

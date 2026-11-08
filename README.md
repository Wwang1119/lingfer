# 语渡 Lingfer

语渡 Lingfer 是一个开发中的 AI 阅读与语言学习应用，使用 Flutter 构建，当前重点面向 iOS / macOS。它把本地多格式阅读、拍照识字、翻译与生词学习放在同一套阅读流程中。

仓库名与 Dart 包名统一为 `lingfer`；应用中文名称为「语渡」。同账号下的 [lingfer-nemotron](https://github.com/Wwang1119/lingfer-nemotron) 目前尚无功能实现或集成；应用中的 AI 代理仍使用 DeepSeek。

## 开发入口

| 要做的事 | 文档 |
| --- | --- |
| 首次运行与日常开发 | 本页及[开发说明](docs/DEVELOPMENT.md) |
| 查看已知问题和下一步 | [项目状态与待办](docs/PROJECT_STATUS.md) |
| 配置翻译代理 | [CloudBase 代理说明](cloudbase/deepseek_proxy/README.md) |
| 修改依赖、版本或资源 | [pubspec.yaml](pubspec.yaml) |
| 查阅隐私政策 | [privacy_policy.html](privacy_policy.html)，下载后可用浏览器打开 |
| 打包与上传 iOS 版本 | [开发说明中的发布流程](docs/DEVELOPMENT.md#ios-发布) |

## 已有功能

- 导入本地 TXT / EPUB / PDF / DOCX，加入书架。
- 从文件、相册或相机添加内容；iOS 使用 Apple Vision，Android 使用 ML Kit 进行 OCR。
- 文本阅读与 PDF 原样渲染，支持选词、段落翻译和核心生词提取。
- 词汇难度、中英学习模式、主题、字号、书签与高亮。
- 保存阅读进度、本地缓存；删除书籍时清理相关数据。
- 书架与探索页入口。

这些功能已包含在代码中，具体平台可用性需在对应设备验证。Android 与其他平台的发布细节仍需核对；存在平台目录不代表已完整适配。探索页的部分示例资源尚未补齐，见[已知问题](docs/PROJECT_STATUS.md)。

## 环境要求

- Flutter SDK，内含 Dart 3.11.1 或更高的兼容 3.x 版本，约束见 `pubspec.yaml`；仓库未单独固定 Flutter 版本。
- iOS/macOS：macOS、Xcode、CocoaPods，以及目标模拟器或真机。
- Android：Android SDK 和模拟器或真机。

## 快速开始

```bash
git clone https://github.com/Wwang1119/lingfer.git
cd lingfer
flutter doctor
flutter pub get
flutter devices
```

先运行本地阅读功能，无需 AI 凭证：

```bash
flutter run -d macos
```

iOS 使用 `flutter devices` 列出的设备 ID：`flutter run -d <设备ID>`。首次构建如遇 Pods 问题，在 `ios/` 或 `macos/` 执行 `pod install` 后重试。

启用 AI 时，在编译或启动时传入代理地址和共享访问口令：

```bash
flutter run -d macos \
  --dart-define=DEEPSEEK_PROXY_URL=https://your-proxy.example.com \
  --dart-define=APP_SECRET=your-development-secret
```

这两个值由 `String.fromEnvironment` 在编译期读取，改完需要重新启动构建，不能只依赖热重载。`DEEPSEEK_API_KEY` 只配置在云函数服务端；`APP_SECRET` 是随客户端打包的共享口令，不是用户登录认证。

## 日常检查

在仓库根目录执行：

```bash
flutter analyze
flutter test
```

当前只有一个基础界面测试，尚未覆盖文件导入、OCR、翻译、PDF 与缓存清理完整流程；当前没有 GitHub Actions 自动检查。每次修改后按[开发说明](docs/DEVELOPMENT.md)中的清单在目标设备验证，并记录结果。

## 目录结构

```text
lib/app/                     应用状态与应用壳
lib/models/                  书籍、主题、词汇与翻译模式
lib/screens/                 书架、探索、阅读、扫描等页面
lib/services/                导入、存储、翻译与缓存清理
lib/widgets/                 复用界面组件
lib/catalog/                 探索页书目
assets/                      预置内容、封面和品牌素材
cloudbase/deepseek_proxy/    DeepSeek HTTP 代理云函数
test/                        Flutter 测试
tool/                        iOS 导出与上传脚本
docs/                        开发说明、项目状态和待办
```

## 维护方式

新增或修复功能时，同步记录运行平台、验证步骤与剩余问题；影响配置或使用方式的改动应更新相应文档。书籍与图片要核对资源声明和引用路径，第三方内容保留来源与使用条件。

仓库尚未选择开源许可证，第三方依赖与素材沿用各自许可。

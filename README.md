# 语渡 Lingfer

`语渡（Lingfer）` 是一个基于 Flutter 开发的多格式 AI 阅读应用，当前重点面向 `iOS / macOS`，同时保留 Android 与桌面端工程骨架。它把本地阅读、PDF 原样阅读、OCR 扫描、AI 翻译、生词提取和苹果风阅读交互整合到了一套体验里。

## 当前功能

- 支持导入本地 `TXT / EPUB / PDF / DOCX` 文件并加入书架。
- 支持从 `文件 / 照片 / 相机` 三个入口添加内容。
- 支持图片 OCR 与拍照扫描，识别后的文本可直接长按学习。
- 支持 `TXT / EPUB / DOCX` 文本阅读，以及 `PDF` 原样渲染阅读。
- 支持长按选词、整段翻译、核心生词提取，并通过 Apple Glass 风格浮层展示。
- 支持多档词汇难度切换，例如四级、六级、考研、雅思、托福等。
- 支持中英学习模式切换、主题切换、字号调节、书签与高亮标记。
- 支持阅读进度记忆、本地缓存，以及删除书籍时同步清理缓存。
- 支持内置探索页和本地书架双入口。

## 技术栈

- Flutter 3 / Dart 3
- `epubx`：EPUB 解析
- `syncfusion_flutter_pdfviewer`：PDF 阅读
- `docx_to_text`：DOCX 文本提取
- `google_mlkit_text_recognition`：Android OCR
- Apple Vision：iOS OCR
- `shared_preferences`：进度、书签、缓存状态持久化
- `path_provider`：导入文件与缓存目录管理
- `http`：AI 代理请求

## 运行前准备

1. 安装 Flutter SDK，并确保 `flutter doctor` 基本通过。
2. 如需启用 AI 功能，请准备代理服务地址与应用密钥。
3. iOS/macOS 首次运行前，建议执行一次 CocoaPods 安装。

## 本地运行

### 安装依赖

```bash
flutter pub get
```

### 安装 iOS Pods

```bash
cd ios
pod install
cd ..
```

### 运行 iOS 模拟器

```bash
open -a Simulator
flutter run -d ios \
  --dart-define=DEEPSEEK_PROXY_URL=https://你的代理地址 \
  --dart-define=APP_SECRET=你的应用暗号
```

### 运行 macOS 桌面版

```bash
flutter run -d macos \
  --dart-define=DEEPSEEK_PROXY_URL=https://你的代理地址 \
  --dart-define=APP_SECRET=你的应用暗号
```

## 使用方法

### 添加内容

- 在书架页点击右上角 `+` 按钮。
- 可选择：
  - `文件`：导入本地 TXT / EPUB / PDF / DOCX
  - `照片`：从相册选择图片进行 OCR
  - `相机`：拍照后进行 OCR

### 阅读与学习

- 点击书架中的书籍卡片进入阅读页。
- 长按正文或 PDF 文本，可触发翻译 / 生词提取面板。
- 阅读页可切换词汇难度、语言模式、主题、字号与排版方式。
- 可添加书签与高亮，方便后续复习与回看。

### 删除书籍

- 在书架中长按书籍卡片。
- 点击“删除本书”后，会同步清理书架记录、阅读进度与翻译缓存。

## 资源目录约定

```text
assets/
  books/       预置书籍
  covers/      封面图
  branding/    图标、启动图等品牌素材
```

## AI 配置说明

项目当前不在客户端硬编码模型密钥，运行时通过 `--dart-define` 注入：

- `DEEPSEEK_PROXY_URL`
- `APP_SECRET`

如果未传入，应用仍可正常打开本地内容，但 AI 翻译相关能力不会完整生效。

## 目录结构

```text
lib/
  app/         全局状态与应用壳
  models/      数据模型
  screens/     页面层（书架、探索、阅读、扫描）
  services/    导入、缓存、AI、清理等服务
  widgets/     复用组件
```

## 说明

- 当前优先优化方向是 `iOS / macOS` 的苹果风阅读体验。
- Android 工程可运行，但交互与发布细节仍在持续完善。
- 若准备上架，请同步检查隐私政策、权限文案、签名、图标与启动图配置。

# 语渡 Lingfer 开发说明

## 本地准备

在根目录运行 `flutter doctor`、`flutter pub get` 与 `flutter devices`，先解决目标平台环境问题。Dart 约束见 [pubspec.yaml](../pubspec.yaml)，依赖锁定见 [pubspec.lock](../pubspec.lock)。目前没有项目级 Flutter 版本固定文件，验证后应记录实际 SDK 和 Xcode 版本。

iOS/macOS 原生依赖有变更时，进入对应目录执行 `pod install`。优先用文件导入验证本地阅读，再单独接通 AI。

## 配置 AI

客户端有两个编译期变量：

| 变量 | 用途 |
| --- | --- |
| `DEEPSEEK_PROXY_URL` | CloudBase HTTP 云函数的完整地址 |
| `APP_SECRET` | 发送给代理的 `X-App-Secret`，需与服务端一致 |

在本地终端设置变量，再运行：

```bash
flutter run -d macos \
  --dart-define=DEEPSEEK_PROXY_URL="$DEEPSEEK_PROXY_URL" \
  --dart-define=APP_SECRET="$APP_SECRET"
```

仓库未实现自动加载 `.env`；只新建该文件不会启用配置。修改编译期值后重新运行。不要把真实配置写入提交或日志。代理部署与服务端变量见[云函数说明](../cloudbase/deepseek_proxy/README.md)。

## 找代码

- 应用入口：`lib/main.dart`。
- 全局状态与应用壳：`lib/app/`。
- 文件导入和文本解析：`lib/services/book_text_service.dart`、`imported_file_store.dart`。
- 翻译调用：`lib/services/ai_translation_service.dart`；扫描页也包含 AI 配置读取。
- 正文阅读：`lib/screens/reading/reading_screen.dart`；PDF 页面在同目录。
- 扫描流程：`lib/screens/scan/scan_reader_page.dart`。
- 本地清理：`lib/services/book_storage_cleaner.dart`。
- 探索页数据：`lib/catalog/catalog_data.dart`。

阅读页与扫描页文件较大；修改时优先围绕一个行为，避免同时改变解析、存储和界面结构。

## 资源管理

`assets/books/` 放预置内容，`assets/covers/` 放封面，`assets/branding/` 放图标与启动图。新增资源时同时检查：

1. 文件确实在仓库中，路径和大小写一致。
2. `pubspec.yaml` 已声明相应文件或目录。
3. 探索页书目、封面路径和实际资源一致。
4. 书籍及图片来源与使用条件明确。

当前探索页部分引用与实际文件不匹配，不能将所有书目视为可正常打开，详见[项目状态](PROJECT_STATUS.md)。

## 提交前验证

```bash
flutter analyze
flutter test
git diff --check
```

按改动范围在目标设备检查以下流程，记录通过、失败或未运行：

- TXT / EPUB / PDF / DOCX 各导入一份，打开并恢复阅读进度。
- 相册和相机入口、权限拒绝，以及 OCR 识别。
- 选词、整段翻译、生词难度与中英模式。
- 缺少 AI 配置、网络断开和代理拒绝时的界面反馈。
- 书签、高亮、重启恢复，以及删除书籍后的缓存清理。

现有测试只是基础界面检查；自动检查通过不代表上述设备流程已验证。

## iOS 发布

先检查版本与构建号、签名、权限说明、隐私政策及实际 AI 配置。当前脚本入口：

- `sh tool/export_ipa.sh`：配置并归档、导出 IPA。
- `sh tool/upload_ipa.sh <IPA路径>`：上传已有 IPA。
- `sh tool/build_and_upload_ipa.sh`：连续导出并上传。

导出脚本使用 `DEEPSEEK_PROXY_URL`、`APP_SECRET`；上传脚本读取 `APP_STORE_CONNECT_KEY_ID`、`APP_STORE_CONNECT_ISSUER_ID`、`APP_STORE_CONNECT_P8_PATH`。

脚本仍带现有部署地址、团队 ID、Key ID、Issuer ID 和本机私钥路径的默认配置，导出脚本还会生成固定团队的导出选项。运行前逐项核对，避免误用旧配置；这是待整理事项。私钥只放本机，不上传仓库。文档整理不会执行这些发布脚本。

## 名称与远端

仓库地址为 `https://github.com/Wwang1119/lingfer.git`，应用名为「语渡」，英文品牌为 Lingfer，Dart 包名为 `lingfer`。已有工作副本可在确认当前目录后更新远端：

```bash
git remote set-url origin https://github.com/Wwang1119/lingfer.git
git remote -v
```

改仓库名不需要改动现有应用的 Bundle Identifier、数据目录或签名身份。

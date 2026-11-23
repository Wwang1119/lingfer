# 语渡 PDF 原版连读原型 · 阶段 A 审查材料

状态：只读调查与实现计划。本文件是给外部模型交叉审查的脱敏材料。阶段 A 没有修改业务代码，没有跑 Flutter 测试，没有设备结果，没有调用 DeepSeek，没有评论或合并 PR #1。

核对时间：2026-11-23。远端以当次 `git fetch` 与 GitHub pulls API 为准，不沿用任务里的旧假设。

## 0. 给审查者的问题

请分别审查，不要把下面任何一项当成已经实现或已经在设备上证明：

1. 原型基线选 `main`（Syncfusion 锁定 33.1.45），不选未合并的屏幕浮层线（锁定 33.2.13）。33.2.13 的选区公开 API 经抽查没有新增“按逻辑选区恢复原生选区”的方法。这个选择是否仍正确？
2. 回位成功的可检验定义是：文档加载后读回的 `zoomLevel` 与 `scrollOffset` 落在容差内，并且用页坐标重放的内存标注与短卡指向同一逻辑选区。原生拖选手柄不作为成功条件。是否同意？
3. `selectedText` 非空但 `getSelectedTextLines()` 为空、跨页、或行文本拼不回回调文本时，失败关闭，不请求模型。是否过严或仍不够？
4. 同意门闩做在这条 PDF 分支上，不读取未合并分支的 `companion_ai_consent_*` 键，避免把另一条线的允许当成这条线的允许。是否同意？
5. 短卡替换 PDF 页上的现有大面板；正文阅读页和扫描页不动。iOS 会因此改变 PDF 选句界面。这个共享改动是否可接受？

## 1. 基线

仓库：`Wwang1119/lingfer`。本地工作区在核对时是干净的 `main`，与 `origin/main` 一致。`git ls-remote --heads origin` 只有三条分支。

| 引用 | 全 SHA | 提交说明 | 时间 |
| --- | --- | --- | --- |
| `origin/main` | `3363596398d9c1fd89c8f6799f5af25b7cdf31ce` | docs: organize Lingfer development and proxy documentation | 2026-11-08 23:53:09 +0800 |
| PR #1 base `origin/feat/screen-reading-redesign` | `ca271a089845fe5ea849ebdbc6b6f06104692409` | Improve Lingfer screen reading on Android and iOS and add verification materials | 2026-11-20 00:02:47 +0800 |
| PR #1 head `origin/cursor/fold-overlay-reading-c116` | `54ffd35e205e3e8fd7ad18e1310af13333487f1d` | Mark the open paragraph with a paper wash, not a box over the type. | 2026-11-20 04:43:07 +0000 |

PR #1（https://github.com/Wwang1119/lingfer/pull/1）在 API 返回时为 `open`，`merged` 为 false，`draft` 为 false。head SHA 仍是任务里最后已知的 `54ffd35e205e3e8fd7ad18e1310af13333487f1d`，没有前移。base 是 `feat/screen-reading-redesign`，不是 `main`。API 当时给出 `mergeable: true`、`mergeable_state: clean`、3 个提交、11 个文件、+1315/−284。mergeable 会变，不能当成以后仍可干净合并。

共同祖先：`a04b2e7f20cf6a01100e24b776b18398d83de812`（提交说明 `1.2.9`）。

- `main` 比 redesign 多 1 个提交：`3363596398d9c1fd89c8f6799f5af25b7cdf31ce`。
- redesign 比 `main` 多 2 个提交：`f56464d`、`ca271a0`。
- PR head 比 redesign 多 3 个提交：`2d955dc`、`e1ac674`、`54ffd35`。PR 正文写明要接受的是 head `54ffd35`，不要把 `2d955dc` 和 `e1ac674` 单独当成应接受的提交。阶段 A 不重写这条历史。

版本与 PDF 依赖：

| 线 | pubspec 版本 | `syncfusion_flutter_pdfviewer` 约束 | lock 版本 |
| --- | --- | --- | --- |
| `main` | `1.2.9+1` | `^33.1.44` | **33.1.45** |
| redesign 与 PR #1 head | redesign `2.1.1+15`，PR head `2.1.2+16` | `^33.1.44` | **33.2.13** |

`lib/screens/reading/pdf_reader_page.dart` 的 blob：

- `main`：`c90bb88d20581d945b6643a43e83ac6a5a3b9c7d`
- redesign 与 PR head：`0d98a245c19077e0b44dea8840c40a9d2e44f04f`

两边的 PDF 阅读器行为差异只有导航标题：redesign 改用 `book.displayTitle`。选区、缩放、回位都没有在那次差异里实现。redesign 另有一个 `lib/features/companion/companion_shell.dart` 也会打开 `PdfReaderPage`。那是屏幕伴读线的壳，不是本原型的基线。

### 1.1 为什么原型从 `main` 起

PDF 原版页、导入和 Syncfusion 阅读器在 `main` 上已经存在。PR #1 是 Android 屏幕浮层：纸色行洗、OCR 遮罩、折叠屏上的段落命中。产品范围写明此轮不做跨 App 浮层、扫描 OCR、全书翻译、支付，也不重写整个阅读器。把原型长在 PR #1 或 redesign 上，会带进 2.1.x 未合并的浮层、同意门闩和资源替换，并冒着覆盖那条线的风险。

33.1.45 与 33.2.13 的选区回调字段、`getSelectedTextLines()` 的当前页查找、`jumpTo` / `jumpToPage` 清除选区、以及 `initialPageNumber` 优先于 `initialScrollOffset`，在两份 pub 源码里都在。升级 lock 不能解决回位。首轮保持 `main` 的 33.1.45，不顺手升到 33.2.13。

### 1.2 现有未完成工作怎么保全

- 不 checkout、不 rebase、不提交、不 force-push `feat/screen-reading-redesign` 或 `cursor/fold-overlay-reading-c116`。
- 不合并 PR #1，不在 PR #1 上评论。
- 不把 redesign 的 `displayTitle`、字体、公版书替换或 `AiConsentStore` 悄悄带回 `main`。
- 阶段 A 的分支从 `3363596398d9c1fd89c8f6799f5af25b7cdf31ce` 拉出，只增加本审查文件。后续实现继续留在这条分支。
- 核对时工作区干净，没有未提交的用户改动可覆盖。若后续发现远端 head 变化，先停，再读新的 SHA。

PR #1 相对其 base 的文件（全部保留在原分支，本原型不改）：

- `android/app/src/androidTest/kotlin/com/wang/lingfer/screen/NativePanelUiInstrumentation.kt`
- `android/app/src/androidTest/kotlin/com/wang/lingfer/screen/ParagraphAnnotationsTest.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/GlassAnnotations.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/NativeOcrEngine.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/NativeReadingPanel.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/OcrPage.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/OverlayReading.kt`（新增）
- `android/app/src/main/kotlin/com/wang/lingfer/screen/ParagraphAnnotations.kt`
- `android/app/src/main/kotlin/com/wang/lingfer/screen/ScreenReaderService.kt`
- `pubspec.yaml`
- `tool/overlay_reading_render.kt`（新增）

redesign 相对 `main` 还有整套屏幕阅读、同意存储、资源增删。`assets/books/sample_paper.pdf` 在 redesign 上被删除，在 `main` 上仍在。那些改动留在原分支。

## 2. 产品切片与明确不做

首轮最小垂直切片，一条路径：

1. 用户导入自己合法取得、带文字层的外文 PDF。页面保持原版，不重排。
2. 捏合缩放和拖选使用现有 `SfPdfViewer`。
3. 选区必须能定位到页和页内行框。然后出现一张短卡：逐字原文、短译、精简解释。推断单独成块。卡片写明这只覆盖所选文字，不是整页语境。
4. 用户允许联网之前，不发代理请求。
5. 每次请求绑定文件内容身份、页、逻辑选区。过期响应不能写到后来的选区上。
6. 离开再打开：恢复 zoom、scrollX、scrollY，以及同一逻辑选区的短卡和页内标记。只跳到页码、让用户自己找句子，不算通过。

此轮不做：跨 App 浮层、扫描 OCR、全书翻译、支付、重写 `ReadingScreen`、用抽取文本重排来代替原版失败。Fold5 的折叠窄屏、展开和旋转是适配检查，不是已证明的正式市场平台优先级。iOS 现有正文阅读和扫描流程不能被这个切片改坏。

现有 `AppleGlassPanel` 是上下停靠的大面板（约 38% 安全高度，翻译区最高约 34% 屏高或 260）。它不是这张短卡。短卡用内容高度，留出原版页面；不能做成强制上下分屏，也不能用一块遮住句子的色块冒充定位。

## 3. 现有架构（`main`）

入口与分流：

- `lib/main.dart`：`LingferRoot`。
- `lib/app/lens_app.dart` 约 155–160 行：本地路径以 `.pdf` 结尾时 `PdfReaderPage`。
- `lib/screens/shelf/shelf_tab.dart` 约 596–601 行：书架同样把 PDF 送到 `PdfReaderPage`。
- `lib/screens/catalog/catalog_tab.dart` 约 205–210 行：资源书以 `.pdf` 结尾时同样分流。
- 其他文本走 `lib/screens/reading/reading_screen.dart`。图片和扫描 JSON 走 `lib/screens/scan/scan_reader_page.dart`。这两处不在首轮编辑集合里。

PDF 页今天只做了“选到非空字符串就打开大面板并立刻翻译”。全文在 `lib/screens/reading/pdf_reader_page.dart`（186 行）。没有 `GlobalKey<SfPdfViewerState>`，没有 `onDocumentLoaded`，没有 `initialZoomLevel` / `initialScrollOffset`，没有进度写入。

选区回调只读取 `selectedText` 和 `globalSelectedRegion`：

```48:67:lib/screens/reading/pdf_reader_page.dart
  void _onTextSelectionChanged(PdfTextSelectionChangedDetails details) {
    final raw = details.selectedText;
    if (raw == null) {
      _selectionDebounce?.cancel();
      _pendingSelectedText = null;
      _pendingSelectedRegion = null;
      return;
    }
    // ...
    _pendingSelectedText = text;
    _pendingSelectedRegion = details.globalSelectedRegion;
```

阅读器构造没有回位参数：

```116:133:lib/screens/reading/pdf_reader_page.dart
    final viewer = switch (widget.book.source) {
      BookSource.asset => SfPdfViewer.asset(
          widget.book.locator,
          controller: _pdfController,
          enableTextSelection: true,
          onTextSelectionChanged: _onTextSelectionChanged,
          canShowTextSelectionMenu: false,
        ),
      BookSource.localFile => SfPdfViewer.file(
          File(widget.book.locator),
          controller: _pdfController,
          enableTextSelection: true,
          onTextSelectionChanged: _onTextSelectionChanged,
          canShowTextSelectionMenu: false,
        ),
```

`globalSelectedRegion` 用来决定面板停在上方还是下方（同文件约 85–96 行）。那是屏幕坐标，滚动、缩放、旋转、折叠之后都会失效，不能当逻辑选区存储。

代理地址和口令来自编译期环境，默认空字符串，仓库业务代码里没有写死密钥：

```12:14:lib/screens/reading/pdf_reader_page.dart
const String _deepSeekProxyUrl =
    String.fromEnvironment('DEEPSEEK_PROXY_URL', defaultValue: '');
const String _appSecret = String.fromEnvironment('APP_SECRET', defaultValue: '');
```

`reading_screen.dart` 和 `scan_reader_page.dart` 也有同样的两个 `fromEnvironment`。发布脚本里另有默认代理主机。本材料不抄该主机，也不抄任何口令。审查实现时不得把脚本里的默认主机或密钥写进 Dart。

`AppleGlassPanel`（`lib/widgets/apple_glass_sheet.dart`）在 `initState` 里只要有文字就调用 `_runTranslate()`（约 94–96 行）。没有同意判断。翻译请求用递增的 `_translationSerial` 丢掉同一面板里更早的响应（约 132–145 行）。这只防止“同一 State 上后一次选区被前一次覆盖”，没有文件、页、行框身份。词汇缓存键是 `'${text.hashCode}_${level.name}'`（约 84–85 行）。`hashCode` 会碰撞，也不能跨进程当身份。

面板分段是“整段翻译 / 核心生词”（约 282–289 行）。原文预览最多 3 行并省略（约 313–328 行）。没有逐字行、没有单独的推断块、没有“所选并非整页语境”的固定说明。

`AiTranslationService.translatePlainText`（`lib/services/ai_translation_service.dart` 约 232–270 行）把选区原文发给代理。系统提示要求只输出译文，但类顶部的 `_garbleImmunityPrompt`（约 19–22 行）要求模型忽略乱码并“结合上下文脑补”。PDF 路径并没有把页面其余文字发给模型。这个提示把未提供的语境说成了可以脑补的上下文，和“不得声称局部选句覆盖完整语境”冲突。首轮新卡不能复用这句提示。

`extractCoreVocabulary`（约 496 行起）按难度抽词，返回 `CoreVocabItem`（约 765 行：`word`、`phonetic`、`meaning`）。那不是逐字短卡。可以复用 HTTP 客户端和净化函数，不复用现有提示词当短卡协议。

正文进度在 `AppState.progressTopChunk`（`lib/app/app_state.dart` 约 25–28 行），键是 `progress_topChunk_${book.stableKey}`。`ReadingScreen` 另有按分页尺寸变化的 `progress_page_` 整数（`reading_screen.dart` 约 792–797 行）。都不是 PDF 的页、滚动和缩放。`Book.stableKey`（`lib/models/book.dart` 约 79–84 行）是标题加难度，不是文件内容。同名 PDF 会撞键。`BookStorageCleaner`（约 25–45 行）只删这些正文键。新的 PDF 位置键以后要加进清理，否则删书会留孤儿记录。

`ImportedFileStore` 把用户文件拷进应用支持目录。路径会变。逻辑身份要用拷贝后的内容哈希，不能只用路径或标题。

仓库内夹具 `assets/books/sample_paper.pdf` 为 593 字节，一页，MediaBox 612×792，Helvetica，内容流只有 `(Sample Paper) Tj`。它能证明“有一个很小的文字层文件”，不能代表多栏、旋转、连字符或跨行选区。

`test/widget_test.dart` 只检查书架和探索页是否出现。没有 PDF 选区或回位测试。

`main` 上不存在 `AiConsentStore`。未合并 redesign 的 `lib/services/ai_consent_store.dart` 使用偏好键 `companion_ai_consent_version_v1` 与 `companion_ai_consent_allowed_v1`，iOS 还走 `lingfer/share_reader`。Android 浮层读取同一组键。那是另一条产品的屏幕分享同意，披露文字包含 OCR 和自动发送。PDF 原型不要读取或写入那组键，也不要移植浮层服务。

## 4. Syncfusion 33.1.45 实际 API

源码来源：`pubspec.lock` 的托管地址上，包 `syncfusion_flutter_pdfviewer` 33.1.45 的官方压缩包。下面行号属于该包的 `lib/src/...`，不在本仓库里。对照包 33.2.13（redesign / PR #1 的 lock）抽查了同样的符号，行为相同，行号略有偏移。没有把 README 的功能列表当成 API。

官方 README 把平台写成 Android、iOS、Web、Windows、macOS，并声明这是商业包，需要商业许可或社区许可。`main` 的 lock 还拉了 `syncfusion_pdfviewer_linux` 33.1.45。Linux 插件方法是渲染：`initializePdfRenderer`、`loadPdfFromFile`、`getPagesHeight`、`getPagesWidth`、`getPage`、瓦片和关闭。没有文字选择方法。文字层解析在 Dart 的 `PdfTextExtractor`。Linux 能编过不等于 Android 选区顺序正确。

### 4.1 回调没有页码和字符索引

`PdfTextSelectionChangedDetails` 只有两个字段：

```dart
class PdfTextSelectionChangedDetails {
  PdfTextSelectionChangedDetails(String? selectedText, Rect? globalSelectedRegion);
  String? get selectedText;
  Rect? get globalSelectedRegion; // 屏幕坐标
}
```

包内位置：`lib/src/control/pdfviewer_callback_details.dart` 约 110–135 行。没有 `pageNumber`，没有行框，没有字符偏移。非空 `selectedText` 只说明画布拼出了一段字符串。

### 4.2 行信息在 State 上，而且只查当前页

`PdfTextLine`（`lib/src/control/pdftextline.dart`）有 `bounds`、`text`、`pageNumber`。注释写 bounds 相对页面。构造时传入的是字形的 PDF 坐标，不是除过缩放后的控件坐标。

两处创建都用 `viewId + 1`。`viewId` 赋的是页面的 `pageIndex`，而 `extractTextLines(startPageIndex: pageIndex)` 使用 0 基索引。因此这里的 `pageNumber` 是 1 基，和 `PdfViewerController.pageNumber` 一致：

```dart
PdfTextLine(
  Rect.fromLTRB(startPoint.left, startPoint.top, endPoint.right, endPoint.bottom),
  glyphText,
  _textSelectionHelper.viewId! + 1,
);
```

包内位置：`lib/src/control/pdfviewer_canvas.dart` 约 2530–2540 行，以及单击选词约 3014–3019 行。

公开读取却只看控制器当前页的那一块画布：

```dart
List<PdfTextLine> getSelectedTextLines() {
  final List<PdfTextLine>? selectedTextLines =
      _pdfPagesKey[_pdfViewerController.pageNumber]
          ?.currentState
          ?.canvasRenderBox
          ?.getSelectedTextLines();
  return selectedTextLines ?? <PdfTextLine>[];
}
```

包内位置：`lib/src/pdfviewer.dart` 约 4595–4601 行。当前页由滚动位置推算，不一定是用户刚选中文字的那一页。连续滚动时，可见邻页上的选区可以让回调拿到非空 `selectedText`，同时 `getSelectedTextLines()` 返回空列表。空列表必须当成“没有定位”，不能当成“文字已经够用”。

多行拼接在提取顺序上插入换行，不另做阅读顺序校正：

```dart
String _copiedTextLines(List<PdfTextLine> textLines) {
  String copiedText = '';
  for (int lineIndex = 0; lineIndex < textLines.length; lineIndex++) {
    copiedText = lineIndex == 0
        ? textLines[lineIndex].text
        : '$copiedText\n${textLines[lineIndex].text}';
  }
  return copiedText;
}
```

包内位置：同画布文件约 2703–2712 行。词间空格取决于相邻字形间隙是否大于 1.0（约 2518–2525 行）。这不是“视觉阅读顺序已被证明”的证据。多栏、旋转、连字符都没有在本轮用真实 PDF 验证。

同一文件约 3933–3935 行还有 `getSelectedTextLines().first.pageNumber + 1 == controller.pageNumber`。这和构造时的 `viewId + 1` 不一致。不要抄这个比较。我们的页码以构造点为准：1 基。

画布的文字行来自单页 `extractTextLines(startPageIndex: pageIndex)`（约 1386–1391 行）。选区模型是一页。不要把跨页拖选规划进首轮；SDK 没有公开的跨页选区对象。

### 4.3 回位 API 与它会清掉的东西

`PdfViewerController`（`lib/src/pdfviewer.dart` 约 6848、6897、7219、7275 行）：

- `Offset get scrollOffset`
- `double get zoomLevel` / `set zoomLevel`。组件 `maxZoomLevel` 默认 3，setter 的处理函数会把超出范围的值夹回 `[minScale, maxZoomLevel]`（约 5811–5816 行）。
- `void jumpTo({double xOffset = 0.0, double yOffset = 0.0})`
- `void jumpToPage(int pageNumber)`。页码非法时导航不发生（约 5909–5914 行）。
- `void addAnnotation(Annotation annotation)`，随后调用 `clearSelection()`（约 7665–7669 行）。
- `void removeAnnotation(Annotation annotation)`
- `HighlightAnnotation({required List<PdfTextLine> textBoundsCollection})` 用页坐标行框。公开的 `PdfTextLine` 构造函数可以在没有活动选区时重建。

`jumpTo` 和 `pageNavigate`（含 `jumpToPage`）的处理函数第一件事都是 `_clearSelection()`（约 5880–5881 行、5905–5907 行）。用它们恢复视口会清掉原生选区。原生手柄不能作为回位成功条件。

组件参数：

- `initialZoomLevel`，默认 1。加载时写入控制器（约 2324 行）。
- `initialScrollOffset`，默认 `Offset.zero`。
- `initialPageNumber`，默认 1。文档写明不要同时使用 `initialScrollOffset` 和 `initialPageNumber`，后者优先（约 561 行）。加载函数先 `jumpTo`，若 `initialPageNumber > 1` 再 `jumpToPage`（约 3484–3497 行）。同时设置时，页码跳转会盖过精确偏移。
- 若 `widget.key` 是 `PageStorageKey`，`_setInitialScrollOffset` 改从 PageStorage 读偏移和缩放，忽略 `initialScrollOffset`（约 1476–1489 行）。回位时不要用 `PageStorageKey`。`GlobalKey<SfPdfViewerState>` 不是 `PageStorageKey`，可以用来读行。

`scrollOffset` 来自变换矩阵的 `toScene(Offset.zero)`（约 6651–6666 行），是内容坐标，随缩放变化。桌面与移动的缩放回写路径不同：`PdfScrollable.scaleTo` 在桌面调用 `jumpTo(previousOffset)`，其他平台调用 `forcePixels`（`lib/src/control/pdf_scrollable.dart` 约 493–517 行）。Linux 桌面测试走的是桌面分支，不能代替 Fold5 的移动分支。

`initState` 在 `zoomLevel > 1` 时用 `Future.delayed(Duration.zero)` 再 `scaleTo`（约 175–178 行）。加载函数也会 `jumpTo`。这两步的先后在设备上没有测过。调用 API 不等于读回成功。

`addAnnotation` 把标注放进阅读器内存列表并跟踪撤销（约 6028–6061 行）。这条路径本身不调用 `saveDocument`。首轮禁止调用 `saveDocument`，禁止把标注写回用户文件。`selectAnnotation` 会 `jumpToPage(annotation.pageNumber)`（约 6074 行），那是页级跳转，不能用来恢复精确位置。

没有公开方法按页和字符范围重新建立原生选区，也没有公开的 page-to-global 变换。页内标记应使用 `HighlightAnnotation` 的页坐标。若标注没有画在字形上，只能记为失败，不能改用重排文本。

`searchText` 会先 `clearSelection()`（约 5937–5938 行），并且按全文匹配导航。重复句子会命中多处。不能用搜索代替逻辑选区。

## 5. 建议的模块边界

首轮实现时新增小模块，PDF 页只做装配。不改 `ReadingScreen` 和 `ScanReaderPage`。

| 模块 | 职责 | 依赖 |
| --- | --- | --- |
| `PdfFileId` | 对导入副本做内容哈希。不使用标题、难度或路径单独当身份 | 纯 Dart |
| `PdfLineSpan` | 1 基页码、页坐标 `Rect`、该行原文。拒绝页码小于 1，拒绝一份选区跨页 | 纯 Dart |
| `PdfSelectionAnchor` | 文件身份、行列表、由行按捕获顺序拼接的文本、捕获时的 zoom 与 scroll | 纯 Dart |
| `PdfViewport` | `zoom`、`scrollX`、`scrollY`。不包含页码字段作为成功条件 | 纯 Dart |
| `PdfRestorePlan` | 只产生 `initialZoomLevel` + `initialScrollOffset`，`initialPageNumber` 保持 1。拒绝“只有页码”的计划 | 纯 Dart |
| `PdfLocatedSelection` | 把回调文本和 `getSelectedTextLines()` 收成锚点，或明确的定位失败 | 纯 Dart，输入是数据不是控件 |
| `PdfCardRequest` | 同意为 false 时不调用传输。请求带锚点 id。响应带同一 id 才可应用 | 纯 Dart 决策；传输用现有 `http` 客户端 |
| `PdfSentenceCard` | 短卡模型：原文行、短译、精简解释、单独的推断列表、固定的范围声明 | UI 使用现有纸色，不新做一套主题 |
| `PdfReaderPage` 装配 | 现有文件内增加 key、加载回调、持久化和短卡。旧的大面板不再在这条路径上自动请求 | Syncfusion 控件 |

短卡文案固定包含一句范围声明，例如：这是所选文字的说明，不是这一页或这一章的完整语境。推断列表与解释分开展示；没有推断时显示空状态，不把解释改写成推断。

模型输出用固定 JSON：`translation`、`explanation`、`inferences`（字符串数组）。解析失败则卡片显示失败，不把原文回显成译文。提示词只接收选区文本，明确禁止补写未给出的前后文，禁止沿用“脑补”那句。

同意：PDF 页第一次需要联网时询问。拒绝后只保留原文行和页内标记，不发 POST。允许记录用这条分支自己的新键，不用 `companion_ai_consent_*`。缺少 `DEEPSEEK_PROXY_URL` 或 `APP_SECRET` 时显示未配置，不发请求。本阶段和实现阶段都不要为了演示去调用付费接口。

异步绑定：锚点 id 是文件哈希、页、各行文本和规范化行框。卡片持有当前 id。响应回来时 id 不一致、页面已销毁、或用户已关闭卡片，就丢弃。同一句话出现在两页是两个锚点。

持久化建议键：`pdf_place_v1_<fileHash>`。值含 viewport、行框、行文本、卡片已展示的结果和结果所绑定的锚点 id。结果可以在身份匹配时直接显示，并标明它是上次这一选区的结果。文件哈希变了就不能贴。删书时在 `BookStorageCleaner.deletePrefs` 增加这一前缀的删除。不要复用 `progress_topChunk_`。

视觉：继续用 PDF 页已有的 `#F6F4EE` 背景。短卡用内容高度和现有纸色卡片。`main` 没有打包中文字体；Android 会落到系统字体。中文是否舒服留给 Fold5 看，不在计划里宣称已经达标。不要从浮层分支搬字体或 46% 宽度规则。

## 6. 可检验的回位契约

给定一份文件哈希为 H 的 PDF，离开时记录：

- `zoom = controller.zoomLevel`
- `scroll = controller.scrollOffset`，分别保存 dx、dy
- 逻辑选区 = 当时 `getSelectedTextLines()` 的 1 基页码、每行 `bounds`、每行 `text`
- 不保存 `globalSelectedRegion`

再次打开同一哈希：

1. `SfPdfViewer` 使用 `initialZoomLevel` 和 `initialScrollOffset`。`initialPageNumber` 保持默认 1。key 使用 `GlobalKey<SfPdfViewerState>`，不用 `PageStorageKey`。
2. `onDocumentLoaded` 之后至少再等一帧，读取 `zoomLevel` 和 `scrollOffset`。
3. 通过条件同时满足：缩放与两个偏移相对保存值的差都在事先写死的容差内；用保存的行重建 `HighlightAnnotation` 并 `addAnnotation`；短卡的原文行与保存的行文本一致。容差在第一次真机读回之前不要假装已经知道，测试里先用构造的假控制器验证比较函数本身。
4. 失败条件：只能回到页码；读回超出容差；行框跨页；标注 API 抛错或首轮设备上看不到标记。失败时短卡说明没有恢复到原选区，并保留页内原版。不允许改成重排阅读器。
5. 不调用 `jumpToPage`、`selectAnnotation`、`searchText`、`saveDocument` 来完成这次恢复。`addAnnotation` 会清原生选区，这是预期，不是成功。

只恢复视口、不恢复逻辑选区，不合格。只恢复短卡文字、页面仍停在第 1 页，也不合格。

## 7. 测试策略

### 7.1 本环境没有跑过的东西

2026-11-23 的这台环境里，`flutter` 和 `dart` 不在 PATH 上。因此没有执行 `flutter analyze`、`flutter test`、Linux 桌面构建或仪器测试。没有截图，没有 Fold5，没有 iOS 设备结果。下面是应当运行的划分，不是运行记录。

### 7.2 有 Flutter SDK 的 Linux 上可以跑的纯逻辑测试

不启动阅读器、不加载 pdfium：

- 非空文本加空行列表 => 定位失败，传输函数不被调用。
- 行文本按捕获顺序拼接后与回调文本规范化不一致 => 定位失败。
- 行列表跨页或页码小于 1 => 拒绝成锚点。
- 相同文本、不同页或不同行框 => 不同锚点 id。
- 响应 id 与当前锚点不同 => 不写入卡片。
- 同意为 false，或代理配置为空 => 传输函数不被调用。
- 恢复计划若只有页码、或同时设置了非默认 `initialPageNumber` 和偏移 => 计划构造失败。
- 假读回超出容差 => 契约判定失败。
- 推断字段缺失时不能从解释文本里推断出一条推断。

这些测试锁定的是我们自己的决策，锁不住 Syncfusion 画布是否把多栏排对。

`node --check cloudbase/deepseek_proxy/index.js` 只检查代理语法，与选区无关，本轮也没有跑。实现时不要为了测试去打真实模型。

### 7.3 Linux 上即使将来跑通也不能当成 Android 证据

- `SfPdfViewer` 的 Linux 路径使用 pdfium 渲染，选区文本来自 Dart 提取器。官方 README 未把 Linux 列为支持平台。
- 缩放回写在 `kIsDesktop` 上走另一条路径。Fold5 走移动路径。
- 夹具 PDF 只有 “Sample Paper” 一行。即使用它把控件泵起来，也不能证明拖选顺序。

可以后补的 Linux 冒烟：用夹具打开控件并收到 `onDocumentLoaded`。失败只说明这台 Linux 的 pdfium 或插件不可用，不能解释成 Android 选区坏了，也不能解释成选区是好的。

### 7.4 必须真机，且本轮没有做

Android / Fold5，使用测试者自己的带文字层外文 PDF，至少覆盖：

- 折叠后的窄屏、展开后的宽屏、竖屏和横屏。短卡不遮住所选行，原版页面仍是主体。
- 捏合缩放后拖选，松手后面板文字与屏幕上被选中的字形一致。交换多栏左右两栏各选一句，确认卡片顺序没有把另一栏拼进来。做不到就保持失败关闭，不要改成重排。
- 记下离开时的页、zoom、scroll。重新进入后读回这三个数，并看到同一行的标记。只看到正确页码而句子不在视野里，记失败。
- 旋转或折叠后再读回。视口尺寸变了，允许标记仍在页坐标上，但必须能看见该句或明确显示未恢复。不要把“页码对了”记通过。
- 快速连选两句，慢响应不能出现在后一句上。拒绝联网后抓包或日志里没有 POST。
- 关闭再打开，未允许联网时不自动补发上次未发送的请求。

iOS 回归，防止共享 Dart 改坏已有实现：

- TXT 或 EPUB 仍进 `ReadingScreen`，扫描页仍进 `ScanReaderPage`。
- PDF 仍是原版页，能缩放。短卡替换大面板是这条切片的预期变化，要单独看，不能顺手改正文排版。
- 不新增屏幕录制或跨 App 浮层权限。

没有上述设备记录之前，不能写“Fold5 已适配”或“回位已通过”。

## 8. 真正的阻塞和仅仅还没验证的事

阻塞首轮诚实交付的，是 API 边界，不是一个尚未证实的渲染根因：

1. 没有公开 API 恢复原生拖选手柄。契约必须改成视口读回加页坐标标注加短卡。若产品坚持手柄也回来，33.1.45 和抽查的 33.2.13 都做不到，切片应停在这个决定上。
2. `getSelectedTextLines()` 只查询当前页。定位必须失败关闭。若真机上正常拖选也经常拿不到行，首轮就停，不能用 `selectedText` 顶上，也不能改成重排。
3. `jumpTo`、`jumpToPage`、`addAnnotation` 都会清原生选区。恢复顺序不能依赖选区还在。
4. 页坐标到屏幕坐标没有公开变换。标记依赖 `HighlightAnnotation` 是否按页坐标画对。画不对就停，不自绘一个猜出来的矩形盖住页面。
5. `main` 的 PDF 路径没有同意门闩，而且现有面板会立刻 POST。新路径在同意前不能再走那个调用。这是实现约束，不是未知根因。

还没验证、因此不能写进完成声明的：

- `initialZoomLevel` 与延迟 `scaleTo`、加载时 `jumpTo` 的真实先后。
- 缩放后的 `scrollOffset` 读回误差。
- 旋转页面上高亮矩形是否还压在字形上。构造点没有旋转校正；便签路径另有旋转处理。
- 多栏提取顺序。
- Fold5 窗口尺寸类。`main` 的 Android 工程没有折叠或铰链代码。
- 中文在系统字体下的观感。
- Linux pdfium 能否加载。本环境没有 Flutter，无法开始这段验证。

不要把“当前页查找”提前说成用户已经遇到的线上故障。当前应用根本没调用 `getSelectedTextLines()`。这是源码里的能力边界。

## 9. 审查通过之后的实施清单

仍不要在阶段 A 做这些。审查意见汇入后，在同一分支继续：

1. 只加第 5 节的纯 Dart 类型、PDF 页装配和对应 `flutter test`。不改浮层分支。
2. PDF 页：`GlobalKey<SfPdfViewerState>`；加载后按第 6 节恢复；选区经 `PdfLocatedSelection`；短卡替换该页的 `AppleGlassPanel`。
3. 新提示词与 JSON 解析放在 PDF 卡片专用函数。不要改 `_garbleImmunityPrompt` 的正文阅读调用，除非那次改动有自己的测试。首轮更稳妥的是 PDF 卡片不调用带那句提示的 `translatePlainText`。
4. 同意前不构造 POST。配置缺失走本地说明。
5. `BookStorageCleaner` 删除 `pdf_place_v1_` 记录。
6. 有 Flutter 的环境跑 `flutter analyze` 和 `flutter test`，把命令和结果记进后续说明。本文件不要被改成“已通过”。
7. 真机清单按第 7.4 节记录通过、失败或未跑。未跑就保持未跑。
8. 不调用付费模型，不合并，不发布，不评论 PR #1。

## 10. 脱敏边界

本材料可以交给外部模型。它包含上述必要片段和包 API 签名。它故意不包含：代理主机、`APP_SECRET`、`DEEPSEEK_API_KEY`、发布脚本中的默认地址、未合并同意文案里的联系邮箱和策略链接、用户 PDF 正文。夹具文件的全部可见文字就是 “Sample Paper”。

阶段 A 没有修改 `lib/`、`android/`、`ios/`、`pubspec.yaml` 或 `pubspec.lock`。

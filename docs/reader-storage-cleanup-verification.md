# 本地阅读缓存与旧版空示例清理

2026-11-14。设置底部新增“本地存储”，没有自动清理动作，也没有增加确认弹框。本轮子任务未操作用户设备上的资料；真实设备清理由主任务按用户授权验收。

## 清理范围

`ReaderCacheStorage` 仅使用 `getTemporaryDirectory()/lens_cache`，这是现有书内翻译可重新生成的缓存目录。提供测试用的 `baseDirectory` 时，它表示临时目录根，服务仍只处理其 `lens_cache` 子目录。

- 统计普通缓存文件的字节数和数量；清理后重新统计并显示结果。
- 保留缓存根容器，删除其中普通文件和已空的子目录。
- 根目录或 `lens_cache` 本身是符号链接时不进入。内部链接只解除链接本身，不访问目标；枚举不跟随链接，目录删除不使用递归删除。
- 不枚举或删除 Application Support 导入原件、扫描 OCR、其他临时文件、SharedPreferences、生词和阅读进度。
- 失败显示重试入口，不把无法统计伪装成 0 B；清理过程中避免重复操作。

“移除旧版空示例”仅在书架存在 `BookSource.mock` 时显示，调用主任务提供的 `AppState.archiveEmptyExamples()`。移除后提供 SnackBar“撤销”，使用返回的原始 `Book` 记录调用 `addToShelf`，不重建标题、定位符或稳定标识。导入资料和完整内置书不属于该操作。

## 文件与验证

- `lib/services/reader_cache_storage.dart`：限定目录统计和清理。
- `lib/features/companion/reader_storage_controls.dart`：设置卡片、异步状态、清理及示例撤销。
- `lib/features/companion/companion_shell.dart`：设置底部接入该卡片。
- `test/reader_cache_storage_test.dart`：五项真实文件系统测试。
- `test/app_state_archive_test.dart`：四项归档与原记录撤销测试。

五项文件系统测试全部通过：精确 UTF-8 字节数、保护导入／扫描／偏好／其他临时文件、内部文件／目录／循环／断链隔离、根缓存与根目录链接拒绝进入、缺失／空缓存重复清理。

归档追加的四项测试全部通过：只移出 mock 且完整元数据写入备份；asset／公版书／本地 EPUB／PDF／扫描记录、进度和生词等偏好不变；返回原 `Book` 对象可用 `addToShelf` 完整撤销；与已有备份合并、重复归档不重复，没有 mock 时不写偏好。

既有书内及主页 UI 测试合计 15 项通过。分析无错误；`companion_shell.dart` 导入修复区域的一条 `if` 花括号提示已交主任务处理，没有为清理缓存修改该区域。

日志：`/private/tmp/lingfer-reader-cache-fs-tests-nov14.log`、`/private/tmp/lingfer-reader-storage-and-ui-tests-nov14.log`、`/private/tmp/lingfer-reader-storage-and-ui-analyze-nov14.log`。

追加归档测试日志：`/private/tmp/lingfer-app-state-archive-tests-nov14.log`。

实际设置入口、用户设备缓存大小与撤销效果仍由主任务在最终安装包验收；上述测试没有清理用户设备，也没有提交、推送或发布。

# 11 月 16 日原生准备页与单层返回：模拟器原图

来源：`/private/tmp/lingfer-toolchain/return-glass-nov16.xcresult`，日志同前缀 `.log`。四张图片直接复制自 `xcresulttool export attachments` 导出的原始 PNG；没有裁切、重绘、加标记或替换界面文字。设备为 **iOS Simulator** `Lingfer-Return-Glass-Nov16`（`20638840-1685-4AD5-91EC-647FC0C2D35F`），**不是物理 iPhone**。

两项 UI 用例 **2/2 通过、0 失败**：

| 用例 | 用时 | 实际检查范围 |
| --- | --- | --- |
| `ReadingUITests/testIndependentReadingSetupControls()` | 57.760 秒 | 阅读方式与语言独立、浮窗／灵动岛选择、学习辅助准备页及回到首页。未开启系统读屏。 |
| `ReadingUITests/testReadingPreparationReturnAndOptionalConsent()` | 27.693 秒 | 准备页开启时没有擅自弹出 AI 说明、开始按钮可点、唯一返回可点；用户主动打开联网 AI 说明后可选择仅本机阅读，返回仍可用。未授权系统共享。 |

| 原图 | 导出附件 | 来源用例 |
| --- | --- | --- |
| [单层返回与可选许可](nov16-reading-preparation-single-return.png) | `AF507708-2E7D-4F24-8534-4051ED1E3344.png` | 单层返回／可选许可 |
| [独立阅读方式与语言](store-ios-live-ready-independent-controls.png) | `BEDBFD78-D13C-47CE-A911-982D4216DC49.png` | 独立准备控件 |
| [学习辅助准备页](store-ios-live-ready-learning.png) | `869E4C15-3EEB-4048-B5DA-BD62108A0CC0.png` | 独立准备控件 |
| [返回后的首页](store-ios-current-home.png) | `055A1827-2B34-47B6-BDED-B68C6AE2402F.png` | 独立准备控件 |

四张均为 **1206 × 2622、8-bit RGB**。已逐图目视核对：返回为单个系统玻璃按钮，未见两层玻璃叠加；准备说明不再写授权后自动收起；联网 AI 处于仅本机阅读／尚未开启状态。逐图捕获时间、原附件名、SHA-256 和未修改标记见 [provenance.json](provenance.json)。44pt 物理点击区域没有据本组图片作几何测量。

`ShareViewController.swift` 当前两处 `onAppear` 已去掉自动设置 `aiConsentOpen`，只刷新许可状态；点击“联网 AI”仍可主动进入说明，未许可时默认禁止联网并未改变。这项调整旨在避免系统授权回来又被另一张 sheet 覆盖。最终真机测试构建 `/private/tmp/lingfer-toolchain/release14-return-consent-final-build-nov16.log` 已通过，但手机当前离线，**授权之后是否不再出现覆盖 sheet、首次跨 App PiP、灵动岛及恢复／停止均未据此完成真机回归**。

本组截图只作原生准备页 UI 证据，不作为 PiP、灵动岛或后台系统捕获已经正常的证据。用户授权先推内部 Beta、下次再做真机测试后，**TestFlight 2.1.1（14）已上传并处理完成，原“王业翔内部测试”两人组“正在测试”，可下载**；测试说明已保存并重开核对一致。凭证：[上传成功](../../../artifacts/testflight-2.1.1-14/xcode-uploaded.png)、[内部组可下载](../../../artifacts/testflight-2.1.1-14/available-internal-group.png)、[最终状态](../../../artifacts/testflight-2.1.1-14/status.json)。最终归档及严格签名已通过，见 [最终源摘要与归档记录](../../../artifacts/testflight-2.1.1-14/source-manifest.json)；最新 first PiP／灵动岛真机回归仍待补，未提交正式 App Store 审核或发布。

海报 01 已批准采用本组最新真实首页，文案“随屏与资料，从这里开始”；02 采用本组正确独立准备页，01 不再等待 PiP 图。六图由主任务并行制作，本记录不宣称已经上传商店素材；本次文档更新没有重绘原始截图。

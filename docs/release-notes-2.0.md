# GemmaTrans 2.0：更安静、更明确的本地翻译体验

GemmaTrans 2.0 不是一次简单换肤。主窗口、设置、模型管理和快捷翻译浮窗都围绕同一件事重新设计：让译文成为主角，让工具在需要时出现，并在不需要时保持安静。

## 全新的 Quiet Glass 界面

- 重新设计主翻译窗口，输入和译文保持清晰的双栏关系。
- 设置集中为“通用、模型、集成”三个标签，控件密度和状态表达一致。
- 浅色、深色和系统外观使用语义颜色与克制的 Liquid Glass 层级。
- 菜单栏命令会把正确窗口带到前台；快捷翻译不会打断当前 App。

## 更适合连续阅读的翻译浮窗

- 译文优先，减少不必要的外围结构和重复状态。
- 支持固定浮窗位置，逐段翻译长文时保持视线与窗口稳定。
- 完成后提供等尺寸的复制与朗读操作，Esc 随时关闭。
- 译文字号可在设置中从 12pt 到 18pt 调整。
- 长译文保留滚动能力，但默认隐藏滚动条，并用轻微渐隐提示下方仍有内容。

## 模型由你决定

GemmaTrans 不再在首次启动时自动联网和下载模型。你可以在模型页明确选择：

- Gemma 4 E4B 4-bit（约 4.9GB）
- Gemma 4 E2B 4-bit（约 3.6GB）
- Hy-MT2 1.8B 4-bit（约 1.1GB）
- Hy-MT2 1.8B 8-bit（约 1.9GB）

下载优先使用 Hugging Face；连接或远端清单不可用时，应用自动回退到 ModelScope。下载新模型时，当前模型仍可继续翻译。

## 隐私与兼容性

模型下载完成后，翻译全部在本机完成。GemmaTrans 不包含分析、广告或云端 AI 服务；可选本地 API 仅监听 `127.0.0.1`。

GemmaTrans 2.0 要求 Apple Silicon Mac 与 macOS 26.0 或更高版本。升级会保留现有 UserDefaults、模型目录和 API 配置；旧版 `auto` 或未知模型选择会迁移为“尚未选择模型”，不会触发隐式下载。

## 发布验收

- Swift 核心、路由、设置、模型下载与浮窗几何测试全部通过。
- `GemmaTrans` 与 `GemmaTrans-MAS` 两个 scheme 构建通过。
- GitHub 直分发包需完成 Developer ID 签名、Apple 公证和 Gatekeeper 验证。
- Mac App Store 包需以 Apple Distribution 签名导出，并先上传至 App Store Connect/TestFlight 验证。

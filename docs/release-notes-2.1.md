# GemmaTrans 2.1 发布说明

## 用户版 What's New

GemmaTrans 2.1 新增两款更小的本地翻译模型：

- Hy-MT2 1.8B（1.25-bit · 轻量版），约 440 MB。
- Hy-MT2 1.8B（2-bit · 均衡版），约 573 MB。

两款模型都在 Apple Silicon Mac 上完全本地运行。请在“设置 › 模型”中主动下载并切换；升级不会自动下载，也不会改变当前模型。下载文件绑定固定版本并校验大小和 SHA-256，Hugging Face 不可用时自动回退 ModelScope。

本版本还改进了长文本工作流：GemmaTrans 的 PopClip 插件现在直接调用 macOS 系统服务，在可滚动的多行浮窗中显示完整译文；本地 API 也显式放宽服务端处理窗口，避免较慢请求提前在 15 秒中断。

## English What's New

GemmaTrans 2.1 adds two smaller on-device translation models:

- Hy-MT2 1.8B 1.25-bit Lightweight, about 440 MB.
- Hy-MT2 1.8B 2-bit Balanced, about 573 MB.

Both models run fully on-device on Apple silicon. Download and select one explicitly under Settings › Models. Updating never downloads a model or changes your active model automatically. Fixed model revisions are verified by file size and SHA-256, with automatic fallback from Hugging Face to ModelScope.

This release also improves long-text workflows. The bundled PopClip action now uses the native macOS Service and shows the complete result in GemmaTrans's scrollable multiline panel. The local API also allows a longer server processing window instead of ending slower requests after 15 seconds.

## TestFlight 测试重点

1. 从 2.0 升级后，确认当前模型不变，首次启动没有自动下载。
2. 分别下载“1.25-bit · 轻量版”和“2-bit · 均衡版”，确认显示约 440 MB 与约 573 MB。
3. 在主窗口、⌥⌘T 系统服务、⌥D 剪贴板浮窗和本地 API 中分别翻译中英文。
4. 下载完成后断网，确认两款模型均可翻译。
5. 在 1.25-bit → 2-bit → 旧 MLX 模型之间切换，确认翻译、停止和删除保护正常。
6. 重点观察数字、URL、Markdown、代码和占位符是否保持不变，并报告复读、漏译、乱码或明显语义反转。
7. 安装仓库内 PopClip 插件，选择超过 160 字符的多段文本，确认结果进入 GemmaTrans 多行浮窗而不是 PopClip 单行预览。
8. 使用非流式本地 API 发起耗时超过 15 秒的请求，确认不会提前返回 HTTP 500。

## 兼容与回滚

- 仅支持 Apple Silicon Mac 与 macOS 26.0 或更高版本；不新增 iOS App。
- 旧四款模型的 ID、目录和行为不变。
- 回退 2.0 时旧模型继续可用；2.0 不会误加载新增模型目录。
- 正式 `v2.1.0` 标签、GitHub ZIP/DMG 和 Mac App Store 提审，均等待 TestFlight 验收通过后执行。

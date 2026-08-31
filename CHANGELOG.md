# Changelog

GemmaTrans 的用户可见变更记录。版本遵循语义化版本号；macOS App 的正式构建号由 App Store Connect 发布流程单独递增。

## [2.1.0] - 2026-08-31

### Added

- 新增 Hy-MT2 1.8B（1.25-bit · 轻量版，约 440 MB）与 Hy-MT2 1.8B（2-bit · 均衡版，约 573 MB）。
- 新增面向两款策展 GGUF 的 CPU/NEON 静态运行时；运行时来源、补丁、许可证和确定性构建脚本均随仓库提供。
- 新增固定 revision 单文件下载，下载完成后校验精确字节数和 SHA-256。

### Changed

- 模型页由四款增加为六款；旧模型顺序、标识、目录和行为保持不变。
- Hy-MT2 提示词与官方 1.8B 推荐对齐：完整语言名、仅 user 消息、无 system prompt。
- 小于 1 GiB 的模型使用 MB 显示体积；下载完成后仍由用户主动切换，不自动改变当前模型。
- PopClip 插件改为调用 GemmaTrans 的 macOS Service，在原生可滚动多行浮窗中展示完整译文。

### Fixed

- 修复 PopClip `show-result` 将长译文限制为单行、最多预览 160 字符的问题。
- 修复本地 API 沿用 FlyingFox 15 秒默认 handler 超时、较慢请求提前返回 HTTP 500 的问题。

### Compatibility

- 仅支持 Apple Silicon Mac 与 macOS 26.0 或更高版本；本版本不新增 iOS App。
- HTTP API、SSE 格式、UserDefaults key 和旧四款模型目录保持兼容。
- 构建号 17 已上传 TestFlight 用于前一轮初测；本次源码候选构建号为 18，需重新上传验收。正式 `v2.1.0` 标签仅在验收通过后创建。

## [2.0.0] - 2026-07-23

### Added

- Liquid Glass 设计系统，以及主窗口、翻译浮窗和三标签设置窗口的完整重构。
- 翻译浮窗位置固定、可调译文字号、复制反馈和系统朗读。
- Gemma 4 E4B/E2B 与 Hy-MT2 4/8-bit 四个明确可选模型。
- Hugging Face 不可用时自动回退 ModelScope 的下载策略。
- 项目内固定的生成、构建、启动与进程/端口验证脚本。
- Developer ID 手动验收工作流，可在不创建 GitHub Release 的情况下生成已签名、公证产物。

### Changed

- GUI 首次启动不再自动选择或下载模型，由用户明确下载并设为当前使用。
- 翻译浮窗采用结果优先的紧凑结构；快捷翻译不再把主窗口带到前台。
- 菜单栏“显示主窗口”和“设置…”现在会将目标窗口正确置前，但不产生永久悬浮。
- 设置页统一行高、控件尺寸、按钮语义和浅色/深色对比度。
- 模型下载入口不再暴露来源选择，网络回退由应用自动处理。

### Fixed

- 修复新版 Gemma 4 checkpoint 权重结构不兼容时暴露原始 tensor path 的问题，并提供可操作错误信息。
- 修复长译文浮窗内容被裁切、滚动状态不清晰和连续请求覆盖的问题。
- 修复系统外观切换、浅色模式对比度、输入光标与占位文字错位。
- 修复翻译浮窗矩形外框、按钮尺寸不一致和窗口置顶行为。

### Compatibility

- macOS 26.0 或更高版本。
- Apple Silicon Mac。
- 不修改 HTTP API、UserDefaults key、模型目录或对外数据格式。

[2.0.0]: https://github.com/Rand01ph/gemma-trans/compare/v1.1.0...v2.0.0
[2.1.0]: https://github.com/Rand01ph/gemma-trans/compare/v2.0.0...v2.1.0

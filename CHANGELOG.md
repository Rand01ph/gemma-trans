# Changelog

GemmaTrans 的用户可见变更记录。版本遵循语义化版本号；macOS App 的正式构建号由 App Store Connect 发布流程单独递增。

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

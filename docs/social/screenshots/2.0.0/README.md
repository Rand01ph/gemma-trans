# GemmaTrans 2.0 发布图片

这一目录把 2.0 发布图片按平台分开，避免商店截图、技术帖配图和社交媒体竖图混用。

## App Store

正式商店截图位于 [`docs/app-store/screenshots/2.0.0`](../../../app-store/screenshots/2.0.0)，均为 2560 × 1600 JPEG。上传顺序：

1. `01-main-dark.jpg` — 主窗口与双栏翻译
2. `03-panel-light.jpg` — 可固定的划词翻译浮窗
3. `04-settings-general-light.jpg` — 通用设置
4. `05-settings-models-light.jpg` — 四款本地模型与下载源自动回退
5. `06-settings-integrations-light.jpg` — 快捷键与本地 API

这些图片使用真实 Debug 构建和确定性数据生成，不应再叠加二维码、下载地址或社交媒体话术。

## 小红书

[`xiaohongshu`](xiaohongshu) 内是 1440 × 1920、3:4 比例的九宫格成片：

1. `01-cover.jpg` — 故事型封面
2. `02-main-window.jpg` — 双栏主窗口
3. `03-quick-panel.jpg` — 固定位置翻译浮窗
4. `04-general-settings.jpg` — 紧凑通用设置
5. `05-local-models.jpg` — 本地模型选择
6. `06-integrations.jpg` — 快捷键与本地 API
7. `07-design-system.jpg` — `DESIGN.md` 核心规则
8. `08-ai-design-process.jpg` — AI 设计协作闭环
9. `09-download.jpg` — 下载二维码与系统要求

建议按编号原样发布。封面只讲故事，功能信息在第 2–6 张，设计方法在第 7–8 张，下载入口放最后。
`xiaohongshu-preview.jpg` 是 3 × 3 总览，只用于快速审稿，不要作为第十张上传。

重新生成：

```bash
swift script/prepare_social_screenshots.swift
```

脚本只对项目中的真实产品截图做裁切与排版，不使用生成式图片修改 UI。

## GitHub / V2EX

优先直接使用 App Store 的 16:10 图片：

- GitHub Release 首图：`01-main-dark.jpg`
- V2EX 正文：`01-main-dark.jpg`、`03-panel-light.jpg`、`05-settings-models-light.jpg`
- 设计复盘：小红书的 `07-design-system.jpg`、`08-ai-design-process.jpg` 也可作为竖版补图

发布前检查：

- 页面中出现的 Release URL 已经可访问；
- 截图对应版本与发布包一致；
- 不使用带有 Codex 侧栏、用户名、任务标题或自动化标记的过程截图；
- 小红书二维码可由手机实际扫描。

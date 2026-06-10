# 翻译浮窗高度自适应设计

日期：2026-06-10
状态：已确认（方案 A：动态高度，上限 70% 屏高）

## 需求

长译文时浮窗尽量完整展示、不出滚动条；只有内容超过屏幕合理范围才滚动（用户验收反馈）。

## 设计

- 浮窗宽度 360 → **420pt** 固定；高度动态：最小 **140pt**，最大 **屏幕 visibleFrame 高度 × 0.7**，内容在范围内则完整展示（无滚动条），超上限才滚动。
- **高度测量**：`TranslationView` 的译文 `Text` 背景挂 `GeometryReader`，经 `PreferenceKey` 上报渲染高度（macOS 14 兼容，不用 15 的 onGeometryChange）；视图通过 `onContentHeight: (CGFloat) -> Void` 回调把高度交给 `TranslationPanel`。
- **面板调整**（`TranslationPanel.adjustHeight(contentHeight:)`）：目标高度 = clamp(内容高 + 96pt chrome（内边距+状态/按钮行+标题区）, 140, 屏高×0.7)；**顶边保持不动向下生长**（origin.y = 原 maxY − 新高度）；若底边越出 `screen.visibleFrame.minY`，整体上移贴底。`setFrame(_:display:animate: true)` 平滑过渡。
- **流式防抖**：与当前面板高度差 < 8pt 不触发调整。
- `showMessage` 短提示路径不参与自适应（内容固定一行）。

## 错误处理

- `panel.screen` 为 nil（面板尚未上屏）回退 `NSScreen.main`；再为 nil 用 800pt 兜底。

## 测试

- UI 几何逻辑无单测框架覆盖，clamp 计算提为纯静态函数 `TranslationPanel.targetHeight(content:screenVisibleHeight:)` 做单测（3 例：范围内取内容高、低于 min 取 140、超上限取 0.7×屏高）。
- 手动验收：短句（一行，窗口小）；中等段落（完整展示无滚动条）；超长文本（封顶 70% 屏高出滚动条）；屏幕底部附近划词（窗口不越出屏幕）。

## 不做（YAGNI）

宽度自适应、用户可配上限比例、记忆窗口大小。

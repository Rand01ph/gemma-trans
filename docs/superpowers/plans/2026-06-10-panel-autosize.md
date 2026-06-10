# 浮窗高度自适应 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 译文浮窗高度随内容生长（顶边不动），上限 70% 屏高，范围内无滚动条。

**Architecture:** clamp 数学抽成 Kit 里的 `PanelGeometry` 纯函数（可单测，Double 无 UI 依赖）；`TranslationView` 用 GeometryReader+PreferenceKey 上报译文渲染高度；`TranslationPanel` 据此调整 NSPanel frame（防出屏、8pt 防抖、动画）。

**Tech Stack:** SwiftUI PreferenceKey（macOS 14 兼容）、NSPanel setFrame(animate:)。

**Spec:** `docs/superpowers/specs/2026-06-10-panel-autosize-design.md`

---

### Task 1: PanelGeometry 纯函数（TDD）

**Files:**
- Create: `Sources/GemmaTransKit/PanelGeometry.swift`
- Test: `Tests/GemmaTransKitTests/PanelGeometryTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
// Tests/GemmaTransKitTests/PanelGeometryTests.swift
import Testing
@testable import GemmaTransKit

@Suite struct PanelGeometryTests {
    @Test func contentWithinRangeGetsContentPlusChrome() {
        // 200 内容 + 96 chrome = 296，在 [140, 630] 内
        #expect(PanelGeometry.targetHeight(contentHeight: 200, screenVisibleHeight: 900) == 296)
    }

    @Test func tinyContentClampsToMinimum() {
        #expect(PanelGeometry.targetHeight(contentHeight: 10, screenVisibleHeight: 900) == 140)
    }

    @Test func hugeContentClampsTo70PercentOfScreen() {
        #expect(PanelGeometry.targetHeight(contentHeight: 2000, screenVisibleHeight: 1000) == 700)
    }
}
```

- [ ] **Step 2: 跑测确认失败**

Run: `swift test --filter PanelGeometryTests`
Expected: FAIL（PanelGeometry 未定义）

- [ ] **Step 3: 实现**

```swift
// Sources/GemmaTransKit/PanelGeometry.swift
import Foundation

/// 翻译浮窗几何计算。纯函数（Double，无 AppKit 依赖），便于单测。
public enum PanelGeometry {
    public static let panelWidth: Double = 420
    public static let minHeight: Double = 140
    public static let maxScreenFraction: Double = 0.7
    /// 内边距 + 状态/按钮行 + 隐藏标题区
    public static let chromeHeight: Double = 96
    /// 流式期间小于该差值不调整，防抖
    public static let resizeThreshold: Double = 8

    public static func targetHeight(contentHeight: Double, screenVisibleHeight: Double) -> Double {
        min(max(contentHeight + chromeHeight, minHeight), screenVisibleHeight * maxScreenFraction)
    }
}
```

- [ ] **Step 4: 跑测确认通过**

Run: `swift test --filter PanelGeometryTests`
Expected: PASS（3 个测试）

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/PanelGeometry.swift Tests/GemmaTransKitTests/PanelGeometryTests.swift
git commit -m "feat: PanelGeometry 浮窗高度 clamp 纯函数"
```

### Task 2: TranslationPanel/View 接入

**Files:**
- Modify: `App/GemmaTrans/TranslationPanel.swift`

- [ ] **Step 1: TranslationView 上报内容高度**

在文件底部加 PreferenceKey，并改 TranslationView：

```swift
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
```

TranslationView 增加回调属性（放在 `onClose` 下一行）：

```swift
var onContentHeight: (CGFloat) -> Void = { _ in }
```

`Text(...)` 挂背景测量（紧跟 `.textSelection(.enabled)` 之后）：

```swift
.background(GeometryReader { geo in
    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
})
```

整个 VStack 的 `.frame(width: 360, height: 180)` 改为：

```swift
.frame(width: PanelGeometry.panelWidth)
.onPreferenceChange(ContentHeightKey.self) { onContentHeight($0) }
```

文件顶部 `import GemmaTransKit` 已有。

- [ ] **Step 2: TranslationPanel 动态调高**

`present(model:)` 中 NSRect 改为 `NSRect(x: 0, y: 0, width: PanelGeometry.panelWidth, height: PanelGeometry.minHeight)`；创建 view 时传回调：

```swift
let view = TranslationView(
    model: model,
    onClose: { [weak self] in self?.close() },
    onContentHeight: { [weak self] h in self?.adjustHeight(contentHeight: h) }
)
```

新增方法：

```swift
private func adjustHeight(contentHeight: CGFloat) {
    guard let panel else { return }
    let screen = panel.screen ?? NSScreen.main
    let visibleHeight = screen?.visibleFrame.height ?? 800
    let target = PanelGeometry.targetHeight(
        contentHeight: contentHeight, screenVisibleHeight: visibleHeight)
    guard abs(target - panel.frame.height) >= PanelGeometry.resizeThreshold else { return }

    var frame = panel.frame
    let topY = frame.maxY
    frame.size.height = target
    frame.origin.y = topY - target  // 顶边不动向下生长
    if let visible = screen?.visibleFrame, frame.minY < visible.minY {
        frame.origin.y = visible.minY  // 防越出屏幕底部
    }
    panel.setFrame(frame, display: true, animate: true)
}
```

注：`showMessage` 路径内容固定一行，高度上报也会走到 adjustHeight，目标值为 minHeight，与初始一致（差 < 8pt 不动作），自然豁免。

- [ ] **Step 3: 构建 + 重启 + 手动验收**

Run: `cd App && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error|BUILD"; pkill -x GemmaTrans; open build/Build/Products/Debug/GemmaTrans.app`

验收（用户/真机）：① 短句 → 小窗口无空白；② 中等段落（如本 spec 第一段）→ 完整展示无滚动条；③ 超长文本（>2000 字）→ 封顶 70% 屏高出滚动条；④ 屏幕底部划词 → 窗口不越出屏幕。

- [ ] **Step 4: Commit**

```bash
git add App/GemmaTrans/TranslationPanel.swift
git commit -m "feat: 浮窗高度随译文自适应（顶边固定生长/70% 屏高封顶/防抖防出屏）"
```

---

## 自查

spec 全覆盖：宽 420 ✓、min 140 / 70% 上限 ✓（纯函数+测试）、顶边不动 ✓、防出屏 ✓、8pt 防抖 ✓、showMessage 豁免 ✓（差值天然小于阈值）、screen nil 兜底 ✓。类型一致：`PanelGeometry.targetHeight(contentHeight:screenVisibleHeight:)` 两处签名相同；CGFloat→Double 隐式可换（macOS 上等宽）。

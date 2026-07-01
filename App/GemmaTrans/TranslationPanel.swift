import SwiftUI
import AppKit
import GemmaTransKit

@MainActor
final class TranslationPanel {
    static let shared = TranslationPanel()
    private var panel: NSPanel?
    private var messagePanel: NSPanel?
    private var currentState: TranslationPanelState?

    private var isPinned: Bool {
        currentState?.isPinned ?? false
    }

    func show(text: String, engine: TranslationEngine) {
        let model = TranslationViewModel()
        GTLog.info("translation panel show requested chars=\(text.count) pinned=\(isPinned)")
        present(model: model)
        model.start(text: text, engine: engine)
    }

    /// 短提示（如"未检测到选中文本"），1.5 秒后自动关闭
    func showMessage(_ message: String) {
        let model = TranslationViewModel()
        model.output = message
        model.status = " "
        if isPinned, panel != nil {
            GTLog.info("translation transient message while pinned")
            presentTransientMessage(model: model)
            return
        }

        present(model: model)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if self.currentState?.model === model {
                self.close()
            }
        }
    }

    func close() {
        currentState?.model.cancel()
        currentState = nil
        panel?.close()
        panel = nil
        closeMessagePanel()
        GTLog.info("translation panel closed")
    }

    private func present(model: TranslationViewModel) {
        currentState?.model.cancel()  // 取消上一个浮窗的翻译消费，让被取代的生成尽快收尾

        if let panel, let state = currentState, state.isPinned {
            reusePinnedPanel(panel, state: state, model: model)
            return
        }

        let state = TranslationPanelState(model: model)
        let panel = makePanel(contentViewController: NSHostingController(rootView: makeMainView(state)))
        positionPanelNearMouse(panel)
        self.panel?.close()
        currentState = state
        self.panel = panel
        panel.orderFrontRegardless()
        GTLog.info("translation panel presented near mouse")
    }

    private func makeMainView(_ state: TranslationPanelState) -> TranslationView {
        TranslationView(
            state: state,
            showsPinButton: true,
            onTogglePinned: { [weak self] in self?.togglePinned() },
            onClose: { [weak self] in self?.close() },
            onContentHeight: { [weak self] h in self?.adjustHeight(contentHeight: h) }
        )
    }

    private func presentTransientMessage(model: TranslationViewModel) {
        closeMessagePanel()
        let state = TranslationPanelState(model: model)

        let view = TranslationView(
            state: state,
            showsPinButton: false,
            onTogglePinned: {},
            onClose: { [weak self] in self?.closeMessagePanel() },
            onContentHeight: { [weak self] h in self?.adjustMessageHeight(contentHeight: h) }
        )
        let panel = makePanel(contentViewController: NSHostingController(rootView: view))
        positionPanelNearMouse(panel)
        messagePanel = panel
        panel.orderFrontRegardless()

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if self.messagePanel === panel {
                self.closeMessagePanel()
            }
        }
    }

    private func closeMessagePanel() {
        messagePanel?.close()
        messagePanel = nil
    }

    private func togglePinned() {
        guard let panel, let state = currentState else { return }
        state.isPinned.toggle()
        if state.isPinned {
            clampPanelToVisibleFrame(panel, animate: true)
        }
        GTLog.info("translation panel pinned=\(state.isPinned)")
    }

    private func reusePinnedPanel(_ panel: NSPanel, state: TranslationPanelState, model: TranslationViewModel) {
        state.model = model
        clampPanelToVisibleFrame(panel, animate: false)
        panel.orderFrontRegardless()
        GTLog.info("translation panel reused pinned frame")
    }

    private func makePanel(contentViewController: NSViewController) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelGeometry.panelWidth, height: PanelGeometry.minHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        // 跨 Space / 全屏：浮窗出现在「当前」所在 Space（含全屏 app 上方），不跟着主窗口跑回它的桌面。
        // 主窗口开着时切到全屏 app 划词，旧版会把浮窗弹回主窗口所在桌面——根因是浮窗默认绑主窗口的 Space。
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = contentViewController
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    private func positionPanelNearMouse(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let proposed = PanelGeometry.Frame(
            x: mouse.x + 8,
            y: mouse.y - 8 - panel.frame.height,
            width: panel.frame.width,
            height: panel.frame.height
        )
        if let visible = screen?.visibleFrame.panelGeometryFrame {
            panel.setFrame(
                NSRect(panelGeometryFrame: PanelGeometry.clampedFrame(proposed, visibleFrame: visible)),
                display: true
            )
        } else {
            panel.setFrameTopLeftPoint(NSPoint(x: mouse.x + 8, y: mouse.y - 8))
        }
    }

    /// 译文流式生长时随内容调高：顶边不动向下生长，70% 屏高封顶，防越出屏幕底部。
    private func adjustHeight(contentHeight: CGFloat) {
        guard let panel else { return }
        adjustHeight(contentHeight: contentHeight, for: panel)
    }

    private func adjustMessageHeight(contentHeight: CGFloat) {
        guard let messagePanel else { return }
        adjustHeight(contentHeight: contentHeight, for: messagePanel)
    }

    private func adjustHeight(contentHeight: CGFloat, for panel: NSPanel) {
        let screen = panel.screen ?? NSScreen.main
        let visibleHeight = screen?.visibleFrame.height ?? 800
        let target = PanelGeometry.targetHeight(
            contentHeight: contentHeight, screenVisibleHeight: visibleHeight)
        guard abs(target - panel.frame.height) >= PanelGeometry.resizeThreshold else { return }

        var frame = panel.frame
        if let visible = screen?.visibleFrame.panelGeometryFrame {
            frame = NSRect(
                panelGeometryFrame: PanelGeometry.resizedFrameKeepingTop(
                    frame.panelGeometryFrame,
                    targetHeight: target,
                    visibleFrame: visible
                )
            )
        } else {
            let topY = frame.maxY
            frame.size.height = target
            frame.origin.y = topY - target
        }
        panel.setFrame(frame, display: true, animate: true)
    }

    private func clampPanelToVisibleFrame(_ panel: NSPanel, animate: Bool) {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame.panelGeometryFrame else { return }
        let frame = PanelGeometry.clampedFrame(panel.frame.panelGeometryFrame, visibleFrame: visible)
        panel.setFrame(NSRect(panelGeometryFrame: frame), display: true, animate: animate)
    }
}

@MainActor @Observable
final class TranslationPanelState {
    var model: TranslationViewModel
    var isPinned: Bool

    init(model: TranslationViewModel, isPinned: Bool = false) {
        self.model = model
        self.isPinned = isPinned
    }
}

@MainActor @Observable
final class TranslationViewModel {
    var output = ""
    var status = ""
    var error: String?
    /// 上次生成速度（tok/s），生成结束后从引擎取，供面板观察性能。
    var tokensPerSecond: Double?
    private var task: Task<Void, Never>?

    func start(text: String, engine: TranslationEngine) {
        GTLog.info("translation model start chars=\(text.count)")
        status = "翻译中…"
        task = Task {
            do {
                let result = try await engine.translate(text, target: nil)
                if result.truncated { status = "（超长已截断）翻译中…" }
                for try await chunk in result.chunks {
                    output += chunk
                }
                tokensPerSecond = await engine.lastTokensPerSecond
                EngineController.shared.recordTokensPerSecond(tokensPerSecond)
                status = "\(result.detected) → \(result.target)"
            } catch is CancellationError {
                GTLog.info("translation model cancelled")
                // 被新请求取代，旧浮窗已关闭，无需展示
            } catch {
                self.error = "\(error)"
                status = ""
                GTLog.error("translation failed: \(error)")
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// 主窗口复用同一个 view model：开新翻译/清空前先取消在飞生成并清状态。
    func reset() {
        task?.cancel()
        output = ""
        status = ""
        error = nil
        tokensPerSecond = nil
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TranslationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared

    let state: TranslationPanelState
    var showsPinButton = true
    let onTogglePinned: () -> Void
    let onClose: () -> Void
    var onContentHeight: (CGFloat) -> Void = { _ in }

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(showsIndicators: true) {
                Text(displayText)
                    .font(.system(size: 15))
                    .lineSpacing(1.5)
                    .foregroundStyle(model.error == nil ? theme.textPrimary : theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    })
            }
            HStack(spacing: 7) {
                statusView
                Spacer()
                actionButtons
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(width: PanelGeometry.panelWidth)
        .background {
            GlassSurface(
                cornerRadius: 18,
                fill: theme.windowOverlay,
                stroke: theme.hairline,
                shadowOpacity: theme.isDark ? 0.22 : 0.05,
                shadowRadius: 8,
                shadowY: 4
            )
        }
        .glassPreferredColorScheme(theme)
        .onPreferenceChange(ContentHeightKey.self) { onContentHeight($0) }
    }

    private var model: TranslationViewModel {
        state.model
    }

    private var displayText: String {
        model.error ?? (model.output.isEmpty ? "…" : model.output)
    }

    @ViewBuilder
    private var actionButtons: some View {
        actionButtonContent
    }

    private var actionButtonContent: some View {
        HStack(spacing: 4) {
            if showsPinButton {
                GlassIconButton(
                    systemName: state.isPinned ? "mappin.circle.fill" : "mappin",
                    help: state.isPinned ? "取消固定位置" : "固定位置",
                    isActive: state.isPinned,
                    action: onTogglePinned
                )
            }
            GlassIconButton(
                systemName: "doc.on.doc",
                help: "复制译文",
                isDisabled: model.output.isEmpty
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.output, forType: .string)
            }
            GlassIconButton(systemName: "xmark", help: "关闭", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        HStack(spacing: 6) {
            Text(model.status)
            if let tps = model.tokensPerSecond {
                Text(String(format: "· %.1f tok/s", tps))
            }
        }
        .font(.caption)
        .foregroundStyle(theme.textSecondary)
        .lineLimit(1)
    }
}

private extension NSRect {
    init(panelGeometryFrame frame: PanelGeometry.Frame) {
        self.init(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    var panelGeometryFrame: PanelGeometry.Frame {
        PanelGeometry.Frame(x: origin.x, y: origin.y, width: width, height: height)
    }
}

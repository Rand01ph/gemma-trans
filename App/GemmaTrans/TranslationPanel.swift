import AppKit
import AVFoundation
import QuartzCore
import SwiftUI
import GemmaTransKit

@MainActor @Observable
private final class TranslationPanelInteractionState {
    var isPositionLocked = false
}

@MainActor
final class TranslationPanel {
    static let shared = TranslationPanel()

    private var panel: TranslationFloatingPanelWindow?
    private var currentModel: TranslationViewModel?
    private var currentMode: TranslationPanelLayoutMode = .translation
    private var didSettleCompletedLayout = false
    private var escapeMonitor: Any?
    private let interactionState = TranslationPanelInteractionState()
    private var lockedTopLeft: NSPoint?

    func show(text: String, engine: TranslationEngine) {
        let model = TranslationViewModel()
        present(model: model) {
            model.reset()
            model.start(text: text, engine: engine)
        }
        model.start(text: text, engine: engine)
    }

    func showMessage(_ message: String) {
        let model = TranslationViewModel()
        model.setMessage(message)
        present(model: model, mode: .message)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            self.close()
        }
    }

#if DEBUG
    func showScreenshotFixture() {
        let model = TranslationViewModel()
        model.setMessage(GTDebugScreenshotFixture.panelOutput)
        model.status = "zh-Hans → en"
        model.tokensPerSecond = 72.4
        interactionState.isPositionLocked = true
        present(model: model)
        if let panel {
            GTDebugScreenshotFixture.captureIfRequested(window: panel, matching: "panel")
        }
    }
#endif

    func close() {
        if interactionState.isPositionLocked, currentMode == .translation, let panel {
            captureLockedPosition(from: panel)
        }
        currentModel?.cancel()
        currentModel = nil
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        panel?.close()
        panel = nil
    }

    private func present(model: TranslationViewModel,
                         mode: TranslationPanelLayoutMode = .translation,
                         onRetry: (() -> Void)? = nil) {
        // Capture the external activation owner before creating or reordering any AppKit
        // objects. `orderFrontRegardless` is intentionally non-activating; the process ID is
        // retained only as a guard against delayed activation races from the shortcut path.
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let foregroundProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let externalForegroundProcessID = foregroundProcessID == currentProcessID
            ? nil
            : foregroundProcessID
        let previousMode = currentMode
        let previousPanel = panel
        if interactionState.isPositionLocked, previousMode == .translation, let previousPanel {
            captureLockedPosition(from: previousPanel)
        }

        currentModel?.cancel()
        currentModel = model
        currentMode = mode
        didSettleCompletedLayout = false

        let view = GTTranslationPanelView(
            model: model,
            mode: mode,
            action: .translate,
            interactionState: interactionState,
            resultFontSize: CGFloat(AppSettings.load().translationFontSize),
            onRetry: onRetry,
            onClose: { [weak self] in self?.close() },
            onStop: { model.cancel() },
            onTogglePositionLock: { [weak self] in self?.togglePositionLock() },
            onContentHeight: { [weak self] height, settle in
                self?.adjustHeight(contentHeight: height, settleCompletedLayout: settle)
            }
        )
        let hosting = NSHostingController(rootView: view)

        let canReuseLockedPanel = interactionState.isPositionLocked
            && previousMode == .translation
            && mode == .translation
            && previousPanel != nil
        let panel: TranslationFloatingPanelWindow
        if canReuseLockedPanel, let previousPanel {
            panel = previousPanel
        } else {
            panel = TranslationFloatingPanelWindow(
                contentRect: NSRect(x: 0,
                                    y: 0,
                                    width: mode.windowSize.width,
                                    height: mode.windowSize.height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.masksToBounds = false
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.layer?.masksToBounds = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let targetFrame = presentationFrame(for: mode)
        panel.setFrame(targetFrame, display: false)
        if let previousPanel, previousPanel !== panel {
            previousPanel.close()
        }
        self.panel = panel
        installEscapeMonitor()
        panel.orderFrontRegardless()
        yieldActivationIfNeeded(to: externalForegroundProcessID)
        // Activation changes can land one run-loop turn after ordering. Re-check once without
        // ever calling `activate` on GemmaTrans or reordering its normal windows.
        DispatchQueue.main.async { [weak self] in
            self?.yieldActivationIfNeeded(to: externalForegroundProcessID)
        }
    }

    private func yieldActivationIfNeeded(to processIdentifier: pid_t?) {
        guard let processIdentifier,
              NSApp.isActive,
              let foregroundApplication = NSRunningApplication(
                processIdentifier: processIdentifier
              ) else { return }
        NSApp.yieldActivation(to: foregroundApplication)
    }

    private func installEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.close()
            return nil
        }
    }

    private func adjustHeight(contentHeight: CGFloat, settleCompletedLayout: Bool) {
        guard let panel, currentMode == .translation else { return }
        let screen = panel.screen ?? NSScreen.main
        let visibleHeight = screen?.visibleFrame.height ?? 800
        let targetVisualHeight = PanelGeometry.targetHeight(
            contentHeight: contentHeight,
            screenVisibleHeight: visibleHeight
        )
        let targetWindowHeight = targetVisualHeight + GTGlassTokens.Panel.translationShadowGutter * 2
        guard abs(targetWindowHeight - panel.frame.height) >= PanelGeometry.resizeThreshold else { return }

        var frame = panel.frame
        frame.size.height = targetWindowHeight
        if interactionState.isPositionLocked, let lockedTopLeft,
           let visible = screen?.visibleFrame {
            let origin = PanelGeometry.lockedWindowOrigin(
                anchorX: Double(lockedTopLeft.x),
                anchorTopY: Double(lockedTopLeft.y),
                windowWidth: Double(frame.width),
                windowHeight: Double(frame.height),
                visibleMinX: Double(visible.minX),
                visibleMinY: Double(visible.minY),
                visibleMaxX: Double(visible.maxX),
                visibleMaxY: Double(visible.maxY)
            )
            frame.origin = NSPoint(x: CGFloat(origin.x), y: CGFloat(origin.y))
            self.lockedTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
        } else {
            let topY = panel.frame.maxY
            frame.origin.y = topY - targetWindowHeight
            if let visible = screen?.visibleFrame, frame.minY < visible.minY {
                frame.origin.y = visible.minY
            }
        }

        let shouldAnimate = settleCompletedLayout
            && !didSettleCompletedLayout
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if settleCompletedLayout { didSettleCompletedLayout = true }

        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true, animate: false)
        }
    }

    private func initialFrame(for mode: TranslationPanelLayoutMode) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let size = mode.windowSize
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let margin: CGFloat = 10
        // Anchor the visible rounded surface, not the larger transparent shadow window.
        var frame = NSRect(x: mouse.x + margin - mode.shadowGutter,
                           y: mouse.y - margin - size.height + mode.shadowGutter,
                           width: size.width,
                           height: size.height)

        if frame.maxX > visible.maxX - margin { frame.origin.x = visible.maxX - size.width - margin }
        if frame.minX < visible.minX + margin { frame.origin.x = visible.minX + margin }
        if frame.minY < visible.minY + margin { frame.origin.y = visible.minY + margin }
        if frame.maxY > visible.maxY - margin { frame.origin.y = visible.maxY - size.height - margin }
        return frame
    }

    private func presentationFrame(for mode: TranslationPanelLayoutMode) -> NSRect {
        guard mode == .translation,
              interactionState.isPositionLocked,
              let lockedTopLeft else {
            return initialFrame(for: mode)
        }

        let size = mode.windowSize
        let anchorPoint = NSPoint(x: lockedTopLeft.x + mode.shadowGutter,
                                  y: lockedTopLeft.y - mode.shadowGutter)
        let screen = NSScreen.screens.first { NSMouseInRect(anchorPoint, $0.frame, false) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let origin = PanelGeometry.lockedWindowOrigin(
            anchorX: Double(lockedTopLeft.x),
            anchorTopY: Double(lockedTopLeft.y),
            windowWidth: Double(size.width),
            windowHeight: Double(size.height),
            visibleMinX: Double(visible.minX),
            visibleMinY: Double(visible.minY),
            visibleMaxX: Double(visible.maxX),
            visibleMaxY: Double(visible.maxY)
        )
        return NSRect(x: CGFloat(origin.x),
                      y: CGFloat(origin.y),
                      width: size.width,
                      height: size.height)
    }

    private func togglePositionLock() {
        interactionState.isPositionLocked.toggle()
        if interactionState.isPositionLocked, let panel, currentMode == .translation {
            captureLockedPosition(from: panel)
        } else {
            lockedTopLeft = nil
        }
    }

    private func captureLockedPosition(from panel: NSPanel) {
        lockedTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }
}

final class TranslationFloatingPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private enum TranslationPanelLayoutMode {
    case translation
    case message

    var visualWidth: CGFloat {
        switch self {
        case .translation: return GTGlassTokens.Panel.translationVisualWidth
        case .message: return GTGlassTokens.Panel.messageVisualSize.width
        }
    }

    var initialVisualHeight: CGFloat {
        switch self {
        case .translation: return GTGlassTokens.Panel.translationInitialVisualHeight
        case .message: return GTGlassTokens.Panel.messageVisualSize.height
        }
    }

    var shadowGutter: CGFloat { GTGlassTokens.Panel.translationShadowGutter }

    var windowSize: NSSize {
        NSSize(width: visualWidth + shadowGutter * 2,
               height: initialVisualHeight + shadowGutter * 2)
    }

    var surfacePadding: CGFloat {
        switch self {
        case .translation: return 10
        case .message: return 16
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .translation: return 18
        case .message: return 22
        }
    }
}

enum TextActionKind: String, CaseIterable, Identifiable {
    case translate

    var id: String { rawValue }
}

struct TextActionDescriptor: Identifiable {
    let id: TextActionKind
    let title: String
    let systemImage: String
    let kind: TextActionKind

    static let registered: [TextActionDescriptor] = [
        TextActionDescriptor(id: .translate,
                             title: "翻译",
                             systemImage: "wand.and.sparkles",
                             kind: .translate),
    ]
}

enum TranslationPhase: Equatable {
    case idle
    case running
    case completed
    case failed(String)
    case cancelled
}

@MainActor @Observable
final class TranslationViewModel {
    var output = ""
    var status = ""
    private(set) var phase: TranslationPhase = .idle
    var tokensPerSecond: Double?

    private var task: Task<Void, Never>?
    private var generation = 0

    var isRunning: Bool { phase == .running }

    var error: String? {
        guard case .failed(let message) = phase else { return nil }
        return message
    }

    func start(text: String, engine: TranslationEngine) {
        generation += 1
        let currentGeneration = generation
        phase = .running
        status = "翻译中…"

        task = Task {
            do {
                let result = try await engine.translate(text, target: nil)
                guard currentGeneration == generation else { return }
                if result.truncated { status = "（超长已截断）翻译中…" }
                for try await chunk in result.chunks {
                    guard currentGeneration == generation else { return }
                    output += chunk
                }
                guard currentGeneration == generation else { return }
                tokensPerSecond = await engine.lastTokensPerSecond
                EngineController.shared.recordTokensPerSecond(tokensPerSecond)
                status = "\(result.detected) → \(result.target)"
                phase = .completed
            } catch is CancellationError {
                guard currentGeneration == generation else { return }
                phase = .cancelled
                if output.isEmpty { status = "已停止" }
            } catch {
                guard currentGeneration == generation else { return }
                let message = "\(error)"
                phase = .failed(message)
                status = ""
                GTLog.error("translation failed: \(error)")
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        phase = .cancelled
        if output.isEmpty {
            status = "已停止"
        } else if !status.contains("已停止") {
            status = status.isEmpty ? "已停止" : "\(status) · 已停止"
        }
    }

    func reset() {
        generation += 1
        task?.cancel()
        output = ""
        status = ""
        tokensPerSecond = nil
        phase = .idle
    }

    func setMessage(_ message: String) {
        reset()
        output = message
        phase = .completed
    }
}

@MainActor
private final class TranslationPanelSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: trimmed))
    }
}

private struct GTTranslationPanelView: View {
    let model: TranslationViewModel
    let mode: TranslationPanelLayoutMode
    let action: TextActionKind
    let interactionState: TranslationPanelInteractionState
    let resultFontSize: CGFloat
    let onRetry: (() -> Void)?
    let onClose: () -> Void
    let onStop: () -> Void
    let onTogglePositionLock: () -> Void
    var onContentHeight: (CGFloat, Bool) -> Void = { _, _ in }

    @State private var speaker = TranslationPanelSpeaker()
    @State private var copied = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var resultSurfaceHeight = CGFloat(PanelGeometry.streamingResultSurfaceHeight)
    @State private var hasResultContentBelow = false

    var body: some View {
        ZStack {
            Color.clear
            GlassEffectContainer(spacing: GTGlassTokens.Space.m) {
                visibleSurface
            }
            .padding(mode.shadowGutter)
        }
        .frame(width: mode.windowSize.width)
        .gtApplicationAppearance()
        .onAppear {
            onContentHeight(preferredVisualHeight, false)
            if model.phase == .completed {
                settleCompletedResultLayout()
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .completed {
                settleCompletedResultLayout()
            }
        }
        .onDisappear { copyFeedbackTask?.cancel() }
    }

    @ViewBuilder
    private var visibleSurface: some View {
        switch mode {
        case .translation: translationSurface
        case .message: messageSurface
        }
    }

    private var translationSurface: some View {
        panelContent
            .padding(mode.surfacePadding)
            .frame(width: mode.visualWidth,
                   height: preferredVisualHeight,
                   alignment: .topLeading)
            .gtGlassSurface(.flat,
                            cornerRadius: mode.cornerRadius,
                            fillOpacity: 0.20,
                            gradient: false)
            .background {
                GTExteriorShadow(cornerRadius: mode.cornerRadius,
                                 color: .black.opacity(0.20),
                                 radius: 8,
                                 y: 4)
            }
    }

    private var messageSurface: some View {
        HStack(spacing: GTGlassTokens.Space.m) {
            Text(resultText)
                .font(.system(size: 15, weight: .medium))
                .lineSpacing(2)
                .foregroundStyle(model.error == nil ? Color.primary : GTGlassPalette.semanticRed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            GTGlassIconButton(title: "关闭", systemImage: "xmark", quiet: true, size: 28, action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(mode.surfacePadding)
        .frame(width: mode.visualWidth,
               height: mode.initialVisualHeight,
               alignment: .center)
        .gtGlassSurface(.flat,
                        cornerRadius: mode.cornerRadius,
                        fillOpacity: 0.20,
                        gradient: false)
        .background {
            GTExteriorShadow(cornerRadius: mode.cornerRadius,
                             color: .black.opacity(0.20),
                             radius: 8,
                             y: 4)
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            actionHeader
            resultSurface
            resultActions
        }
    }

    private var actionHeader: some View {
        HStack(spacing: GTGlassTokens.Space.s) {
            actionIdentity
            Spacer(minLength: GTGlassTokens.Space.s)
            phaseMetadata
            GTGlassIconButton(
                title: interactionState.isPositionLocked ? "取消固定位置" : "固定浮窗位置",
                systemImage: interactionState.isPositionLocked ? "pin.fill" : "pin",
                emphasis: interactionState.isPositionLocked ? .selected : .secondary,
                quiet: !interactionState.isPositionLocked,
                size: 24,
                action: onTogglePositionLock
            )
            GTGlassIconButton(title: "关闭", systemImage: "xmark", quiet: true, size: 24, action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private var actionIdentity: some View {
        if TextActionDescriptor.registered.count > 1 {
            Menu {
                ForEach(TextActionDescriptor.registered) { descriptor in
                    Button {
                        // Future actions apply to the next request; only translation is registered today.
                    } label: {
                        Label(descriptor.title, systemImage: descriptor.systemImage)
                    }
                    .disabled(descriptor.kind == action)
                }
            } label: {
                actionLabel
            }
            .menuStyle(.borderlessButton)
        } else {
            actionLabel
        }
    }

    @ViewBuilder
    private var actionLabel: some View {
        let descriptor = TextActionDescriptor.registered.first { $0.kind == action }
            ?? TextActionDescriptor.registered[0]
        Label(descriptor.title, systemImage: descriptor.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .help(EngineController.shared.activeModelName)
    }

    private var phaseMetadata: some View {
        Group {
            switch model.phase {
            case .idle:
                Text("等待结果").foregroundStyle(GTGlassPalette.secondaryText)
            case .running:
                HStack(spacing: GTGlassTokens.Space.s) {
                    ProgressView().controlSize(.small)
                    Text("正在翻译…")
                }
                .foregroundStyle(GTGlassPalette.secondaryText)
            case .completed:
                completedStatus
            case .failed:
                Label("翻译失败", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(GTGlassPalette.semanticRed)
            case .cancelled:
                Text("已停止").foregroundStyle(GTGlassPalette.secondaryText)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    private var resultSurface: some View {
        ScrollView(.vertical) {
            Text(resultText)
                .font(.system(size: resultFontSize, weight: .regular))
                .lineSpacing(resultLineSpacing)
                .foregroundStyle(resultForeground)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, resultHorizontalInset)
                .padding(.vertical, resultVerticalInset)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            PanelGeometry.hasContentBelow(
                contentHeight: Double(geometry.contentSize.height),
                visibleMaxY: Double(geometry.visibleRect.maxY)
            )
        } action: { _, hasContentBelow in
            hasResultContentBelow = hasContentBelow
        }
        .mask {
            VStack(spacing: 0) {
                Rectangle().fill(.black)
                if hasResultContentBelow {
                    LinearGradient(
                        colors: [.black, .black.opacity(0.42), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: resultSurfaceHeight)
    }

    private var resultActions: some View {
        HStack(spacing: GTGlassTokens.Space.s) {
            switch model.phase {
            case .running:
                GTGlassButton("停止", systemImage: "stop.fill", emphasis: .interrupt, compact: true) {
                    onStop()
                }
            case .failed:
                if let onRetry {
                    GTGlassButton("重试", systemImage: "arrow.clockwise", emphasis: .primary, compact: true) {
                        onRetry()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            case .completed, .cancelled:
                GTGlassIconButton(
                    title: copied ? "已复制译文" : "复制译文",
                    systemImage: copied ? "checkmark" : "doc.on.doc",
                    emphasis: copied ? .feedback : .secondary,
                    size: 26
                ) {
                    copyResult()
                }
                .disabled(model.output.isEmpty)

                GTGlassIconButton(
                    title: "朗读译文",
                    systemImage: "speaker.wave.2",
                    size: 26
                ) {
                    speaker.speak(model.output)
                }
                .disabled(model.output.isEmpty)
            case .idle:
                EmptyView()
            }
            Spacer()
        }
        .frame(height: 26)
    }

    private var resultText: String {
        model.error ?? (model.output.isEmpty ? "译文会显示在这里…" : model.output)
    }

    private var resultForeground: Color {
        if model.error != nil { return GTGlassPalette.semanticRed }
        return model.output.isEmpty ? GTGlassPalette.secondaryText : Color.primary
    }

    private var preferredVisualHeight: CGFloat {
        CGFloat(PanelGeometry.preferredHeight(
            resultSurfaceHeight: Double(resultSurfaceHeight)
        ))
    }

    private func settleCompletedResultLayout() {
        guard mode == .translation else { return }

        let targetSurfaceHeight = measuredResultSurfaceHeight(for: model.output)
        let targetVisualHeight = CGFloat(PanelGeometry.preferredHeight(
            resultSurfaceHeight: Double(targetSurfaceHeight)
        ))
        guard abs(targetVisualHeight - preferredVisualHeight) >= CGFloat(PanelGeometry.resizeThreshold) else {
            return
        }

        resultSurfaceHeight = targetSurfaceHeight
        onContentHeight(targetVisualHeight, true)
    }

    private func measuredResultSurfaceHeight(for text: String) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = resultLineSpacing
        let font = NSFont.systemFont(ofSize: resultFontSize, weight: .regular)
        let contentWidth = mode.visualWidth
            - mode.surfacePadding * 2
            - resultHorizontalInset * 2
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
            ]
        )
        let measuredWithInsets = ceil(bounds.height) + resultVerticalInset * 2
        return CGFloat(PanelGeometry.resultSurfaceHeight(
            measuredContentHeight: Double(measuredWithInsets)
        ))
    }

    private var resultHorizontalInset: CGFloat { 2 }
    private var resultVerticalInset: CGFloat { 1 }
    private var resultLineSpacing: CGFloat { max(1, resultFontSize * 0.12) }

    private var completedStatus: some View {
        Text(completedStatusText)
            .foregroundStyle(GTGlassPalette.secondaryText)
            .help(completedPerformanceHelp)
    }

    private var completedStatusText: String {
        let status = model.status.trimmingCharacters(in: .whitespacesAndNewlines)
        return status.isEmpty ? "译文已生成" : status
    }

    private var completedPerformanceHelp: String {
        if let tokensPerSecond = model.tokensPerSecond {
            return String(format: "生成速度 %.1f tok/s", tokensPerSecond)
        }
        return "翻译完成"
    }

    private func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.output, forType: .string)
        copied = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

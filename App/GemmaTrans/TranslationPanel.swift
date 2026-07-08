import SwiftUI
import AppKit
import AVFoundation
import GemmaTransKit

@MainActor
final class TranslationPanel {
    static let shared = TranslationPanel()
    private var panel: TranslationFloatingPanelWindow?
    private var currentModel: TranslationViewModel?
    private var currentMode: TranslationPanelLayoutMode = .translation

    func show(text: String, engine: TranslationEngine) {
        let model = TranslationViewModel()
        present(model: model, sourceText: text) {
            model.reset()
            model.start(text: text, engine: engine)
        }
        model.start(text: text, engine: engine)
    }

    /// 短提示（如"未检测到选中文本"），1.5 秒后自动关闭
    func showMessage(_ message: String) {
        let model = TranslationViewModel()
        model.output = message
        model.status = " "
        present(model: model, sourceText: "提示", mode: .message)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            self.close()
        }
    }

    func close() {
        currentModel?.cancel()
        currentModel = nil
        panel?.close()
        panel = nil
    }

    private func present(model: TranslationViewModel,
                         sourceText: String,
                         mode: TranslationPanelLayoutMode = .translation,
                         onRetry: (() -> Void)? = nil) {
        currentModel?.cancel()  // 取消上一个浮窗的翻译消费，让被取代的生成尽快收尾
        currentModel = model
        currentMode = mode
        let view = GTTranslationPanelView(
            sourceText: sourceText,
            model: model,
            mode: mode,
            onRetry: onRetry,
            onClose: { [weak self] in self?.close() },
            onStop: { model.cancel() },
            onContentHeight: { [weak self] h in self?.adjustHeight(contentHeight: h) }
        )
        let hosting = NSHostingController(rootView: view)

        let panel = TranslationFloatingPanelWindow(
            contentRect: NSRect(x: 0,
                                y: 0,
                                width: mode.windowSize.width,
                                height: mode.windowSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        // 跨 Space / 全屏：浮窗出现在「当前」所在 Space（含全屏 app 上方），不跟着主窗口跑回它的桌面。
        // 主窗口开着时切到全屏 app 划词，旧版会把浮窗弹回主窗口所在桌面——根因是浮窗默认绑主窗口的 Space。
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        panel.setFrame(initialFrame(for: mode), display: false)
        self.panel?.close()
        self.panel = panel
        panel.orderFrontRegardless()
    }

    /// 译文流式生长时随内容调高：顶边不动向下生长，70% 屏高封顶，防越出屏幕底部。
    private func adjustHeight(contentHeight: CGFloat) {
        guard let panel, currentMode == .translation else { return }
        let screen = panel.screen ?? NSScreen.main
        let visibleHeight = screen?.visibleFrame.height ?? 800
        let targetVisualHeight = PanelGeometry.targetHeight(contentHeight: contentHeight,
                                                            screenVisibleHeight: visibleHeight)
        let targetWindowHeight = targetVisualHeight + GTGlassTokens.Panel.translationShadowGutter * 2
        guard abs(targetWindowHeight - panel.frame.height) >= PanelGeometry.resizeThreshold else { return }

        var frame = panel.frame
        let topY = frame.maxY
        frame.size.height = targetWindowHeight
        frame.origin.y = topY - targetWindowHeight
        if let visible = screen?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        panel.setFrame(frame, display: true, animate: true)
    }

    private func initialFrame(for mode: TranslationPanelLayoutMode) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let size = mode.windowSize
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let margin: CGFloat = 10
        var frame = NSRect(x: mouse.x + margin,
                           y: mouse.y - margin - size.height,
                           width: size.width,
                           height: size.height)

        if frame.maxX > visible.maxX - margin {
            frame.origin.x = visible.maxX - size.width - margin
        }
        if frame.minX < visible.minX + margin {
            frame.origin.x = visible.minX + margin
        }
        if frame.minY < visible.minY + margin {
            frame.origin.y = visible.minY + margin
        }
        if frame.maxY > visible.maxY - margin {
            frame.origin.y = visible.maxY - size.height - margin
        }
        return frame
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

    var minimumVisualHeight: CGFloat {
        switch self {
        case .translation: return GTGlassTokens.Panel.translationMinVisualHeight
        case .message: return GTGlassTokens.Panel.messageVisualSize.height
        }
    }

    var shadowGutter: CGFloat {
        GTGlassTokens.Panel.translationShadowGutter
    }

    var windowSize: NSSize {
        NSSize(width: visualWidth + shadowGutter * 2,
               height: minimumVisualHeight + shadowGutter * 2)
    }

    var surfacePadding: CGFloat {
        switch self {
        case .translation: return 18
        case .message: return 16
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .translation: return 24
        case .message: return 22
        }
    }
}

@MainActor @Observable
final class TranslationViewModel {
    var output = ""
    var status = ""
    var error: String?
    var isRunning = false
    /// 上次生成速度（tok/s），生成结束后从引擎取，供面板观察性能。
    var tokensPerSecond: Double?
    private var task: Task<Void, Never>?

    func start(text: String, engine: TranslationEngine) {
        isRunning = true
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
                isRunning = false
            } catch is CancellationError {
                isRunning = false
                if output.isEmpty { status = "已停止" }
                // 被新请求取代，旧浮窗已关闭，无需展示
            } catch {
                isRunning = false
                self.error = "\(error)"
                status = ""
                GTLog.error("translation failed: \(error)")
            }
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
        if !output.isEmpty {
            status = status.isEmpty ? "已停止" : "\(status) · 已停止"
        }
    }

    /// 主窗口复用同一个 view model：开新翻译/清空前先取消在飞生成并清状态。
    func reset() {
        task?.cancel()
        output = ""
        status = ""
        error = nil
        tokensPerSecond = nil
        isRunning = false
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
    let sourceText: String
    let model: TranslationViewModel
    let mode: TranslationPanelLayoutMode
    let onRetry: (() -> Void)?
    let onClose: () -> Void
    let onStop: () -> Void
    var onContentHeight: (CGFloat) -> Void = { _ in }

    @State private var speaker = TranslationPanelSpeaker()

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
        .onPreferenceChange(ContentHeightKey.self) { onContentHeight($0) }
    }

    @ViewBuilder
    private var visibleSurface: some View {
        switch mode {
        case .translation:
            translationSurface
        case .message:
            messageSurface
        }
    }

    private var translationSurface: some View {
        panelContent
            .padding(mode.surfacePadding)
            .frame(width: mode.visualWidth, alignment: .topLeading)
            .frame(minHeight: mode.minimumVisualHeight, alignment: .topLeading)
            .gtGlassSurface(.flat,
                            cornerRadius: mode.cornerRadius,
                            fill: GTGlassPalette.warmNeutral,
                            fillOpacity: 0.30,
                            gradient: true)
            .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
            .background(GeometryReader { geo in
                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
            })
    }

    private var messageSurface: some View {
        HStack(spacing: GTGlassTokens.Space.m) {
            Text(resultText)
                .font(.system(size: 15, weight: .medium))
                .lineSpacing(2)
                .foregroundStyle(model.error == nil ? Color.primary : GTGlassPalette.semanticRed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            GTGlassIconButton(title: "关闭",
                              systemImage: "xmark",
                              size: 28,
                              action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(mode.surfacePadding)
        .frame(width: mode.visualWidth,
               height: mode.minimumVisualHeight,
               alignment: .center)
        .gtGlassSurface(.flat,
                        cornerRadius: mode.cornerRadius,
                        fill: GTGlassPalette.warmNeutral,
                        fillOpacity: 0.30,
                        gradient: true)
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
        .background(GeometryReader { geo in
            Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
        })
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourceCard
            toolRow
            resultCard
        }
    }

    private var sourceCard: some View {
        HStack(alignment: .top, spacing: GTGlassTokens.Space.m) {
            ScrollView {
                Text(sourceText.isEmpty ? "等待输入..." : sourceText)
                    .font(.system(size: 16, weight: .regular))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 58, maxHeight: sourceTextMaxHeight)

            if let onRetry {
                GTGlassIconButton(title: "重新翻译",
                                  systemImage: "arrow.up",
                                  filled: true,
                                  size: 34,
                                  action: onRetry)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(GTGlassTokens.Space.m)
        .gtGlassSurface(.flat,
                        cornerRadius: 18,
                        fill: GTGlassPalette.coolNeutral,
                        fillOpacity: 0.20,
                        gradient: true,
                        stroke: false)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var toolRow: some View {
        HStack(spacing: 10) {
            PanelToolbarIcon(systemImage: "bubble.left", label: "原文")
            PanelToolbarIcon(systemImage: "globe", label: "自动检测语言")
            PanelPill(title: "翻译", systemImage: "wand.and.sparkles")
            PanelToolbarIcon(systemImage: "checklist", label: "结果")

            Spacer(minLength: GTGlassTokens.Space.l)

            Text(EngineController.shared.activeModelName)
                .font(.system(size: 14.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: 230, alignment: .trailing)
                .help(EngineController.shared.activeModelName)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            GTGlassIconButton(title: "关闭",
                              systemImage: "xmark",
                              size: 30,
                              action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: GTGlassTokens.Space.s) {
            ScrollView {
                Text(resultText)
                    .font(.system(size: 16, weight: .regular))
                    .lineSpacing(2)
                    .foregroundStyle(model.error == nil ? Color.primary : GTGlassPalette.semanticRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 78, maxHeight: resultTextMaxHeight)

            HStack(spacing: GTGlassTokens.Space.m) {
                GTGlassIconButton(title: "复制译文",
                                  systemImage: "doc.on.doc",
                                  size: 30) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.output, forType: .string)
                }
                .disabled(model.output.isEmpty)

                GTGlassIconButton(title: "朗读译文",
                                  systemImage: "speaker.wave.2",
                                  size: 30) {
                    speaker.speak(model.output)
                }
                .disabled(model.output.isEmpty)

                if model.isRunning {
                    GTGlassIconButton(title: "停止翻译",
                                      systemImage: "stop.fill",
                                      tint: GTGlassPalette.semanticOrange,
                                      size: 30,
                                      action: onStop)
                }

                Spacer()

                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(diagnosticText)
            }
        }
        .padding(GTGlassTokens.Space.m)
        .gtGlassSurface(.flat,
                        cornerRadius: 18,
                        fill: GTGlassPalette.peach,
                        fillOpacity: 0.22,
                        gradient: true,
                        stroke: false)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var resultText: String {
        model.error ?? (model.output.isEmpty ? "译文会显示在这里..." : model.output)
    }

    private var sourceTextMaxHeight: CGFloat {
        sourceText.count > 220 ? 96 : 72
    }

    private var resultTextMaxHeight: CGFloat {
        resultText.count > 180 ? 128 : 78
    }

    private var statusText: String {
        if model.error != nil { return "需要处理" }
        if model.isRunning { return "正在翻译..." }
        if model.output.isEmpty { return "等待结果" }
        return "完成"
    }

    private var diagnosticText: String {
        var parts: [String] = []
        let status = model.status.trimmingCharacters(in: .whitespacesAndNewlines)
        if !status.isEmpty { parts.append(status) }
        if let tps = model.tokensPerSecond {
            parts.append(String(format: "%.1f tok/s", tps))
        }
        return parts.isEmpty ? statusText : parts.joined(separator: " · ")
    }
}

private struct PanelToolbarIcon: View {
    var systemImage: String
    var label: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .frame(width: 26, height: 26)
            .foregroundStyle(Color.primary)
            .help(label)
            .accessibilityLabel(label)
    }
}

private struct PanelPill: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, GTGlassTokens.Space.m)
            .frame(height: 32)
            .gtGlassSurface(.flat,
                            cornerRadius: 16,
                            fill: GTGlassPalette.innerNeutral,
                            fillOpacity: 0.16,
                            gradient: true)
    }
}

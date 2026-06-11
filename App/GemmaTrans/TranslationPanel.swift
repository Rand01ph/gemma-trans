import SwiftUI
import AppKit
import GemmaTransKit

@MainActor
final class TranslationPanel {
    static let shared = TranslationPanel()
    private var panel: NSPanel?
    private var currentModel: TranslationViewModel?

    func show(text: String, engine: TranslationEngine) {
        let model = TranslationViewModel()
        present(model: model)
        model.start(text: text, engine: engine)
    }

    /// 短提示（如"未检测到选中文本"），1.5 秒后自动关闭
    func showMessage(_ message: String) {
        let model = TranslationViewModel()
        model.output = message
        model.status = " "
        present(model: model)
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

    private func present(model: TranslationViewModel) {
        currentModel?.cancel()  // 取消上一个浮窗的翻译消费，让被取代的生成尽快收尾
        currentModel = model
        let view = TranslationView(
            model: model,
            onClose: { [weak self] in self?.close() },
            onContentHeight: { [weak self] h in self?.adjustHeight(contentHeight: h) }
        )
        let hosting = NSHostingController(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelGeometry.panelWidth, height: PanelGeometry.minHeight),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentViewController = hosting
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let mouse = NSEvent.mouseLocation
        panel.setFrameTopLeftPoint(NSPoint(x: mouse.x + 8, y: mouse.y - 8))
        self.panel?.close()
        self.panel = panel
        panel.orderFrontRegardless()
    }

    /// 译文流式生长时随内容调高：顶边不动向下生长，70% 屏高封顶，防越出屏幕底部。
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
        frame.origin.y = topY - target
        if let visible = screen?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        panel.setFrame(frame, display: true, animate: true)
    }
}

@MainActor @Observable
final class TranslationViewModel {
    var output = ""
    var status = ""
    var error: String?
    private var task: Task<Void, Never>?

    func start(text: String, engine: TranslationEngine) {
        status = "翻译中…"
        task = Task {
            do {
                let result = try await engine.translate(text, target: nil)
                if result.truncated { status = "（超长已截断）翻译中…" }
                for try await chunk in result.chunks {
                    output += chunk
                }
                status = "\(result.detected) → \(result.target)"
            } catch is CancellationError {
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
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TranslationView: View {
    let model: TranslationViewModel
    let onClose: () -> Void
    var onContentHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(model.error ?? (model.output.isEmpty ? "…" : model.output))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    })
            }
            HStack {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.output, forType: .string)
                }
                .disabled(model.output.isEmpty)
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .frame(width: PanelGeometry.panelWidth)
        .onPreferenceChange(ContentHeightKey.self) { onContentHeight($0) }
    }
}

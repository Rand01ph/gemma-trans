import SwiftUI
import AppKit
import GemmaTransKit

@MainActor
final class TranslationPanel {
    static let shared = TranslationPanel()
    private var panel: NSPanel?

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
        panel?.close()
        panel = nil
    }

    private func present(model: TranslationViewModel) {
        let view = TranslationView(model: model, onClose: { [weak self] in self?.close() })
        let hosting = NSHostingController(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
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
            } catch {
                self.error = "\(error)"
                status = ""
            }
        }
    }
}

struct TranslationView: View {
    let model: TranslationViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(model.error ?? (model.output.isEmpty ? "…" : model.output))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
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
        .frame(width: 360, height: 180)
    }
}

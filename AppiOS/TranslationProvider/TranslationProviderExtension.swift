import SwiftUI
import ExtensionKit
import TranslationUIProvider
import GemmaTransKit
import os

@main
final class TranslationProviderExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            SpikePanelView(box: ContextBox(value: context))
        }
    }
}

/// 把非 Sendable 的 context 装箱跨进 MainActor 的 View init——
/// 场景 content 闭包来自 @preconcurrency 框架（非 MainActor 声明，实际主线程回调），
/// Swift 6 区域隔离不许直接传，装箱后在 init 里取出。
struct ContextBox: @unchecked Sendable {
    let value: any TranslationUIProviderContext
}

/// Spike 探针面板：上屏即报扩展进程内存额度，再尝试加载引擎翻译选中文字。
/// 测得的数字回写 spec（Task 6）后由正式面板替换（Task 7）。
struct SpikePanelView: View {
    @State var context: any TranslationUIProviderContext
    @State private var lines: [String] = []
    @State private var output = ""

    init(box: ContextBox) {
        self.context = box.value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { Text($0).font(.footnote.monospaced()) }
            if !output.isEmpty { Text(output) }
        }
        .padding()
        .task { await spike() }
    }

    private func spike() async {
        log("内存额度: \(os_proc_available_memory() / 1_048_576) MB")
        guard ModelStore.modelDownloaded else {
            log("模型未下载——请先打开 GemmaTrans 主 app")
            return
        }
        let t0 = Date()
        EngineHolder.shared.ensureLoaded()
        while EngineHolder.shared.status != .ready {
            if Task.isCancelled { return }  // 面板收起 .task 被取消，否则 sleep 抛 CancellationError 被吞、循环变热自旋
            if case .failed(let msg) = EngineHolder.shared.status {
                log("引擎加载失败: \(msg)")
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        log("引擎就绪: \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
        guard let engine = EngineHolder.shared.engine,
              let text = context.inputText.map({ String($0.characters) }),
              !text.isEmpty else { return }
        do {
            let t1 = Date()
            let result = try await engine.translate(text, target: nil)
            var first = true
            for try await chunk in result.chunks {
                if first {
                    log("首字: \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
                    first = false
                }
                output += chunk
            }
            log("完成: \(String(format: "%.1f", Date().timeIntervalSince(t1)))s | " +
                "剩余额度: \(os_proc_available_memory() / 1_048_576) MB")
        } catch {
            log("翻译失败: \(error)")
        }
    }

    private func log(_ s: String) {
        lines.append(s)
        GTLog.info("[spike] \(s)")
    }
}

import SwiftUI
import GemmaTransKit

@main
struct GemmaTransApp: App {
    private let controller = EngineController.shared

    init() {
        EngineController.shared.start()
        HotkeyCenter.install(controller: EngineController.shared)
    }

    var body: some Scene {
        MenuBarExtra {
            switch controller.engineStatus {
            case .loading:
                Text("引擎：模型加载中…")
            case .downloading(let progress):
                Text("引擎：模型下载中 \(Self.downloadText(progress))")
            case .ready:
                Text("引擎：就绪")
            case .failed(let msg):
                Text("引擎失败: \(msg)")
                Button("重试加载引擎") { EngineController.shared.retry() }
            }
            switch controller.apiStatus {
            case .disabled:
                Text("API：已关闭")
            case .running(let port):
                Text("API：127.0.0.1:\(String(port))")
            case .failed(let msg):
                Text("API 失败: \(msg)")
            }
            Divider()
            Toggle("本地 API", isOn: Binding(
                get: { EngineController.shared.settings.apiEnabled },
                set: { EngineController.shared.setAPIEnabled($0) }
            ))
            SettingsLink { Text("设置…") }
            Button("退出") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: controller.engineStatus == .ready ? "character.bubble.fill" : "character.bubble")
        }
        Settings {
            SettingsView()
        }
    }

    /// 「35%（1.2/3.4 GB）」；字节未知（HF 宏路径）时只显示百分比
    private static func downloadText(_ progress: DownloadProgress) -> String {
        let pct = Int(progress.fraction * 100)
        guard let done = progress.completedBytes, let total = progress.totalBytes else {
            return "\(pct)%"
        }
        let bytes = String(format: "%.1f/%.1f GB", Double(done) / 1e9, Double(total) / 1e9)
        return "\(pct)%（\(bytes)）"
    }
}

import SwiftUI

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
            case .ready:
                Text("引擎：就绪")
            case .failed(let msg):
                Text("引擎失败: \(msg)")
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
}

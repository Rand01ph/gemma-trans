import SwiftUI

@main
struct GemmaTransApp: App {
    private let controller = EngineController.shared

    init() {
        EngineController.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            switch controller.status {
            case .loading:
                Text("模型加载中…")
            case .ready:
                Text("就绪 · API 127.0.0.1:\(String(controller.settings.port))")
            case .failed(let msg):
                Text("加载失败: \(msg)")
            }
            Divider()
            SettingsLink { Text("设置…") }
            Button("退出") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: controller.status == .ready ? "character.bubble.fill" : "character.bubble")
        }
        Settings {
            SettingsView()
        }
    }
}

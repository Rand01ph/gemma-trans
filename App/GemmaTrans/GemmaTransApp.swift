import SwiftUI
import AppKit
import GemmaTransKit

@main
struct GemmaTransApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let controller = EngineController.shared

    var body: some Scene {
        // 主窗口用 AppKit 显式管理（见 MainWindowController），由 AppDelegate 在启动时
        // 弹出：SwiftUI 的 Window scene 与 MenuBarExtra 共存时启动不必然自动展示窗口，
        // 实测会「有 Dock 图标却无窗口」装死——正是 App Review 2.1a「下载时一直空闲」根因。
        MenuBarExtra {
            switch controller.engineStatus {
            case .needsModel:
                Text("引擎：请选择模型")
            case .loading(let stage):
                Text("引擎：\(stage)")
            case .downloading(let progress):
                Text("引擎：模型下载中 \(Self.downloadText(progress))")
            case .ready:
                Text("引擎：就绪 · \(controller.activeModelName)")
            case .failed(let msg):
                Text("引擎失败: \(msg)")
            }
            switch controller.engineStatus {
            case .loading, .downloading, .failed:
                Button("重新加载引擎") { EngineController.shared.reload() }
            case .needsModel, .ready:
                EmptyView()
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
            Button("显示窗口") { MainWindowController.shared.show() }
            Toggle("本地 API", isOn: Binding(
                get: { EngineController.shared.settings.apiEnabled },
                set: { EngineController.shared.setAPIEnabled($0) }
            ))
            Button("设置…") { MainWindowController.shared.showSettings() }
            Button("退出") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: controller.engineStatus == .ready ? "character.book.closed.fill" : "character.book.closed")
        }

        Settings {
            SettingsView()
                .gtApplicationAppearance()
        }
    }

    /// 「35%（1.2/3.4 GB）」；字节未知（HF 宏路径）时只显示百分比
    static func downloadText(_ progress: DownloadProgress) -> String {
        let pct = Int(progress.fraction * 100)
        guard let done = progress.completedBytes, let total = progress.totalBytes else {
            return "\(pct)%"
        }
        let bytes = String(format: "%.1f/%.1f GB", Double(done) / 1e9, Double(total) / 1e9)
        return "\(pct)%（\(bytes)）"
    }
}

/// 应用级接线：启动引擎、注册剪贴板热键、注册 macOS「服务」provider。
/// 服务注册需在运行期把实例挂到 NSApp.servicesProvider（Info.plist NSServices 仅声明菜单项）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServicesProvider()
#if DEBUG
    private var debugTranslateClipboardObserver: NSObjectProtocol?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        GTAppearanceStore.shared.reloadFromDefaults()
        EngineController.shared.start()
        HotkeyCenter.install()
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            MainWindowController.shared.show()  // 启动即弹主窗口，下载进度对用户/审核员可见
#if DEBUG
            if GTDebugScreenshotFixture.settingsSection != nil {
                MainWindowController.shared.showSettings()
            } else if GTDebugScreenshotFixture.isPanel {
                TranslationPanel.shared.showScreenshotFixture()
            }
#endif
        }
        // 设置窗口由 SwiftUI 管理、拿不到创建句柄：在它成为 key 时补设 moveToActiveSpace，
        // 让从全屏 app 打开「设置」时也来到当前 Space。浮窗(NSPanel)与状态栏(非 titled)跳过。
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil)
#if DEBUG
        // Visual-QA hook for exercising the real floating-panel path without relying on a signed
        // global shortcut. It is compiled out of Release/App Store builds.
        debugTranslateClipboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.gemmatrans.debug.translate-clipboard"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in HotkeyCenter.handle() }
        }
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
#if DEBUG
        if let debugTranslateClipboardObserver {
            DistributedNotificationCenter.default().removeObserver(debugTranslateClipboardObserver)
        }
#endif
    }

    @MainActor @objc private func windowBecameKey(_ note: Notification) {
        guard let win = note.object as? NSWindow,
              !(win is NSPanel),
              win.styleMask.contains(.titled) else { return }
        win.collectionBehavior.insert(.moveToActiveSpace)
    }

    /// 点 Dock 图标 / 重新打开：重新展示主窗口（菜单栏 app 关掉窗口后仍可由此唤回）。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }
}

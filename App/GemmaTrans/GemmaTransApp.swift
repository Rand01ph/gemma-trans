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
            case .loading(let stage):
                Text("引擎：\(stage)")
            case .downloading(let progress):
                Text("引擎：模型下载中 \(Self.downloadText(progress))")
            case .ready:
                Text("引擎：就绪 · \(controller.activeModelName)")
            case .failed(let msg):
                Text("引擎失败: \(msg)")
            }
            if controller.engineStatus != .ready {
                Button("重新加载引擎") { EngineController.shared.reload() }
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        EngineController.shared.start()
        HotkeyCenter.install()
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        MainWindowController.shared.show()  // 启动即弹主窗口，下载进度对用户/审核员可见
        // 设置窗口由 SwiftUI 管理、拿不到创建句柄：在它成为 key 时补设 moveToActiveSpace，
        // 让从全屏 app 打开「设置」时也来到当前 Space。浮窗(NSPanel)与状态栏(非 titled)跳过。
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil)
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

/// 主窗口的 AppKit 宿主：NSWindow + NSHostingController(MainView)，由 AppDelegate 显式弹出。
/// 不用 SwiftUI Window scene——与 MenuBarExtra 共存时其启动自动展示不可靠（见 body 注释）。
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: MainView(controller: EngineController.shared))
            let win = NSWindow(contentViewController: hosting)
            win.title = "GemmaTrans"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false  // 关窗保留实例，下次 reopen 复用
            // 从全屏 app 唤出时窗口来到当前 Space，而不是把人跳回它原来的桌面
            win.collectionBehavior = [.moveToActiveSpace]
            win.setContentSize(NSSize(width: 460, height: 440))
            win.center()
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        // 纯菜单栏 app（LSUIElement）：activate 把窗口带到前台展示，不产生 Dock 图标。
        // 关键：不再 setActivationPolicy(.regular)——保持 accessory，划词时「服务」不会前台化本 app，
        // 浮窗才不会被主窗口拽回它所在的 Space（根因见诊断日志）。
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 主窗口：顶部显示引擎/下载状态（带进度条与失败重试），下方粘贴/输入文字翻译。
/// 这条通道零系统权限，是「服务菜单」「剪贴板热键」之外最稳的兜底入口。
struct MainView: View {
    let controller: EngineController
    @State private var input = ""
    @State private var vm = TranslationViewModel()

    private var canTranslate: Bool {
        controller.engineStatus == .ready
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader
            Divider()
            Text("输入或粘贴要翻译的文字")
                .font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $input)
                    .font(.body)
                    .frame(minHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                if input.isEmpty {
                    Text("在此粘贴文字，或在其他 app 选中文字用「服务」菜单翻译…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Button("翻译") { translate() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canTranslate)
                Button("清空") { input = ""; vm.reset() }
                    .disabled(input.isEmpty && vm.output.isEmpty)
                Spacer()
                if let tps = vm.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", tps))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(vm.status).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                Text(vm.error ?? (vm.output.isEmpty ? "译文显示在这里…" : vm.output))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .foregroundStyle(vm.error != nil ? .red
                        : (vm.output.isEmpty ? .secondary : .primary))
            }
            .frame(minHeight: 120)
        }
        .padding(16)
        .frame(width: 460)
    }

    @ViewBuilder private var statusHeader: some View {
        switch controller.engineStatus {
        case .loading(let stage):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("引擎：\(stage)")
            }
        case .downloading(let p):
            VStack(alignment: .leading, spacing: 4) {
                Text("正在下载翻译模型 \(Int(p.fraction * 100))%")
                ProgressView(value: p.fraction)
                if let d = p.completedBytes, let t = p.totalBytes {
                    Text(String(format: "已下载 %.1f / %.1f GB", Double(d) / 1e9, Double(t) / 1e9))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .ready:
            Label("模型就绪 · \(controller.activeModelName)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("重试下载") { controller.reload() }
            }
        }
    }

    private func translate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, controller.engineStatus == .ready, let engine = controller.engine
        else { return }
        vm.reset()
        vm.start(text: text, engine: engine)
    }
}

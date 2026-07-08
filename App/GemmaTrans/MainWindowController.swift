import AppKit
import Observation
import SwiftUI

enum MainWindowSection: String, CaseIterable, Identifiable {
    case translate
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .translate: return "翻译"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .translate: return "character.bubble"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
@Observable
final class MainWindowState {
    var selectedSection: MainWindowSection = .translate
    var searchText = ""
}

/// 主窗口的 AppKit 宿主。GemmaTrans 仍是菜单栏 app；这里只负责一个当前 Space 的
/// hidden-titlebar glass window，不改变 Dock/activation 策略。
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private let state = MainWindowState()
    private var window: NSWindow?

    func show() {
        state.selectedSection = .translate
        showWindow()
    }

    func showSettings() {
        state.selectedSection = .settings
        showWindow()
    }

    private func showWindow() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: MainView(controller: EngineController.shared, windowState: state)
            )
            let win = NSWindow(contentViewController: hosting)
            win.title = "GemmaTrans"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.isMovableByWindowBackground = true
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = true
            win.isReleasedWhenClosed = false
            win.collectionBehavior = [.moveToActiveSpace]
            win.minSize = GTGlassTokens.Window.minSize
            win.setContentSize(GTGlassTokens.Window.defaultSize)
            centerOnActiveScreen(win)
            window = win
        }

        if let window, !isVisibleOnAnyScreen(window) {
            centerOnActiveScreen(window)
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        let screen = activeScreen()
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        var frame = window.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        frame.origin.x = min(max(frame.origin.x, visible.minX + 12), visible.maxX - frame.width - 12)
        frame.origin.y = min(max(frame.origin.y, visible.minY + 12), visible.maxY - frame.height - 12)
        window.setFrame(frame, display: false)
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func isVisibleOnAnyScreen(_ window: NSWindow) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
    }
}

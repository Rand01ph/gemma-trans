import AppKit
import OSLog
import SwiftUI

/// 主窗口的 AppKit 宿主。GemmaTrans 仍是菜单栏 app；这里只负责一个当前 Space 的
/// native-toolbar glass window，不改变 Dock/activation 策略。
@MainActor
final class MainWindowController: NSObject, NSToolbarDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private weak var settingsWindow: NSWindow?
    private var shouldFocusSettingsWindowOnRegistration = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gemmatrans.GemmaTrans",
        category: "Windowing"
    )

    func show() {
        let window = makeMainWindowIfNeeded()
        if !isVisibleOnAnyScreen(window) {
            centerOnActiveScreen(window)
        }
        scheduleBringToFront(window)
    }

    func showSettings() {
        if let settingsWindow {
            scheduleBringToFront(settingsWindow)
            return
        }

        guard let item = settingsMenuItem(in: NSApp.mainMenu), let action = item.action else {
            NSSound.beep()
            return
        }
        shouldFocusSettingsWindowOnRegistration = true
        guard NSApp.sendAction(action, to: item.target, from: item) else {
            shouldFocusSettingsWindowOnRegistration = false
            NSSound.beep()
            return
        }
    }

    func registerSettingsWindow(_ window: NSWindow) {
        settingsWindow = window
        window.collectionBehavior.insert(.moveToActiveSpace)
        guard shouldFocusSettingsWindowOnRegistration else { return }
        shouldFocusSettingsWindowOnRegistration = false
        scheduleBringToFront(window)
    }

    private func makeMainWindowIfNeeded() -> NSWindow {
        if window == nil {
            let hosting = NSHostingController(
                rootView: MainView(controller: EngineController.shared)
            )
            let win = NSWindow(contentViewController: hosting)
            win.title = "GemmaTrans"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            win.titleVisibility = .visible
            win.titlebarAppearsTransparent = true
            win.titlebarSeparatorStyle = .none
            win.toolbarStyle = .unifiedCompact
            win.toolbar = makeToolbar()
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

        guard let window else {
            preconditionFailure("Main window must exist after creation")
        }
        return window
    }

    /// MenuBarExtra actions run while the status menu is still tracking. Waiting until the
    /// next main-loop turn prevents the menu dismissal from cancelling the activation request.
    private func scheduleBringToFront(_ window: NSWindow) {
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.bringToFront(window)
        }
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.unhide(nil)
        window.collectionBehavior.insert(.moveToActiveSpace)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        // A MenuBarExtra belongs to an accessory app. Establish the intended key window first,
        // then activate and order once more after the status menu has dismissed. The final
        // one-shot order prevents the existing main window from covering Settings without
        // changing either window's normal level.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        let title = window.title
        logger.info("Requested front window: \(title, privacy: .public)")
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.logger.debug(
                "Front result: active=\(NSApp.isActive) key=\(window.isKeyWindow) main=\(window.isMainWindow)"
            )
        }
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: .gemmaTransMain)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .engineStatus, .settings]
    }

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .engineStatus, .settings]
    }

    nonisolated func toolbar(_ toolbar: NSToolbar,
                             itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                             willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        MainActor.assumeIsolated {
            switch itemIdentifier {
            case .engineStatus:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = "引擎状态"
                item.paletteLabel = "引擎状态"
                item.visibilityPriority = .high
                item.view = NSHostingView(
                    rootView: MainToolbarStatus(controller: EngineController.shared)
                )
                return item

            case .settings:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = "设置"
                item.paletteLabel = "设置"
                item.toolTip = "设置"
                item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")
                item.target = self
                item.action = #selector(openSettings(_:))
                item.visibilityPriority = .high
                return item

            default:
                return nil
            }
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        showSettings()
    }

    private func settingsMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.keyEquivalent == ",",
               item.keyEquivalentModifierMask.contains(.command) {
                return item
            }
            if let match = settingsMenuItem(in: item.submenu) {
                return match
            }
        }
        return nil
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

private extension NSToolbar.Identifier {
    static let gemmaTransMain = NSToolbar.Identifier("com.gemmatrans.main-toolbar")
}

private extension NSToolbarItem.Identifier {
    static let engineStatus = NSToolbarItem.Identifier("com.gemmatrans.engine-status")
    static let settings = NSToolbarItem.Identifier("com.gemmatrans.settings")
}

private struct MainToolbarStatus: View {
    let controller: EngineController

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusTint)
                .frame(width: 6, height: 6)
            Text(statusTitle)
                .fontWeight(.medium)
        }
        .font(.caption)
        .foregroundStyle(GTGlassPalette.secondaryText)
        // The native toolbar supplies the group's trailing control padding. The hosted
        // status view only compensates the leading edge and the inter-item handoff.
        .padding(.leading, GTGlassTokens.Space.s)
        .padding(.trailing, 0)
        .frame(height: 22)
        .fixedSize()
        .help(controller.activeModelName)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("引擎状态：\(statusTitle)")
    }

    private var statusTitle: String {
        switch controller.engineStatus {
        case .needsModel:
            return "选择模型"
        case .ready:
            return "就绪"
        case .loading:
            return "正在加载"
        case .downloading(let progress):
            return "下载中 \(Int(progress.fraction * 100))%"
        case .failed:
            return "需要处理"
        }
    }

    private var statusTint: Color {
        switch controller.engineStatus {
        case .needsModel: return GTGlassPalette.secondaryText
        case .ready: return GTGlassPalette.semanticGreen
        case .loading: return GTGlassPalette.semanticOrange
        case .downloading: return GTGlassPalette.controlAccent
        case .failed: return GTGlassPalette.semanticOrange
        }
    }
}

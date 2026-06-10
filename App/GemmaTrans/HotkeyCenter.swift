import AppKit
import KeyboardShortcuts
import GemmaTransKit

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("translateSelection", default: .init(.d, modifiers: [.option]))
}

@MainActor
enum HotkeyCenter {
    static func install(controller: EngineController) {
        KeyboardShortcuts.onKeyUp(for: .translateSelection) {
            Task { await handle(controller: controller) }
        }
    }

    static func handle(controller: EngineController) async {
        guard SelectionReader.hasAccessibilityPermission else {
            SelectionReader.promptForPermission()
            return
        }
        guard controller.engineStatus == .ready, let engine = controller.engine else {
            NSSound.beep()
            return
        }
        guard let text = await SelectionReader.read(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            TranslationPanel.shared.showMessage("未检测到选中文本")
            return
        }
        TranslationPanel.shared.show(text: text, engine: engine)
    }
}

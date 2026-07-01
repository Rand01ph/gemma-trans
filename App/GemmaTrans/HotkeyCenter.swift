import AppKit
import KeyboardShortcuts
import GemmaTransKit

extension KeyboardShortcuts.Name {
    // 名字字符串保持 "translateSelection" 不变：用户此前录制的快捷键按此键持久化，
    // 改键会丢用户设置。语义已从「读取选中」变为「翻译剪贴板」。
    static let translateSelection = Self("translateSelection", default: .init(.d, modifiers: [.option]))
}

@MainActor
enum HotkeyCenter {
    static func install() {
        KeyboardShortcuts.onKeyUp(for: .translateSelection) {
            Task { @MainActor in handle() }
        }
    }

    /// 热键翻译剪贴板内容（无需任何系统权限：用户先复制，再按热键）。
    static func handle() {
        let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        GTLog.info("hotkey translate requested chars=\(text.count)")
        guard !text.isEmpty else {
            GTLog.info("hotkey translate ignored empty clipboard")
            TranslationPanel.shared.showMessage("剪贴板为空——先复制要翻译的文字")
            return
        }
        ServicesProvider.translate(text)
    }
}

import AppKit
import ApplicationServices

enum SelectionReader {
    /// 读取当前前台 app 的选中文本。先 AX，失败则模拟 ⌘C（保存并恢复剪贴板）。
    static func read() async -> String? {
        if let s = axSelectedText(), !s.isEmpty { return s }
        return await copySelectedText()
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func promptForPermission() {
        let opts = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
              let text = selectedRef as? String else { return nil }
        return text
    }

    private static func copySelectedText() async -> String? {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        let beforeCount = pasteboard.changeCount

        // 模拟 ⌘C
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)  // kVK_ANSI_C
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // 最多等 300ms 剪贴板变化
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(50))
            if pasteboard.changeCount != beforeCount { break }
        }
        let text = pasteboard.changeCount != beforeCount ? pasteboard.string(forType: .string) : nil

        // 恢复剪贴板
        pasteboard.clearContents()
        pasteboard.writeObjects(savedItems)
        return text
    }
}

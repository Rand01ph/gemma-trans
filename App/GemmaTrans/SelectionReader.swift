import AppKit
import GemmaTransKit

/// 选中文本捕获——无需「辅助功能」权限。
///
/// 旧版用 AXSelectedText / 模拟 ⌘C（CGEvent）读取前台 app 的选中文本，二者都依赖
/// 「辅助功能」权限，被 App Review 2.4.5 否决（辅助功能仅限无障碍用途）。本版彻底
/// 移除该路径，改用两条用户主动发起、零权限的通道：
///   1. macOS「服务」菜单：用户选中文字后从服务菜单触发，系统把选中文本放进
///      NSPasteboard 交给本 provider（可在 系统设置 › 键盘 › 键盘快捷键 › 服务 指定快捷键）。
///   2. 剪贴板热键（见 HotkeyCenter）：用户先复制，再按热键翻译剪贴板内容。
///
/// NSServices 在 Info.plist 声明，NSMessage = "translateSelection" 指向下方方法。
/// provider 实例由 AppDelegate 注册到 NSApp.servicesProvider。
final class ServicesProvider: NSObject {
    /// 服务菜单回调：系统在主线程把选中文本放进 pboard 调用本方法。
    @objc func translateSelection(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let text = pboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Task { @MainActor in
            GTLog.info("service translate requested chars=\(text.count)")
            guard !text.isEmpty else {
                TranslationPanel.shared.showMessage("未检测到选中文本")
                return
            }
            ServicesProvider.translate(text)
        }
    }

    /// 公共入口：非空文本交引擎，在鼠标旁浮窗流式显示。引擎未就绪时给提示。
    /// 服务菜单与剪贴板热键共用此方法。
    @MainActor
    static func translate(_ text: String) {
        let controller = EngineController.shared
        guard controller.engineStatus == .ready, let engine = controller.engine else {
            GTLog.info("translate request blocked: engine not ready chars=\(text.count)")
            TranslationPanel.shared.showMessage("模型尚未就绪，请稍候")
            return
        }
        GTLog.info("translate request accepted chars=\(text.count)")
        TranslationPanel.shared.show(text: text, engine: engine)
    }
}

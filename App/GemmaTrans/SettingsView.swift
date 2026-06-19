import SwiftUI
import AppKit
import GemmaTransKit
import KeyboardShortcuts

struct SettingsView: View {
    @State private var settings = AppSettings.load()
    @State private var saved = false

    var body: some View {
        Form {
            Section("模型") {
                LabeledContent("当前模型", value: "Gemma 4 (4-bit · 按内存自动选 E4B/E2B)")
                Text("首次启动自动下载（E4B 约 4.9GB / E2B 约 3.6GB，按内存自动选），支持断点续传。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("使用国内源（ModelScope）下载模型", isOn: $settings.useCNSource)
                Text("国内网络无法直连 HuggingFace 时开启；切换后下次下载生效")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("翻译") {
                TextField("中文翻译为（语言代码）", text: $settings.targetForChinese)
                TextField("其他语言翻译为", text: $settings.targetDefault)
            }
            Section("API") {
                Toggle("启用本地 API（PopClip 等外部工具需要）", isOn: Binding(
                    get: { EngineController.shared.settings.apiEnabled },
                    set: { EngineController.shared.setAPIEnabled($0) }
                ))
                TextField("端口", value: $settings.port, format: .number.grouping(.never))
            }
            Section("性能") {
                Toggle("自动配置（按内存推荐）", isOn: $settings.autoTuning)
                if settings.autoTuning {
                    let auto = EngineTuning.recommended(
                        physicalMemory: SystemMemory.physical(),
                        availableMemory: SystemMemory.available()
                    )
                    Text("当前推荐：\(auto.variant == .gemma4E4B4bit ? "E4B" : "E2B") · 生成上限 \(auto.maxTokens) tokens · 输入上限 \(auto.maxInputChars) 字符")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("生成上限 (tokens)", value: $settings.manualMaxTokens,
                              format: .number.grouping(.never))
                    TextField("输入上限（字符）", value: $settings.maxInputChars,
                              format: .number.grouping(.never))
                }
            }
            Section("快捷键") {
                KeyboardShortcuts.Recorder("翻译剪贴板（先复制，再按）", name: .translateSelection)

                LabeledContent("划词翻译（选中即译）") {
                    HStack(spacing: 8) {
                        Text(Self.serviceShortcutGlyphs).foregroundStyle(.secondary)
                        Button("打开键盘快捷键设置…") { Self.openServicesShortcutSettings() }
                            .buttonStyle(.link)
                    }
                }
                Text("""
                「划词翻译」由 macOS「服务」提供：选中文字后直接按快捷键即可翻译，无需先复制。

                首次使用：默认快捷键是 \(Self.serviceShortcutGlyphs)，但 macOS 不一定会自动启用它。若按了没反应，点上面「打开键盘快捷键设置…」，在左侧选「服务」（系统不会自动停在这一页，需手动点进去），找到 Translate with GemmaTrans，勾选并确认它的快捷键即可——设一次就长期生效。
                """)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("保存（重启 app 生效）") {
                // API 开关即时生效且由 EngineController 持有真值，防止本视图的陈旧副本覆盖
                settings.apiEnabled = EngineController.shared.settings.apiEnabled
                settings.save()
                saved = true
            }
            if saved { Text("已保存").foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }

    /// 从自身 Info.plist 的 NSServices 声明读取「划词翻译」服务的默认快捷键，转成符号（如 ⌥⌘T）。
    /// 沙盒内无法读取系统 pbs 里用户改后的实际绑定，故展示声明的默认值。
    static var serviceShortcutGlyphs: String {
        guard let services = Bundle.main.infoDictionary?["NSServices"] as? [[String: Any]],
              let keyEq = services.first?["NSKeyEquivalent"] as? [String: String],
              let def = keyEq["default"] else { return "⌥⌘T" }
        var out = ""
        for ch in def {
            switch ch {
            case "@": out += "⌘"
            case "~": out += "⌥"
            case "$": out += "⇧"
            case "^": out += "⌃"
            default: out += String(ch).uppercased()
            }
        }
        return out
    }

    /// 打开 系统设置 ›「键盘快捷键」（服务快捷键归系统管理，沙盒 app 不能代写）。
    static func openServicesShortcutSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}

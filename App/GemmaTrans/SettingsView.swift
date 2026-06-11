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
                Text("首次启动自动从 Hugging Face 下载（约 1.5–2.4GB）。国内网络可在启动前设置 HF_ENDPOINT 镜像。")
                    .font(.caption).foregroundStyle(.secondary)
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
            Section("热键") {
                KeyboardShortcuts.Recorder("划词翻译", name: .translateSelection)
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
}

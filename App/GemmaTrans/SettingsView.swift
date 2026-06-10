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
                HStack {
                    TextField("模型路径", text: $settings.modelPath)
                    Button("选择…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.modelPath = url.path
                        }
                    }
                }
                Link("下载 Gemma 4 E4B (.litertlm)",
                     destination: URL(string: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm")!)
            }
            Section("翻译") {
                TextField("中文翻译为（语言代码）", text: $settings.targetForChinese)
                TextField("其他语言翻译为", text: $settings.targetDefault)
            }
            Section("API") {
                TextField("端口", value: $settings.port, format: .number.grouping(.never))
            }
            Section("热键") {
                KeyboardShortcuts.Recorder("划词翻译", name: .translateSelection)
            }
            Button("保存（重启 app 生效）") {
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

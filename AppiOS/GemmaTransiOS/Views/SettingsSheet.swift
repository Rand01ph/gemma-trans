import SwiftUI
import GemmaTransKit

/// 设置 sheet（spec 3.7）：目标语言、模型、系统集成、关于。
/// 读写 AppSettings.load/save(suiteName: ModelStore.settingsSuite)（App Group 共享）。
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var holder = EngineHolder.shared

    /// 目标语言两项（与 AppSettings.targetForChinese / targetDefault 对应）
    @State private var targetForChinese = "en"
    @State private var targetDefault = "zh-Hans"
    /// 国内源开关：与 onboarding 共用同一 @AppStorage key
    @AppStorage(ModelStore.sourceKey, store: UserDefaults(suiteName: ModelStore.settingsSuite))
    private var useCNSource = false

    /// 中文译为：英/日/韩等常见目标
    private let chineseTargets: [(String, String)] = [
        ("en", "English"), ("ja", "日本語"), ("ko", "한국어"),
        ("fr", "Français"), ("de", "Deutsch"),
    ]
    /// 其他语言译为：简/繁中文
    private let defaultTargets: [(String, String)] = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("目标语言") {
                    Picker("中文译为", selection: $targetForChinese) {
                        ForEach(chineseTargets, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("其他语言译为", selection: $targetDefault) {
                        ForEach(defaultTargets, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }

                Section("模型") {
                    LabeledContent("Gemma 4 E2B") {
                        Text(modelStatusText)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("使用国内源", isOn: $useCNSource)
                    Text("重新下载时生效（ModelScope 魔搭）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("系统集成") {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Text("设为系统翻译 App")
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                }

                Section("关于") {
                    LabeledContent("版本") {
                        Text("\(appVersion) · 完全离线运行")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save(); dismiss() }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    private var modelStatusText: String {
        holder.status == .ready ? "已就绪 · 3.6 GB" : "3.6 GB"
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }

    private func load() {
        let s = AppSettings.load(suiteName: ModelStore.settingsSuite)
        targetForChinese = s.targetForChinese
        targetDefault = s.targetDefault
    }

    private func save() {
        var s = AppSettings.load(suiteName: ModelStore.settingsSuite)
        s.targetForChinese = targetForChinese
        s.targetDefault = targetDefault
        s.useCNSource = useCNSource
        s.save(suiteName: ModelStore.settingsSuite)
    }
}

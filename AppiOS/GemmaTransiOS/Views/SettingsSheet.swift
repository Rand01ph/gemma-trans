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

    /// 一键导入的快递短信快捷指令模板（iCloud 分享链接）。
    /// ⚠️ 临时链接，依赖分享者账号与原快捷指令存续；正式发版应换为开发者维护的
    /// 稳定托管或随包分发的 .shortcut 文件。
    private static let templateShortcutURL =
        "https://www.icloud.com/shortcuts/a7f07bbf9b8f45d6a5946006b49bef85"

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

                    Button {
                        if let url = URL(string: Self.templateShortcutURL) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("获取快递短信快捷指令模板")
                                Text("一键导入，省去手动搭动作链")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.down")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)

                    // 取舍：设计文档允许「Link 到 GitHub 仓库文档」或「内嵌简版」。
                    // 选内嵌——GitHub Link 虽只一行，但文档未合入 main 前是 404，
                    // 且离线优先的 app 跳网页体验割裂；内嵌简版离线可读。
                    // 完整图文版见仓库 docs/shortcuts-guide.md（改动时同步这里）。
                    NavigationLink("快捷指令配置指引") {
                        ShortcutsGuideView()
                    }
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

// MARK: - 快捷指令配置指引（内嵌简版，全文见 docs/shortcuts-guide.md）

/// 首发场景「快递短信 → 提醒事项」的逐步配置 + 已知限制。
private struct ShortcutsGuideView: View {
    var body: some View {
        List {
            Section {
                step(1, "快捷指令 app → 自动化 → 新建，触发器选「信息」")
                step(2, "「信息包含」必须填关键词（如 快递）——iOS 实测：留空不触发任何短信；发件人那行别碰")
                step(3, "勾选「立即运行」→ 完成（不开则每次弹横幅等手动确认）")
                step(4, "加动作 GemmaTrans「本地 AI 处理」：文本选「快捷指令的信息」，任务选「快递取件提取」")
                step(5, "加「如果」：本地 AI 处理结果「包含」「无」→ 分支内放「停止此快捷指令」")
                step(6, "加「添加提醒事项」：标题选「本地 AI 处理的结果」（别选「如果的结果」，那个是空的）")
            } header: {
                Text("手动配置（约 3 分钟）")
            } footer: {
                Text("嫌麻烦？设置里「获取快递短信快捷指令模板」可一键导入动作链，只需自己建个「信息」触发器填关键词。任务库里保存的自定义任务也会出现在「任务」下拉里。")
            }

            Section("已知限制") {
                Label("短信无法自动标记已读（iOS 不开放）", systemImage: "envelope.badge")
                Label("只能读到触发那条短信，不能扫历史", systemImage: "clock.arrow.circlepath")
                Label("首次触发后台加载模型约 3 秒，无人等待场景基本无感", systemImage: "hourglass")
            }
            .symbolRenderingMode(.hierarchical)
        }
        .navigationTitle("快捷指令配置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text)
        }
        .padding(.vertical, 2)
    }
}

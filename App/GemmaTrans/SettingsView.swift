import SwiftUI
import AppKit
import GemmaTransKit
import KeyboardShortcuts

struct SettingsView: View {
    @State private var settings = AppSettings.load()
    @State private var saved = false
    @State private var switchBlockMessage: String? = nil
    @State private var installed: [InstalledModel] = []

    var body: some View {
        Form {
            modelSection
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
        .onAppear { installed = EngineController.shared.installedModels() }
        .onChange(of: EngineController.shared.engineStatus) { _, _ in
            installed = EngineController.shared.installedModels()
        }
        // 被阻止时弹 alert（移到 Form 顶层以避免 Section 嵌套限制）
        .alert("无法切换模型", isPresented: Binding(
            get: { switchBlockMessage != nil },
            set: { if !$0 { switchBlockMessage = nil } }
        )) {
            Button("好") { switchBlockMessage = nil }
        } message: {
            Text(switchBlockMessage ?? "")
        }
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

    // MARK: - Model Section

    /// 当前引擎是否处于"切换禁止"状态（加载中 / 下载中）。
    private var isEngineBusy: Bool {
        switch EngineController.shared.engineStatus {
        case .loading, .downloading: return true
        default: return false
        }
    }

    /// 切换/下载按钮禁用规则：仅引擎忙（加载/下载中）时禁用。
    /// API 运行不再阻断切换——切换会自动重启 API 指向新引擎；在飞翻译由引擎串行队列守住。
    private var switchDisabled: Bool { isEngineBusy }

    /// 将字节数格式化为 "X.X GB"（接受 UInt64 或 Int64）。
    private func formatGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return String(format: "%.1f GB", gb)
    }

    private func formatGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return String(format: "%.1f GB", gb)
    }

    /// 触发 switchModel 并在被阻止时展示提示。
    private func trySwitchModel(to id: String) {
        Task {
            if let block = await EngineController.shared.switchModel(to: id) {
                switchBlockMessage = block.message
            }
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        let ec = EngineController.shared
        let installedIDs = Set(installed.map(\.id))
        let selectedID = ec.selectedModelID

        Section("模型") {
            // ── 引擎状态行 ────────────────────────────────────────────────────
            engineStatusRow

            // ── Auto 行 ────────────────────────────────────────────────────────
            let autoActive = selectedID == ModelCatalog.autoID
            LabeledContent {
                HStack(spacing: 8) {
                    if autoActive {
                        Text("活跃")
                            .font(.caption).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Button("设为活跃") { trySwitchModel(to: ModelCatalog.autoID) }
                            .disabled(switchDisabled)
                            .help(isEngineBusy ? "引擎忙（加载/下载中），请稍候再切换" : "")
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto（按内存自动选 Gemma）")
                    Text("E4B ≈ 4.9 GB / E2B ≈ 3.6 GB，按可用内存自动选").font(.caption).foregroundStyle(.secondary)
                }
            }

            // ── Catalog 条目行 ────────────────────────────────────────────────
            ForEach(ModelCatalog.entries) { entry in
                let isActive = selectedID == entry.id
                let isInstalled = installedIDs.contains(entry.id)

                LabeledContent {
                    HStack(spacing: 8) {
                        if isActive {
                            Text("活跃")
                                .font(.caption).bold()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            // 删除按钮：活跃模型禁用
                            Button("删除") { }
                                .disabled(true)
                        } else if isInstalled {
                            Button("设为活跃") { trySwitchModel(to: entry.id) }
                                .disabled(switchDisabled)
                                .help(isEngineBusy ? "引擎忙（加载/下载中），请稍候再切换" : "")
                            Button("删除") {
                                ec.deleteModel(id: entry.id)
                                installed = EngineController.shared.installedModels()
                            }
                            .disabled(isEngineBusy)
                        } else {
                            // 未下载
                            Button("下载并使用") { trySwitchModel(to: entry.id) }
                                .disabled(switchDisabled)
                                .help(isEngineBusy ? "引擎忙（加载/下载中），请稍候再切换" : "")
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName)
                        Text(formatGB(entry.estimatedBytes)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // ── 下载源开关 ────────────────────────────────────────────────────
            Toggle("使用国内源（ModelScope）下载模型", isOn: $settings.useCNSource)
            Text("国内网络无法直连 HuggingFace 时开启；切换后下次下载生效")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// 引擎状态展示行：下载中显示进度，失败时显示错误，加载中/就绪简短提示。
    @ViewBuilder
    private var engineStatusRow: some View {
        let status = EngineController.shared.engineStatus
        switch status {
        case .ready:
            EmptyView()
        case .loading(let msg):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                let pct = Int(progress.fraction * 100)
                if let total = progress.totalBytes, let done = progress.completedBytes {
                    Text("下载中 \(pct)% · \(formatGB(done)) / \(formatGB(total))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("下载中 \(pct)%").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red)
        }
    }
}

import AppKit
import SwiftUI
import GemmaTransKit
import KeyboardShortcuts

struct SettingsView: View {
    var embedded = false

    @State private var settings = AppSettings.load()
    @State private var saved = false
    @State private var switchBlockMessage: String?
    @State private var installed: [InstalledModel] = []
    @State private var appearanceStore = GTAppearanceStore.shared

    var body: some View {
        ZStack {
            if !embedded { GTContentBackground() }
            ScrollView {
                VStack(alignment: .leading, spacing: GTGlassTokens.Space.l) {
                    header
                    appearanceSection
                    modelSection
                    translationSection
                    apiSection
                    performanceSection
                    shortcutsSection
                    saveSection
                }
                .padding(embedded ? GTGlassTokens.Window.contentInset : GTGlassTokens.Space.xl)
                .frame(maxWidth: embedded ? .infinity : GTGlassTokens.Panel.settingsWidth)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .frame(width: embedded ? nil : GTGlassTokens.Panel.settingsWidth,
               height: embedded ? nil : GTGlassTokens.Panel.settingsHeight)
        .gtApplicationAppearance()
        .onAppear {
            settings = AppSettings.load()
            installed = EngineController.shared.installedModels()
            appearanceStore.reloadFromDefaults()
        }
        .onChange(of: EngineController.shared.engineStatus) { _, _ in
            installed = EngineController.shared.installedModels()
        }
        .onChange(of: EngineController.shared.downloadingModelID) { _, _ in
            installed = EngineController.shared.installedModels()
        }
        .alert("无法切换模型", isPresented: Binding(
            get: { switchBlockMessage != nil },
            set: { if !$0 { switchBlockMessage = nil } }
        )) {
            Button("好") { switchBlockMessage = nil }
        } message: {
            Text(switchBlockMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: GTGlassTokens.Space.m) {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .frame(width: GTGlassTokens.Icon.chip, height: GTGlassTokens.Icon.chip)
                .gtGlassSurface(.flat,
                                cornerRadius: GTGlassTokens.Radius.control,
                                fill: GTGlassPalette.warmNeutral,
                                fillOpacity: 0.22,
                                gradient: true,
                                stroke: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.title3.weight(.semibold))
                Text("模型、翻译、API、性能和快捷键")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, GTGlassTokens.Space.xs)
    }

    private var appearanceSection: some View {
        GTPanelSection(title: "外观", subtitle: "默认跟随系统，也可以固定浅色或深色。") {
            GTPanelField(label: "显示模式") {
                Picker("显示模式", selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
        }
    }

    private var translationSection: some View {
        GTPanelSection(title: "翻译", subtitle: "语言代码会在下次翻译时生效。") {
            GTPanelField(label: "中文翻译为") {
                glassTextField("en", text: $settings.targetForChinese)
            }
            GTPanelDivider()
            GTPanelField(label: "其他语言翻译为") {
                glassTextField("zh-Hans", text: $settings.targetDefault)
            }
        }
    }

    private var apiSection: some View {
        GTPanelSection(title: "本地 API", subtitle: "PopClip 等外部工具可通过本地服务调用翻译。") {
            GTPanelToggleRow(title: "启用本地 API",
                             subtitle: apiSubtitle,
                             isOn: Binding(
                                get: { EngineController.shared.settings.apiEnabled },
                                set: { EngineController.shared.setAPIEnabled($0) }
                             ))
            GTPanelDivider()
            GTPanelField(label: "端口") {
                glassNumberField(value: $settings.port)
                    .frame(maxWidth: 110, alignment: .leading)
            }
        }
    }

    private var performanceSection: some View {
        GTPanelSection(title: "性能", subtitle: "自动模式会按内存选择模型和输入/输出上限。") {
            GTPanelToggleRow(title: "自动配置",
                             subtitle: autoTuningSubtitle,
                             isOn: $settings.autoTuning)
            if !settings.autoTuning {
                GTPanelDivider()
                GTPanelField(label: "生成上限") {
                    glassNumberField(value: $settings.manualMaxTokens)
                        .frame(maxWidth: 140, alignment: .leading)
                }
                GTPanelDivider()
                GTPanelField(label: "输入上限") {
                    glassNumberField(value: $settings.maxInputChars)
                        .frame(maxWidth: 140, alignment: .leading)
                }
            }
        }
    }

    private var shortcutsSection: some View {
        GTPanelSection(title: "快捷键", subtitle: "剪贴板快捷键由 app 管理；划词翻译由 macOS 服务管理。") {
            GTPanelRow(title: "翻译剪贴板", subtitle: "先复制，再按快捷键。") {
                KeyboardShortcuts.Recorder("", name: .translateSelection)
                    .labelsHidden()
            }
            GTPanelDivider()
            GTPanelRow(title: "划词翻译", subtitle: "选中文字后按服务快捷键。") {
                HStack(spacing: GTGlassTokens.Space.s) {
                    Text(Self.serviceShortcutGlyphs)
                        .font(.callout.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                    GTGlassButton("打开设置", systemImage: "keyboard") {
                        Self.openServicesShortcutSettings()
                    }
                }
            }
            Text("首次使用若按了没反应，请在系统设置的「键盘快捷键 > 服务」中勾选 Translate with GemmaTrans。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var saveSection: some View {
        HStack(spacing: GTGlassTokens.Space.m) {
            GTGlassButton("保存设置", systemImage: "checkmark.circle.fill", prominent: true) {
                save()
            }
            if saved {
                Text("已保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
        }
        .padding(.horizontal, GTGlassTokens.Space.xs)
    }

    private var modelSection: some View {
        let ec = EngineController.shared
        let installedIDs = Set(installed.map(\.id))
        let selectedID = ec.selectedModelID

        return GTPanelSection(title: "模型", subtitle: "下载模型不会切换当前模型；设为活跃会重新加载引擎。") {
            engineStatusRow

            if ec.engineStatus != .ready {
                GTPanelDivider()
            }

            modelRow(title: "Auto（按内存自动选 Gemma）",
                     subtitle: "E4B 约 4.9 GB / E2B 约 3.6 GB，按可用内存自动选。",
                     active: selectedID == ModelCatalog.autoID,
                     tps: ec.lastTokensPerSecond[ModelCatalog.autoID]) {
                trySwitchModel(to: ModelCatalog.autoID)
            }

            ForEach(ModelCatalog.entries) { entry in
                GTPanelDivider()
                catalogRow(entry, installedIDs: installedIDs)
            }

            GTPanelDivider()
            GTPanelToggleRow(title: "使用国内源（ModelScope）",
                             subtitle: "国内网络无法直连 HuggingFace 时开启；切换后下次下载生效。",
                             isOn: $settings.useCNSource)
        }
    }

    @ViewBuilder
    private var engineStatusRow: some View {
        switch EngineController.shared.engineStatus {
        case .ready:
            GTPanelRow(title: "引擎状态", subtitle: "就绪 · \(EngineController.shared.activeModelName)") {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .loading(let message):
            GTPanelRow(title: "引擎状态", subtitle: message) {
                ProgressView().controlSize(.small)
            }
        case .downloading(let progress):
            GTPanelRow(title: "引擎状态", subtitle: downloadText(progress)) {
                ProgressView(value: progress.fraction)
                    .frame(width: 96)
            }
        case .failed(let message):
            GTPanelRow(title: "引擎状态", subtitle: message) {
                GTGlassButton("重试", systemImage: "arrow.clockwise") {
                    EngineController.shared.reload()
                }
            }
        }
    }

    private var isEngineBusy: Bool {
        switch EngineController.shared.engineStatus {
        case .loading, .downloading: return true
        default: return false
        }
    }

    private var switchDisabled: Bool { isEngineBusy }

    private var apiSubtitle: String {
        switch EngineController.shared.apiStatus {
        case .disabled:
            return "已关闭。"
        case .running(let port):
            return "正在 127.0.0.1:\(port) 监听。"
        case .failed(let message):
            return message
        }
    }

    private var autoTuningSubtitle: String {
        guard settings.autoTuning else { return "关闭后使用下面的手动上限。" }
        let auto = EngineTuning.recommended(
            physicalMemory: SystemMemory.physical(),
            availableMemory: SystemMemory.available()
        )
        let variant = auto.variant == .gemma4E4B4bit ? "E4B" : "E2B"
        return "当前推荐：\(variant) · 生成上限 \(auto.maxTokens) tokens · 输入上限 \(auto.maxInputChars) 字符。"
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding {
            settings.appearance
        } set: { newValue in
            settings.appearance = newValue
            settings.save()
            appearanceStore.set(newValue, persist: false)
        }
    }

    private func catalogRow(_ entry: ModelCatalogEntry, installedIDs: Set<String>) -> some View {
        let ec = EngineController.shared
        let isActive = ec.selectedModelID == entry.id
        let isInstalled = installedIDs.contains(entry.id)
        let subtitle = "\(formatGB(entry.estimatedBytes)) · \(entry.repo)"

        return modelRow(title: entry.displayName,
                        subtitle: subtitle,
                        active: isActive,
                        installed: isInstalled,
                        downloading: ec.downloadingModelID == entry.id,
                        downloadProgress: ec.downloadProgress,
                        tps: ec.lastTokensPerSecond[entry.id],
                        switchAction: { trySwitchModel(to: entry.id) },
                        downloadAction: { ec.downloadModel(id: entry.id) },
                        deleteAction: {
                            ec.deleteModel(id: entry.id)
                            installed = EngineController.shared.installedModels()
                        })
    }

    private func modelRow(title: String,
                          subtitle: String,
                          active: Bool,
                          installed: Bool = true,
                          downloading: Bool = false,
                          downloadProgress: DownloadProgress? = nil,
                          tps: Double? = nil,
                          switchAction: @escaping () -> Void,
                          downloadAction: (() -> Void)? = nil,
                          deleteAction: (() -> Void)? = nil) -> some View {
        GTPanelRow(title: title, subtitle: subtitle) {
            HStack(spacing: GTGlassTokens.Space.s) {
                if active {
                    GTActiveBadge()
                    if let tps {
                        Text(String(format: "%.1f tok/s", tps))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if downloading {
                    Text("下载中 \(Int((downloadProgress?.fraction ?? 0) * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if installed {
                    GTGlassButton("设为活跃", systemImage: "bolt.fill") {
                        switchAction()
                    }
                    .disabled(switchDisabled)
                    if let deleteAction {
                        GTGlassButton("删除", systemImage: "trash", role: .destructive) {
                            deleteAction()
                        }
                        .disabled(isEngineBusy)
                    }
                } else if let downloadAction {
                    GTGlassButton("下载", systemImage: "arrow.down.circle") {
                        downloadAction()
                    }
                    .disabled(EngineController.shared.downloadingModelID != nil)
                }
            }
        }
    }

    private func save() {
        settings.apiEnabled = EngineController.shared.settings.apiEnabled
        settings.save()
        appearanceStore.set(settings.appearance, persist: false)
        withAnimation(.easeOut(duration: 0.18)) { saved = true }
    }

    private func trySwitchModel(to id: String) {
        Task {
            if let block = await EngineController.shared.switchModel(to: id) {
                switchBlockMessage = block.message
            }
        }
    }

    private func glassTextField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, GTGlassTokens.Space.s)
            .frame(height: 30)
            .gtGlassSurface(.flat,
                            cornerRadius: GTGlassTokens.Radius.control,
                            fill: GTGlassPalette.innerNeutral,
                            fillOpacity: 0.10,
                            gradient: false)
    }

    private func glassNumberField(value: Binding<Int>) -> some View {
        TextField("", value: value, format: .number.grouping(.never))
            .textFieldStyle(.plain)
            .padding(.horizontal, GTGlassTokens.Space.s)
            .frame(height: 30)
            .gtGlassSurface(.flat,
                            cornerRadius: GTGlassTokens.Radius.control,
                            fill: GTGlassPalette.innerNeutral,
                            fillOpacity: 0.10,
                            gradient: false)
    }

    private func glassNumberField(value: Binding<UInt16>) -> some View {
        TextField("", value: value, format: .number.grouping(.never))
            .textFieldStyle(.plain)
            .padding(.horizontal, GTGlassTokens.Space.s)
            .frame(height: 30)
            .gtGlassSurface(.flat,
                            cornerRadius: GTGlassTokens.Radius.control,
                            fill: GTGlassPalette.innerNeutral,
                            fillOpacity: 0.10,
                            gradient: false)
    }

    private func formatGB(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    private func formatGB(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    private func downloadText(_ progress: DownloadProgress) -> String {
        let pct = Int(progress.fraction * 100)
        guard let total = progress.totalBytes, let done = progress.completedBytes else {
            return "下载中 \(pct)%"
        }
        return "下载中 \(pct)% · \(formatGB(done)) / \(formatGB(total))"
    }

    /// 从自身 Info.plist 的 NSServices 声明读取「划词翻译」服务的默认快捷键，转成符号（如 ⌥⌘T）。
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

    /// 打开 系统设置 > 键盘快捷键。服务快捷键归系统管理，沙盒 app 不能代写。
    static func openServicesShortcutSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }
}

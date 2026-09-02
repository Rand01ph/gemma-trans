import AppKit
import SwiftUI
import GemmaTransKit
import KeyboardShortcuts

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case models
    case integrations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .models: return "模型"
        case .integrations: return "集成"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .models: return "cpu"
        case .integrations: return "point.3.connected.trianglepath.dotted"
        }
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general
    @State private var settings: AppSettings
    @State private var targetForChineseText: String
    @State private var targetDefaultText: String
    @State private var portText: String
    @State private var targetForChineseError: String?
    @State private var targetDefaultError: String?
    @State private var portError: String?
    @State private var switchBlockMessage: String?
    @State private var pendingModelDeletion: ModelCatalogEntry?
    @State private var installed: [InstalledModel] = []
    @State private var appearanceStore = GTAppearanceStore.shared
    @State private var targetForChineseTask: Task<Void, Never>?
    @State private var targetDefaultTask: Task<Void, Never>?
    @State private var portTask: Task<Void, Never>?

    init() {
        let loaded = AppSettings.load()
#if DEBUG
        _selectedSection = State(initialValue: GTDebugScreenshotFixture.settingsSection ?? .general)
#endif
        _settings = State(initialValue: loaded)
        _targetForChineseText = State(initialValue: loaded.targetForChinese)
        _targetDefaultText = State(initialValue: loaded.targetDefault)
        _portText = State(initialValue: String(loaded.port))
    }

    var body: some View {
        ZStack {
            GTContentBackground()
            TabView(selection: $selectedSection) {
                settingsPage(title: "通用", subtitle: "外观、翻译方向和本机性能配置。") {
                    appearanceSection
                    translationSection
                    performanceSection
                }
                .tabItem { Label(SettingsSection.general.title, systemImage: SettingsSection.general.symbol) }
                .tag(SettingsSection.general)

                settingsPage(title: "模型", subtitle: "下载、切换和管理本地模型。") {
                    modelSection
                }
                .tabItem { Label(SettingsSection.models.title, systemImage: SettingsSection.models.symbol) }
                .tag(SettingsSection.models)

                settingsPage(title: "集成", subtitle: "本地 API、快捷键和 macOS 服务。") {
                    apiSection
                    shortcutsSection
                }
                .tabItem { Label(SettingsSection.integrations.title, systemImage: SettingsSection.integrations.symbol) }
                .tag(SettingsSection.integrations)
            }
            .padding(.top, GTGlassTokens.Space.s)
        }
        .frame(width: GTGlassTokens.Panel.settingsWidth,
               height: GTGlassTokens.Panel.settingsHeight)
        .background(SettingsWindowReader())
        .gtApplicationAppearance()
        .onAppear(perform: reloadSettings)
        .onChange(of: EngineController.shared.engineStatus) { _, _ in refreshInstalledModels() }
        .onChange(of: EngineController.shared.downloadingModelID) { _, _ in refreshInstalledModels() }
        .onDisappear {
            targetForChineseTask?.cancel()
            targetDefaultTask?.cancel()
            portTask?.cancel()
        }
        .alert("无法切换模型", isPresented: Binding(
            get: { switchBlockMessage != nil },
            set: { if !$0 { switchBlockMessage = nil } }
        )) {
            Button("好") { switchBlockMessage = nil }
        } message: {
            Text(switchBlockMessage ?? "")
        }
        .alert("删除模型？", isPresented: Binding(
            get: { pendingModelDeletion != nil },
            set: { if !$0 { pendingModelDeletion = nil } }
        )) {
            Button("取消", role: .cancel) { pendingModelDeletion = nil }
            Button("删除模型", role: .destructive, action: confirmModelDeletion)
        } message: {
            Text(deletionConfirmationMessage)
        }
    }

    private func settingsPage<Content: View>(title: String,
                                             subtitle: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GTGlassTokens.Space.l) {
                HStack(spacing: GTGlassTokens.Space.m) {
                    Image(systemName: selectedSection.symbol)
                        .font(.title3.weight(.semibold))
                        .frame(width: GTGlassTokens.Icon.chip, height: GTGlassTokens.Icon.chip)
                        .background {
                            RoundedRectangle(cornerRadius: GTGlassTokens.Radius.control,
                                             style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.title3.weight(.semibold))
                        Text(subtitle).font(.caption).foregroundStyle(GTGlassPalette.secondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, GTGlassTokens.Space.xs)

                content()
            }
            .padding(GTGlassTokens.Space.xl)
            .frame(maxWidth: GTGlassTokens.Panel.settingsWidth)
        }
        .gtSoftScrollEdges()
    }

    private var appearanceSection: some View {
        GTPanelSection(title: "外观") {
            GTPanelField(label: "主题") {
                Picker("主题", selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases, id: \.self) { mode in
                        Text(compactAppearanceName(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 232)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            GTPanelDivider()
            GTPanelField(label: "浮窗译文字号", subtitle: "用于划词与剪贴板翻译结果。") {
                HStack(spacing: GTGlassTokens.Space.s) {
                    Slider(value: translationFontSizeBinding,
                           in: AppSettings.minimumTranslationFontSize
                            ... AppSettings.maximumTranslationFontSize,
                           step: 1)
                        .frame(width: 148)
                        .accessibilityLabel("浮窗译文字号")
                        .accessibilityValue("\(Int(settings.translationFontSize)) 点")

                    Text("\(Int(settings.translationFontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(GTGlassPalette.secondaryText)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var translationSection: some View {
        GTPanelSection(title: "翻译", subtitle: "配置会在下次模型加载后用于新的翻译任务。") {
            GTSettingsTextFieldRow(label: "中文翻译为",
                                   prompt: "en",
                                   text: $targetForChineseText,
                                   error: targetForChineseError)
                .onChange(of: targetForChineseText) { _, value in
                    scheduleLanguageSave(value, field: .chinese)
                }
            GTPanelDivider()
            GTSettingsTextFieldRow(label: "其他语言翻译为",
                                   prompt: "zh-Hans",
                                   text: $targetDefaultText,
                                   error: targetDefaultError)
                .onChange(of: targetDefaultText) { _, value in
                    scheduleLanguageSave(value, field: .defaultTarget)
                }
        }
    }

    private var performanceSection: some View {
        GTPanelSection(title: "性能", subtitle: "参数配置不会替你选择或下载模型。") {
            GTPanelToggleRow(title: "自动配置参数",
                             subtitle: autoTuningSubtitle,
                             isOn: persistedBinding(\.autoTuning))
            if !settings.autoTuning {
                GTPanelDivider()
                GTPanelField(label: "生成上限") {
                    numberField("生成上限", value: persistedBinding(\.manualMaxTokens))
                }
                GTPanelDivider()
                GTPanelField(label: "输入上限") {
                    numberField("输入上限", value: persistedBinding(\.maxInputChars))
                }
            }
        }
    }

    private var apiSection: some View {
        GTPanelSection(title: "本地 API", subtitle: "PopClip 等外部工具可通过本地服务调用翻译。") {
            GTPanelToggleRow(title: "启用本地 API",
                             subtitle: apiSubtitle,
                             isOn: Binding(
                                get: { EngineController.shared.settings.apiEnabled },
                                set: { enabled in
                                    settings.apiEnabled = enabled
                                    EngineController.shared.setAPIEnabled(enabled)
                                }
                             ))
            GTPanelDivider()
            GTSettingsTextFieldRow(label: "端口",
                                   subtitle: "修改后在下次 API 启动时生效。",
                                   prompt: "8765",
                                   text: $portText,
                                   error: portError,
                                   usesMonospacedDigits: true)
                .onChange(of: portText) { _, value in schedulePortSave(value) }
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
                        .foregroundStyle(GTGlassPalette.secondaryText)
                    GTSettingsActionButton(title: "系统设置…") {
                        Self.openServicesShortcutSettings()
                    }
                }
            }
            Text("首次使用若按了没反应，请在系统设置的“键盘快捷键 > 服务”中勾选 Translate with GemmaTrans。")
                .font(.caption)
                .foregroundStyle(GTGlassPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, GTSettingsControlMetrics.rowVerticalPadding)
        }
    }

    private var modelSection: some View {
        let installedIDs = Set(installed.map(\.id))

        return GTPanelSection(
            title: "本地模型",
            subtitle: "下载后选择使用；Hugging Face 不可用时会自动切换 ModelScope。"
        ) {
            engineStatusRow
            GTPanelDivider()

            ForEach(ModelCatalog.entries) { entry in
                catalogRow(entry, installedIDs: installedIDs)
                if entry.id != ModelCatalog.entries.last?.id {
                    GTPanelDivider()
                }
            }
        }
    }

    @ViewBuilder
    private var engineStatusRow: some View {
        switch EngineController.shared.engineStatus {
        case .needsModel(let message):
            GTPanelRow(title: "请选择模型", subtitle: message) {
                Image(systemName: "arrow.down.circle").foregroundStyle(GTGlassPalette.secondaryText)
            }
        case .ready:
            GTPanelRow(title: "引擎状态", subtitle: "就绪 · \(EngineController.shared.activeModelName)") {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(GTGlassPalette.semanticReady)
            }
        case .loading(let message):
            GTPanelRow(title: "引擎状态", subtitle: message) { ProgressView().controlSize(.small) }
        case .downloading(let progress):
            GTPanelRow(title: "引擎状态", subtitle: downloadText(progress)) {
                ProgressView(value: progress.fraction).frame(width: 96)
            }
        case .failed(let message):
            GTPanelRow(title: "引擎状态", subtitle: message) {
                GTSettingsActionButton(title: "重试") {
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

    private var apiSubtitle: String {
        switch EngineController.shared.apiStatus {
        case .disabled: return "已关闭。"
        case .running(let port): return "正在 127.0.0.1:\(port) 监听。"
        case .failed(let message): return message
        }
    }

    private var autoTuningSubtitle: String {
        guard settings.autoTuning else { return "使用下面的手动上限，不改变当前模型。" }
        guard let selectedModelID = settings.selectedModelID,
              let entry = ModelCatalog.entry(id: selectedModelID) else {
            return "选择模型后使用该模型的建议参数。"
        }
        return "\(entry.displayName) · 生成上限 \(entry.defaultMaxTokens) tokens · 输入上限 \(entry.defaultMaxInputChars) 字符。"
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding {
            settings.appearance
        } set: { newValue in
            settings.appearance = newValue
            AppSettings.update { $0.appearance = newValue }
            appearanceStore.set(newValue, persist: false)
        }
    }

    private var translationFontSizeBinding: Binding<Double> {
        Binding {
            settings.translationFontSize
        } set: { newValue in
            let normalized = AppSettings.normalizedTranslationFontSize(newValue)
            settings.translationFontSize = normalized
            AppSettings.update { $0.translationFontSize = normalized }
        }
    }

    private func persistedBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding {
            settings[keyPath: keyPath]
        } set: { value in
            settings[keyPath: keyPath] = value
            AppSettings.update { $0[keyPath: keyPath] = value }
        }
    }

    private func catalogRow(_ entry: ModelCatalogEntry, installedIDs: Set<String>) -> some View {
        let ec = EngineController.shared
        let installed = installedIDs.contains(entry.id)
        return modelRow(title: entry.displayName,
                        subtitle: ec.modelDownloadErrors[entry.id] ?? formatBytes(entry.estimatedBytes),
                        active: installed && ec.selectedModelID == entry.id,
                        installed: installed,
                        downloading: ec.downloadingModelID == entry.id,
                        downloadProgress: ec.downloadProgress,
                        tps: ec.lastTokensPerSecond[entry.id],
                        switchAction: { trySwitchModel(to: entry.id) },
                        downloadAction: { ec.downloadModel(id: entry.id) },
                        deleteAction: {
                            pendingModelDeletion = entry
                        })
            .help("模型仓库：\(entry.repo)")
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
            modelTrailingSlot {
                if active {
                    HStack(spacing: GTGlassTokens.Space.s) {
                        if let tps {
                            Text(String(format: "%.1f tok/s", tps))
                                .font(.caption)
                                .foregroundStyle(GTGlassPalette.secondaryText)
                                .monospacedDigit()
                        }
                        GTModelStateBadge()
                        modelOverflowPlaceholder
                    }
                } else if downloading {
                    HStack(spacing: GTGlassTokens.Space.s) {
                        ProgressView(value: downloadProgress?.fraction ?? 0)
                            .frame(width: 92)
                        Text("\(Int((downloadProgress?.fraction ?? 0) * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(GTGlassPalette.secondaryText)
                            .frame(width: 34, alignment: .trailing)
                    }
                } else if installed {
                    HStack(spacing: GTGlassTokens.Space.s) {
                        GTSettingsActionButton(title: "使用",
                                               systemImage: "checkmark",
                                               action: switchAction)
                            .disabled(isEngineBusy)
                        if let deleteAction {
                            GTSettingsDestructiveIconButton(title: "删除模型…",
                                                            action: deleteAction)
                            .disabled(isEngineBusy)
                        } else {
                            modelOverflowPlaceholder
                        }
                    }
                } else if let downloadAction {
                    HStack(spacing: GTGlassTokens.Space.s) {
                        GTSettingsActionButton(title: "下载",
                                               systemImage: "arrow.down",
                                               action: downloadAction)
                            .disabled(EngineController.shared.downloadingModelID != nil)
                        modelOverflowPlaceholder
                    }
                }
            }
        }
    }

    private func modelTrailingSlot<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(width: 216,
                   height: GTSettingsControlMetrics.actionHeight,
                   alignment: .trailing)
    }

    private var modelOverflowPlaceholder: some View {
        Color.clear
            .frame(width: GTSettingsControlMetrics.iconSize,
                   height: GTSettingsControlMetrics.iconSize)
            .accessibilityHidden(true)
    }

    private var deletionConfirmationMessage: String {
        guard let entry = pendingModelDeletion else { return "" }
        return "将从本机删除“\(entry.displayName)”。需要时可以重新下载。"
    }

    private func confirmModelDeletion() {
        guard let entry = pendingModelDeletion else { return }
        pendingModelDeletion = nil
        EngineController.shared.deleteModel(id: entry.id)
        refreshInstalledModels()
    }

    private func compactAppearanceName(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .system: return "系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    private func reloadSettings() {
        let loaded = AppSettings.load()
        settings = loaded
        targetForChineseText = loaded.targetForChinese
        targetDefaultText = loaded.targetDefault
        portText = String(loaded.port)
        refreshInstalledModels()
        appearanceStore.reloadFromDefaults()
    }

    private func refreshInstalledModels() {
        installed = EngineController.shared.installedModels()
    }

    private enum LanguageField { case chinese, defaultTarget }

    private func scheduleLanguageSave(_ value: String, field: LanguageField) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let error = trimmed.isEmpty ? "语言代码不能为空。" : nil
        switch field {
        case .chinese:
            targetForChineseTask?.cancel()
            targetForChineseError = error
            guard error == nil else { return }
            targetForChineseTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                settings.targetForChinese = trimmed
                AppSettings.update { $0.targetForChinese = trimmed }
            }
        case .defaultTarget:
            targetDefaultTask?.cancel()
            targetDefaultError = error
            guard error == nil else { return }
            targetDefaultTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                settings.targetDefault = trimmed
                AppSettings.update { $0.targetDefault = trimmed }
            }
        }
    }

    private func schedulePortSave(_ value: String) {
        portTask?.cancel()
        guard let number = Int(value), (1...65535).contains(number) else {
            portError = "请输入 1–65535 之间的端口。"
            return
        }
        portError = nil
        portTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            settings.port = UInt16(number)
            AppSettings.update { $0.port = UInt16(number) }
        }
    }

    private func trySwitchModel(to id: String) {
        Task {
            if let block = await EngineController.shared.switchModel(to: id) {
                switchBlockMessage = block.message
            } else {
                settings.selectedModelID = id
            }
        }
    }

    private func numberField(_ label: String, value: Binding<Int>) -> some View {
        TextField(label, value: value, format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
            .monospacedDigit()
            .frame(width: GTSettingsControlMetrics.compactFieldWidth)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1_073_741_824 {
            return "约 \(Int((Double(bytes) / 1_048_576).rounded())) MB"
        }
        return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1_073_741_824 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    private func downloadText(_ progress: DownloadProgress) -> String {
        let pct = Int(progress.fraction * 100)
        guard let total = progress.totalBytes, let done = progress.completedBytes else {
            return "下载中 \(pct)%"
        }
        return "下载中 \(pct)% · \(formatBytes(done)) / \(formatBytes(total))"
    }

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

private struct SettingsWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowProbe {
        let view = SettingsWindowProbe()
        view.onWindowChange = { window in
            guard let window else { return }
            MainWindowController.shared.registerSettingsWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: SettingsWindowProbe, context: Context) {}
}

@MainActor
private final class SettingsWindowProbe: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

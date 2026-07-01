import AppKit
import GemmaTransKit
import KeyboardShortcuts
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case models
    case translation
    case api
    case performance
    case hotkeys
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: "模型"
        case .translation: "翻译"
        case .api: "API"
        case .performance: "性能"
        case .hotkeys: "快捷键"
        case .appearance: "外观"
        }
    }

    var symbol: String {
        switch self {
        case .models: "cpu"
        case .translation: "character.bubble"
        case .api: "network"
        case .performance: "speedometer"
        case .hotkeys: "keyboard"
        case .appearance: "circle.lefthalf.filled"
        }
    }
}

private enum ModelTableMetrics {
    static let name: CGFloat = 228
    static let status: CGFloat = 62
    static let info: CGFloat = 96
    static let actions: CGFloat = 140
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared
    @State private var settings = AppSettings.load()
    @State private var selectedPane: SettingsPane = .models
    @State private var saved = false
    @State private var switchBlockMessage: String? = nil
    @State private var installed: [InstalledModel] = []

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GlassWindowBackdrop()
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(theme.hairline)
                    .frame(width: 0.6)
                    .padding(.vertical, 18)
                content
            }
            .padding(.top, GlassMetrics.windowChromeHeight)
            GlassWindowControls()
                .padding(.leading, 15)
                .padding(.top, 15)
        }
        .frame(width: GlassMetrics.settingsWidth, height: GlassMetrics.settingsHeight)
        .glassPreferredColorScheme(theme)
        .background {
            GlassWindowConfigurator(
                hideTitle: true,
                movableByBackground: true,
                appearanceName: theme.nsAppearance,
                backgroundColor: theme.nsWindowBackgroundColor
            )
        }
        .onAppear {
            settings = AppSettings.load()
            appearance.setMode(settings.appearanceMode)
            installed = EngineController.shared.installedModels()
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GemmaTrans")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .padding(.top, 18)
                .padding(.horizontal, 16)

            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsSidebarButton(
                        title: pane.title,
                        systemName: pane.symbol,
                        isSelected: selectedPane == pane
                    ) {
                        selectedPane = pane
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)

            Spacer()

            Text("本地翻译 · macOS")
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .frame(width: GlassMetrics.sidebarWidth, alignment: .topLeading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPane.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    let subtitle = subtitle(for: selectedPane)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer()
                GlassPillButton(title: "保存", isPrimary: true) {
                    saveSettings()
                }
                if saved {
                    Text("已保存")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 22)

            ScrollView {
                paneBody
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var paneBody: some View {
        switch selectedPane {
        case .models:
            modelPane
        case .translation:
            translationPane
        case .api:
            apiPane
        case .performance:
            performancePane
        case .hotkeys:
            hotkeysPane
        case .appearance:
            appearancePane
        }
    }

    private func subtitle(for pane: SettingsPane) -> String {
        switch pane {
        case .models: "固定列宽管理模型、状态、大小和操作"
        case .translation: "配置语言目标代码"
        case .api: "本地 HTTP API 与端口"
        case .performance: "输入与生成上限"
        case .hotkeys: "剪贴板热键与系统服务"
        case .appearance: ""
        }
    }

    // MARK: - Panes

    private var modelPane: some View {
        GlassSettingsSection {
            engineStatusRow
            modelTableHeader
            autoModelRow
            ForEach(ModelCatalog.entries) { entry in
                modelRow(entry)
            }
            Divider().opacity(0.35)
            alignedRow(label: "下载源") {
                Toggle("使用国内源（ModelScope）", isOn: $settings.useCNSource)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(theme.textPrimary)
            } meta: {
                Text("下次下载生效")
            }
        }
    }

    private var translationPane: some View {
        GlassSettingsSection {
            alignedRow(label: "中文翻译为") {
                settingsTextField("en", text: $settings.targetForChinese, width: 220)
            } meta: {
                Text("如 en")
            }
            alignedRow(label: "其他语言翻译为") {
                settingsTextField("zh-Hans", text: $settings.targetDefault, width: 220)
            } meta: {
                Text("如 zh-Hans")
            }
        }
    }

    private var apiPane: some View {
        GlassSettingsSection {
            alignedRow(label: "本地 API") {
                Toggle("启用", isOn: Binding(
                    get: { EngineController.shared.settings.apiEnabled },
                    set: {
                        EngineController.shared.setAPIEnabled($0)
                        settings.apiEnabled = $0
                    }
                ))
                .toggleStyle(.checkbox)
                .foregroundStyle(theme.textPrimary)
            } meta: {
                Text("PopClip 等外部工具")
            }
            alignedRow(label: "端口") {
                settingsNumberField("8765", value: $settings.port, width: 120)
            } meta: {
                Text("127.0.0.1")
            }
        }
    }

    private var performancePane: some View {
        GlassSettingsSection {
            alignedRow(label: "自动配置") {
                Toggle("按内存推荐", isOn: $settings.autoTuning)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(theme.textPrimary)
            } meta: {
                Text("推荐")
            }

            if settings.autoTuning {
                let auto = EngineTuning.recommended(
                    physicalMemory: SystemMemory.physical(),
                    availableMemory: SystemMemory.available()
                )
                alignedRow(label: "当前推荐") {
                    Text("\(auto.variant == .gemma4E4B4bit ? "E4B" : "E2B") · \(auto.maxTokens) tokens")
                        .foregroundStyle(theme.textPrimary)
                } meta: {
                    Text("输入 \(auto.maxInputChars) 字符")
                }
            } else {
                alignedRow(label: "生成上限") {
                    settingsIntField("tokens", value: $settings.manualMaxTokens, width: 120)
                } meta: {
                    Text("tokens")
                }
                alignedRow(label: "输入上限") {
                    settingsIntField("字符", value: $settings.maxInputChars, width: 120)
                } meta: {
                    Text("字符")
                }
            }
        }
    }

    private var hotkeysPane: some View {
        GlassSettingsSection {
            alignedRow(label: "剪贴板翻译") {
                KeyboardShortcuts.Recorder("先复制，再按", name: .translateSelection)
            } meta: {
                Text("零权限")
            }
            alignedRow(label: "划词翻译") {
                HStack(spacing: 10) {
                    Text(Self.serviceShortcutGlyphs)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(height: GlassMetrics.controlHeight)
                    GlassPillButton(title: "打开设置") {
                        Self.openServicesShortcutSettings()
                    }
                }
            } meta: {
                Text("系统服务")
            }
            Text("「划词翻译」由 macOS 服务提供。若快捷键没有响应，请在系统设置的键盘快捷键里找到 Translate with GemmaTrans 并启用。")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var appearancePane: some View {
        GlassSettingsSection {
            HStack {
                Spacer(minLength: 0)
                Picker("", selection: Binding(
                    get: { appearance.mode },
                    set: { mode in
                        settings.appearanceMode = mode
                        appearance.setMode(mode)
                        settings.save()
                        saved = true
                    }
                )) {
                    Text("跟随系统").tag(AppAppearanceMode.system)
                    Text("日间").tag(AppAppearanceMode.light)
                    Text("夜间").tag(AppAppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                Spacer(minLength: 0)
            }
            .frame(minHeight: GlassMetrics.rowHeight)
        }
    }

    // MARK: - Model Table

    private var modelTableHeader: some View {
        HStack(spacing: 8) {
            tableHeader("名称", width: ModelTableMetrics.name)
            tableHeader("状态", width: ModelTableMetrics.status)
            tableHeader("信息", width: ModelTableMetrics.info)
            tableHeader("操作", width: ModelTableMetrics.actions)
        }
        .padding(.top, 2)
    }

    private var autoModelRow: some View {
        let ec = EngineController.shared
        let isActive = ec.selectedModelID == ModelCatalog.autoID
        return modelTableRow(
            name: "Auto（按内存自动选 Gemma）",
            subtitle: "E4B ≈ 4.9 GB / E2B ≈ 3.6 GB",
            status: isActive ? "活跃" : "推荐",
            statusIsActive: isActive,
            info: ec.lastTokensPerSecond[ModelCatalog.autoID].map { String(format: "%.1f tok/s", $0) } ?? "自动",
            actions: {
                if isActive {
                    SettingsBadge("当前", isActive: true)
                } else {
                    GlassPillButton(title: "设为活跃", isDisabled: switchDisabled) {
                        trySwitchModel(to: ModelCatalog.autoID)
                    }
                }
            }
        )
    }

    private func modelRow(_ entry: ModelCatalogEntry) -> some View {
        let ec = EngineController.shared
        let installedIDs = Set(installed.map(\.id))
        let isActive = ec.selectedModelID == entry.id
        let isInstalled = installedIDs.contains(entry.id)
        let isDownloading = ec.downloadingModelID == entry.id
        let status = isActive ? "活跃" : (isInstalled ? "已安装" : "未安装")
        let info = isActive
            ? ec.lastTokensPerSecond[entry.id].map { "\(formatGB(entry.estimatedBytes)) · " + String(format: "%.1f tok/s", $0) }
                ?? formatGB(entry.estimatedBytes)
            : formatGB(entry.estimatedBytes)

        return modelTableRow(
            name: entry.displayName,
            subtitle: entry.family == .hunyuanMT2 ? "翻译专用" : "通用翻译",
            status: isDownloading ? "下载中" : status,
            statusIsActive: isActive,
            info: isDownloading ? "\(Int((ec.downloadProgress?.fraction ?? 0) * 100))%" : info,
            actions: {
                if isActive {
                    GlassPillButton(title: "删除", isDisabled: true, minWidth: 54, horizontalPadding: 8) {}
                } else if isInstalled {
                    HStack(spacing: 6) {
                        GlassPillButton(title: "设为活跃", isDisabled: switchDisabled, minWidth: 72, horizontalPadding: 8) {
                            trySwitchModel(to: entry.id)
                        }
                        GlassPillButton(title: "删除", isDestructive: true, isDisabled: isEngineBusy, minWidth: 54, horizontalPadding: 8) {
                            ec.deleteModel(id: entry.id)
                            installed = EngineController.shared.installedModels()
                        }
                    }
                } else if isDownloading {
                    SettingsBadge("下载中")
                } else {
                    GlassPillButton(title: "下载", isDisabled: ec.downloadingModelID != nil) {
                        ec.downloadModel(id: entry.id)
                    }
                }
            }
        )
    }

    private func modelTableRow<Actions: View>(
        name: String,
        subtitle: String,
        status: String,
        statusIsActive: Bool,
        info: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: ModelTableMetrics.name, alignment: .leading)

            SettingsBadge(status, isActive: statusIsActive)
                .frame(width: ModelTableMetrics.status, alignment: .leading)

            Text(info)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .frame(width: ModelTableMetrics.info, alignment: .leading)

            actions()
                .frame(width: ModelTableMetrics.actions, alignment: .leading)
        }
        .frame(minHeight: 48)
        .padding(.vertical, 2)
    }

    private func tableHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.textTertiary)
            .frame(width: width, alignment: .leading)
    }

    // MARK: - Shared Rows

    private func alignedRow<Value: View, Meta: View>(
        label: String,
        @ViewBuilder value: () -> Value,
        @ViewBuilder meta: () -> Meta
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 156, alignment: .leading)
            value()
                .frame(width: 240, alignment: .leading)
            meta()
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .frame(width: 120, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(minHeight: GlassMetrics.rowHeight)
    }

    private func settingsTextField(_ prompt: String, text: Binding<String>, width: CGFloat) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(width: width, height: GlassMetrics.controlHeight)
            .background { GlassFieldBackground() }
    }

    private func settingsNumberField(_ prompt: String, value: Binding<UInt16>, width: CGFloat) -> some View {
        TextField(prompt, value: value, format: .number.grouping(.never))
            .textFieldStyle(.plain)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(width: width, height: GlassMetrics.controlHeight)
            .background { GlassFieldBackground() }
    }

    private func settingsIntField(_ prompt: String, value: Binding<Int>, width: CGFloat) -> some View {
        TextField(prompt, value: value, format: .number.grouping(.never))
            .textFieldStyle(.plain)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(width: width, height: GlassMetrics.controlHeight)
            .background { GlassFieldBackground() }
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

    private var isEngineBusy: Bool {
        switch EngineController.shared.engineStatus {
        case .loading, .downloading: return true
        default: return false
        }
    }

    private var switchDisabled: Bool { isEngineBusy }

    private func formatGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return String(format: "%.1f GB", gb)
    }

    private func formatGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return String(format: "%.1f GB", gb)
    }

    private func trySwitchModel(to id: String) {
        Task {
            if let block = await EngineController.shared.switchModel(to: id) {
                switchBlockMessage = block.message
            }
        }
    }

    private func saveSettings() {
        settings.apiEnabled = EngineController.shared.settings.apiEnabled
        settings.appearanceMode = appearance.mode
        settings.save()
        saved = true
    }

    @ViewBuilder
    private var engineStatusRow: some View {
        let status = EngineController.shared.engineStatus
        switch status {
        case .ready:
            EmptyView()
        case .loading(let msg):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(msg).font(.caption).foregroundStyle(theme.textSecondary)
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                let pct = Int(progress.fraction * 100)
                if let total = progress.totalBytes, let done = progress.completedBytes {
                    Text("下载中 \(pct)% · \(formatGB(done)) / \(formatGB(total))")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                } else {
                    Text("下载中 \(pct)%")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                }
            }
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(theme.destructive)
        }
    }
}

private struct SettingsSidebarButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared

    let title: String
    let systemName: String
    let isSelected: Bool
    let action: () -> Void

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? theme.selectedControlText : theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
            .background {
                sidebarButtonShape
                    .fill(isSelected ? theme.selectedControlFill : Color.clear)
            }
            .contentShape(sidebarButtonShape)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var sidebarButtonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }
}

private struct GlassSettingsSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: GlassMetrics.panelCornerRadius, style: .continuous))
        .background {
            GlassSurface(
                cornerRadius: GlassMetrics.panelCornerRadius,
                fill: theme.panelOverlay,
                stroke: theme.innerHairline,
                shadowOpacity: theme.isDark ? 0.16 : 0.10,
                shadowRadius: theme.isDark ? 10 : 12,
                shadowY: 3
            )
        }
    }
}

private struct SettingsBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared

    let title: String
    var isActive = false

    init(_ title: String, isActive: Bool = false) {
        self.title = title
        self.isActive = isActive
    }

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isActive ? theme.successText : theme.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? theme.successFill : theme.controlFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isActive ? theme.successText.opacity(0.24) : theme.hairline, lineWidth: 0.5)
            }
            .lineLimit(1)
    }
}

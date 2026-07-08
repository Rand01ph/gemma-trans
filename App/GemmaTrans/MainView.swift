import AppKit
import SwiftUI
import GemmaTransKit

struct MainView: View {
    let controller: EngineController
    let windowState: MainWindowState

    @State private var input = ""
    @State private var viewModel = TranslationViewModel()

    private var canTranslate: Bool {
        controller.engineStatus == .ready
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        @Bindable var windowState = windowState

        ZStack {
            GTContentBackground()
            VStack(spacing: 0) {
                toolbar(selection: $windowState.selectedSection, searchText: $windowState.searchText)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    footerStatus
                    Spacer()
                }
                .padding(.horizontal, GTGlassTokens.Space.l)
                .padding(.top, GTGlassTokens.Space.s)
                .padding(.bottom, GTGlassTokens.Space.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .gtApplicationAppearance()
        .tint(GTGlassPalette.semanticBlue)
    }

    @ViewBuilder
    private var content: some View {
        switch windowState.selectedSection {
        case .translate:
            TranslationWorkspace(controller: controller,
                                 input: $input,
                                 viewModel: viewModel,
                                 canTranslate: canTranslate,
                                 translate: translate,
                                 clear: clear)
        case .settings:
            SettingsView(embedded: true)
        }
    }

    private func toolbar(selection: Binding<MainWindowSection>,
                         searchText: Binding<String>) -> some View {
        HStack(spacing: GTGlassTokens.Toolbar.groupSpacing) {
            Color.clear
                .frame(width: GTGlassTokens.Toolbar.leadingTrafficInset,
                       height: GTGlassTokens.Toolbar.controlHeight)
                .accessibilityHidden(true)

            HStack(spacing: GTGlassTokens.Space.s) {
                Image(systemName: "character.bubble.fill")
                    .foregroundStyle(GTGlassPalette.semanticBlue)
                Text("GemmaTrans")
                    .font(.headline.weight(.semibold))
            }
            .padding(.horizontal, GTGlassTokens.Space.m)
            .frame(height: GTGlassTokens.Toolbar.controlHeight)
            .gtGlassSurface(.flat,
                            cornerRadius: GTGlassTokens.Toolbar.radius,
                            fill: GTGlassPalette.warmNeutral,
                            fillOpacity: 0.14,
                            gradient: true)

            GTGlassButtonGroup {
                ForEach(MainWindowSection.allCases) { section in
                    ToolbarSegmentButton(section: section,
                                         selected: selection.wrappedValue == section) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            selection.wrappedValue = section
                        }
                    }
                }
            }

            Spacer(minLength: GTGlassTokens.Space.l)

            GTSearchField(text: searchText,
                          placeholder: selection.wrappedValue == .settings
                            ? "Search settings"
                            : "Search this page, or ⌘K for actions")
                .frame(width: GTGlassTokens.Toolbar.searchWidth)
        }
        .padding(.horizontal, GTGlassTokens.Toolbar.outerPadding)
        .padding(.top, GTGlassTokens.Toolbar.outerPadding)
        .frame(height: GTGlassTokens.Toolbar.band)
    }

    private var footerStatus: some View {
        switch controller.engineStatus {
        case .ready:
            return GTStatusBadge(title: "Ready · \(controller.activeModelName)",
                                 systemImage: "checkmark.circle.fill",
                                 tint: GTGlassPalette.semanticGreen)
        case .loading:
            return GTStatusBadge(title: "Loading",
                                 systemImage: "clock.arrow.circlepath",
                                 tint: GTGlassPalette.semanticOrange)
        case .downloading(let progress):
            return GTStatusBadge(title: "Downloading \(Int(progress.fraction * 100))%",
                                 systemImage: "arrow.down.circle.fill",
                                 tint: GTGlassPalette.semanticBlue)
        case .failed:
            return GTStatusBadge(title: "Needs attention",
                                 systemImage: "exclamationmark.triangle.fill",
                                 tint: GTGlassPalette.semanticOrange)
        }
    }

    private func translate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, controller.engineStatus == .ready, let engine = controller.engine else { return }
        viewModel.reset()
        viewModel.start(text: text, engine: engine)
    }

    private func clear() {
        input = ""
        viewModel.reset()
    }
}

private struct ToolbarSegmentButton: View {
    let section: MainWindowSection
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, GTGlassTokens.Space.m)
                .frame(height: GTGlassTokens.Toolbar.controlHeight - 8)
                .background {
                    Capsule(style: .continuous)
                        .fill((selected || hovering) ? Color.white.opacity(0.12) : .clear)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
        .onHover { hovering = $0 }
        .help(section.title)
        .accessibilityLabel(section.title)
    }
}

private struct TranslationWorkspace: View {
    let controller: EngineController
    @Binding var input: String
    let viewModel: TranslationViewModel
    let canTranslate: Bool
    let translate: () -> Void
    let clear: () -> Void

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: GTGlassTokens.Space.l) {
                    leftColumn
                        .frame(width: 360)
                    outputCard
                        .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: GTGlassTokens.Space.l) {
                    leftColumn
                    outputCard
                }
            }
            .padding(.horizontal, GTGlassTokens.Window.contentInset)
            .padding(.top, GTGlassTokens.Space.m)
            .padding(.bottom, GTGlassTokens.Space.l)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var leftColumn: some View {
        VStack(spacing: GTGlassTokens.Space.l) {
            inputCard
            engineCard
            shortcutsCard
        }
    }

    private var inputCard: some View {
        GTGlassCard(title: "输入",
                    subtitle: "粘贴文本，或在其他 app 里使用服务/快捷键。",
                    systemImage: "text.alignleft",
                    fill: GTGlassPalette.warmNeutral) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $input)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(GTGlassTokens.Space.s)
                    .frame(minHeight: 190)
                    .gtGlassSurface(.flat,
                                    cornerRadius: GTGlassTokens.Radius.control,
                                    fill: GTGlassPalette.coolNeutral,
                                    fillOpacity: 0.12,
                                    gradient: false)
                if input.isEmpty {
                    Text("在此粘贴文字...")
                        .foregroundStyle(.tertiary)
                        .padding(GTGlassTokens.Space.l)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: GTGlassTokens.Space.s) {
                GTGlassButton("翻译", systemImage: "arrow.right.circle.fill", prominent: true) {
                    translate()
                }
                .disabled(!canTranslate)
                .keyboardShortcut(.return, modifiers: .command)

                GTGlassButton("清空", systemImage: "xmark.circle") {
                    clear()
                }
                .disabled(input.isEmpty && viewModel.output.isEmpty)
            }
        }
    }

    private var engineCard: some View {
        GTGlassCard(title: "引擎",
                    subtitle: engineSubtitle,
                    systemImage: engineIcon,
                    fill: engineTint) {
            switch controller.engineStatus {
            case .ready:
                GTPanelRow(title: "模型", subtitle: controller.activeModelName) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .loading(let stage):
                HStack(spacing: GTGlassTokens.Space.s) {
                    ProgressView().controlSize(.small)
                    Text(stage).foregroundStyle(.secondary)
                }
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: GTGlassTokens.Space.s) {
                    ProgressView(value: progress.fraction)
                    Text(downloadText(progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: GTGlassTokens.Space.s) {
                    Text(message)
                        .foregroundStyle(.orange)
                    GTGlassButton("重试", systemImage: "arrow.clockwise", prominent: true) {
                        controller.reload()
                    }
                }
            }
        }
    }

    private var shortcutsCard: some View {
        GTGlassCard(title: "快捷入口",
                    subtitle: "保留菜单栏形态，不改变划词翻译的当前 Space 行为。",
                    systemImage: "keyboard",
                    fill: GTGlassPalette.lavender) {
            GTPanelRow(title: "剪贴板翻译", subtitle: "先复制文本，再按 Option-D。") {
                Text("⌥D")
                    .font(.callout.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            GTPanelDivider()
            GTPanelRow(title: "划词翻译", subtitle: "由 macOS 服务菜单提供。") {
                Text(SettingsView.serviceShortcutGlyphs)
                    .font(.callout.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outputCard: some View {
        GTGlassCard(title: "译文",
                    subtitle: outputSubtitle,
                    systemImage: "character.cursor.ibeam",
                    fill: GTGlassPalette.peach) {
            ScrollView {
                Text(outputText)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .foregroundStyle(viewModel.error == nil
                        ? (viewModel.output.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        : AnyShapeStyle(Color.red))
                    .padding(GTGlassTokens.Space.m)
            }
            .frame(minHeight: 430)
            .gtGlassSurface(.flat,
                            cornerRadius: GTGlassTokens.Radius.control,
                            fill: GTGlassPalette.innerNeutral,
                            fillOpacity: 0.12,
                            gradient: false)

            HStack {
                if let tps = viewModel.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", tps))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GTGlassButton("复制", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.output, forType: .string)
                }
                .disabled(viewModel.output.isEmpty)
            }
        }
    }

    private var outputText: String {
        viewModel.error ?? (viewModel.output.isEmpty ? "译文显示在这里..." : viewModel.output)
    }

    private var outputSubtitle: String {
        if let error = viewModel.error { return error }
        return viewModel.status.isEmpty ? "等待翻译任务。" : viewModel.status
    }

    private var engineSubtitle: String {
        switch controller.engineStatus {
        case .ready:
            return "模型就绪，可直接翻译。"
        case .loading(let stage):
            return stage
        case .downloading(let progress):
            return downloadText(progress)
        case .failed(let message):
            return message
        }
    }

    private var engineIcon: String {
        switch controller.engineStatus {
        case .ready: return "checkmark.seal.fill"
        case .loading: return "clock.arrow.circlepath"
        case .downloading: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var engineTint: Color {
        switch controller.engineStatus {
        case .ready: return GTGlassPalette.semanticGreen
        case .loading: return GTGlassPalette.semanticOrange
        case .downloading: return GTGlassPalette.semanticBlue
        case .failed: return GTGlassPalette.semanticOrange
        }
    }

    private func downloadText(_ progress: DownloadProgress) -> String {
        let pct = Int(progress.fraction * 100)
        guard let done = progress.completedBytes, let total = progress.totalBytes else {
            return "下载中 \(pct)%"
        }
        return String(format: "下载中 %d%% · %.1f / %.1f GB",
                      pct,
                      Double(done) / 1e9,
                      Double(total) / 1e9)
    }
}

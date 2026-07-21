import AppKit
import SwiftUI
import GemmaTransKit

private let horizontalWorkspaceBreakpoint: CGFloat = 860

struct TranslationWorkspace: View {
    let controller: EngineController
    @Binding var input: String
    let viewModel: TranslationViewModel
    let canTranslate: Bool
    let translate: () -> Void
    let clearInput: () -> Void

    @FocusState private var inputFocused: Bool
    @State private var copied = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: GTGlassTokens.Space.m) {
                if controller.engineStatus != .ready {
                    engineNotice
                }

                if proxy.size.width >= horizontalWorkspaceBreakpoint {
                    HStack(alignment: .top, spacing: GTGlassTokens.Space.l) {
                        inputCard
                        outputCard
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: GTGlassTokens.Space.l) {
                            inputCard.frame(minHeight: 340)
                            outputCard.frame(minHeight: 340)
                        }
                    }
                    .scrollEdgeEffectStyle(.soft, for: .all)
                }
            }
            .padding(.horizontal, GTGlassTokens.Window.contentInset)
            .padding(.top, GTGlassTokens.Space.m)
            .padding(.bottom, GTGlassTokens.Window.contentInset)
        }
        .task { inputFocused = true }
        .onDisappear { copyFeedbackTask?.cancel() }
    }

    private var inputCard: some View {
        GTGlassCard(title: "原文",
                    subtitle: input.isEmpty ? "粘贴或输入要翻译的内容" : "\(input.count) 个字符",
                    systemImage: "text.alignleft") {
            GTTextEditor(text: $input,
                         focused: $inputFocused,
                         placeholder: "在此粘贴文字…",
                         supportingText: "⌘↩ 翻译")
                .frame(minHeight: 220, maxHeight: .infinity)
                .gtContentSurface(.reading)
                .accessibilityLabel("原文")

            HStack(spacing: GTGlassTokens.Space.s) {
                Label("自动检测语言", systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(GTGlassPalette.secondaryText)
                Spacer()
                GTGlassButton("清空原文", systemImage: "xmark.circle") {
                    clearInput()
                    inputFocused = true
                }
                .disabled(input.isEmpty)

                GTGlassButton("翻译", systemImage: "arrow.right.circle.fill", emphasis: .primary) {
                    translate()
                }
                .disabled(!canTranslate)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var outputCard: some View {
        GTGlassCard(title: "译文",
                    subtitle: outputSubtitle,
                    systemImage: "text.quote") {
            ScrollView {
                Text(outputText)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .foregroundStyle(viewModel.error == nil
                        ? (viewModel.output.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        : AnyShapeStyle(GTGlassPalette.semanticRed))
                    .padding(GTGlassTokens.Space.m)
            }
            .frame(minHeight: 220, maxHeight: .infinity)
            .gtContentSurface(.reading)

            HStack(spacing: GTGlassTokens.Space.s) {
                if let tps = viewModel.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", tps))
                        .font(.caption)
                        .foregroundStyle(GTGlassPalette.secondaryText)
                }
                Spacer()
                if viewModel.isRunning {
                    GTGlassButton("停止", systemImage: "stop.fill", emphasis: .interrupt) {
                        viewModel.cancel()
                    }
                }
                GTGlassButton(copied ? "已复制" : "复制译文",
                              systemImage: copied ? "checkmark" : "doc.on.doc",
                              emphasis: copied ? .feedback : .secondary,
                              minWidth: 104) {
                    copyOutput()
                }
                .disabled(viewModel.output.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var engineNotice: some View {
        HStack(spacing: GTGlassTokens.Space.m) {
            Image(systemName: engineIcon)
                .font(.title3)
                .foregroundStyle(engineTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(engineTitle)
                    .font(.callout.weight(.semibold))
                Text(engineSubtitle)
                    .font(.caption)
                    .foregroundStyle(GTGlassPalette.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
            if case .downloading(let progress) = controller.engineStatus {
                ProgressView(value: progress.fraction)
                    .frame(width: 120)
            }
            if case .failed = controller.engineStatus {
                GTGlassButton("重试", systemImage: "arrow.clockwise", emphasis: .primary) {
                    controller.reload()
                }
            }
        }
        .padding(GTGlassTokens.Space.m)
        .gtGlassSurface(.flat,
                        cornerRadius: GTGlassTokens.Radius.card,
                        fillOpacity: 0.12,
                        gradient: false)
    }

    private var outputText: String {
        viewModel.error ?? (viewModel.output.isEmpty ? "译文会显示在这里…" : viewModel.output)
    }

    private var outputSubtitle: String {
        if let error = viewModel.error { return error }
        if viewModel.isRunning { return "正在生成译文…" }
        return viewModel.status.isEmpty ? "等待翻译" : viewModel.status
    }

    private var engineTitle: String {
        switch controller.engineStatus {
        case .needsModel: return "请选择本地模型"
        case .ready: return "模型已就绪"
        case .loading: return "正在加载模型"
        case .downloading: return "正在下载模型"
        case .failed: return "引擎需要处理"
        }
    }

    private var engineSubtitle: String {
        switch controller.engineStatus {
        case .needsModel(let message): return message
        case .ready: return controller.activeModelName
        case .loading(let stage): return stage
        case .downloading(let progress): return downloadText(progress)
        case .failed(let message): return message
        }
    }

    private var engineIcon: String {
        switch controller.engineStatus {
        case .needsModel: return "cpu"
        case .ready: return "checkmark.seal.fill"
        case .loading: return "clock.arrow.circlepath"
        case .downloading: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var engineTint: Color {
        switch controller.engineStatus {
        case .failed: return GTGlassPalette.semanticRed
        case .needsModel, .ready, .loading, .downloading:
            return GTGlassPalette.secondaryText
        }
    }

    private func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.output, forType: .string)
        copied = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            copied = false
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

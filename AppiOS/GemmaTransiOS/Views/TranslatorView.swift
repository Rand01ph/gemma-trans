import SwiftUI
import GemmaTransKit

/// 翻译工作区状态（spec 第 3.4–3.6）。单例：供 GemmaTransiOSApp 注入接力文本并触发自动翻译。
@MainActor @Observable
final class TranslatorModel {
    static let shared = TranslatorModel()

    var input = ""
    var output = ""
    /// 实化语向（翻译开始后由 result.detected/target 透出，nil 时语向 pill 显示「自动」）
    var detected: String?
    var target: String?
    var truncated = false
    var isTranslating = false
    /// 拷贝成功后 0.8s 内图标变 checkmark
    var didCopy = false

    private var task: Task<Void, Never>?

    /// 700 字上限与引擎 maxInputChars 对齐
    static let charLimit = 700

    func translate() {
        guard let engine = EngineHolder.shared.engine, !input.isEmpty, !isTranslating else { return }
        let text = input
        isTranslating = true
        output = ""
        detected = nil
        target = nil
        truncated = false
        task = Task {
            do {
                let result = try await engine.translate(text, target: nil)
                detected = result.detected
                target = result.target
                truncated = result.truncated
                for try await chunk in result.chunks {
                    if Task.isCancelled { break }
                    output += chunk
                }
            } catch {
                if !Task.isCancelled {
                    output = "翻译失败：\(error)"
                }
            }
            isTranslating = false
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isTranslating = false
    }

    func clearInput() {
        cancel()
        input = ""
        output = ""
        detected = nil
        target = nil
        truncated = false
    }

    /// 接力入口：灌入文本并自动开始翻译（引擎就绪时立即译，否则由 ContentView 在 .ready 时补触发）
    func handoff(_ text: String) {
        input = text
        output = ""
        if EngineHolder.shared.engine != nil {
            translate()
        }
    }
}

/// 工作区主视图（spec 2.2 / 3.4–3.6）。
struct TranslatorView: View {
    @State private var holder = EngineHolder.shared
    @State private var model = TranslatorModel.shared
    @Binding var showSettings: Bool

    @FocusState private var inputFocused: Bool

    private var isLoading: Bool {
        if case .loading = holder.status { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                    languageRow
                    InputCard(model: model, isLoading: isLoading, focused: $inputFocused)
                    if !model.output.isEmpty {
                        OutputCard(model: model)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if holder.status == .ready && model.input.isEmpty && model.output.isEmpty {
                        SystemTranslateTipCard(onOpenSettings: { showSettings = true })
                            .padding(.top, Theme.Spacing.cardGap)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenH)
                .padding(.vertical, Theme.Spacing.cardGap)
                .animation(.default, value: model.output.isEmpty)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("GemmaTrans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("设置")
                }
            }
        }
    }

    /// 语向 pill + 加载 pill（spec 2.2）
    private var languageRow: some View {
        HStack(spacing: 8) {
            LanguagePill(detected: model.detected, target: model.target)
            if isLoading {
                LoadingPill()
                    .transition(.opacity)
            }
            Spacer()
        }
        .animation(.default, value: isLoading)
    }
}

// MARK: - 语向 pill

private struct LanguagePill: View {
    let detected: String?
    let target: String?

    private var text: String {
        if let detected, let target {
            return LanguageLabel.arrow(detected: detected, target: target)
        }
        return "自动 · 中文 ⇄ English"
    }

    var body: some View {
        Label(text, systemImage: "arrow.left.arrow.right")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

// MARK: - 加载 pill（spec 2.2，仅 .loading 约 5s）

private struct LoadingPill: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("正在加载模型")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }
}

// MARK: - 输入卡（spec 2.2 / 3.4–3.5）

private struct InputCard: View {
    @Bindable var model: TranslatorModel
    let isLoading: Bool
    @FocusState.Binding var focused: Bool

    private var overLimit: Bool { model.input.count > TranslatorModel.charLimit }
    private var canSend: Bool {
        EngineHolder.shared.engine != nil && !model.input.isEmpty && !model.isTranslating
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if model.input.isEmpty {
                    Text("输入或粘贴要翻译的文本")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.input)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72, maxHeight: 200)
                    .fixedSize(horizontal: false, vertical: true)
            }
            controlRow
        }
        .padding(Theme.Spacing.cardPadding)
        .cardBackground()
    }

    /// 底部控件行：左侧 清除/计数，右侧 粘贴/发送/停止
    private var controlRow: some View {
        HStack(alignment: .bottom) {
            leftControls
            Spacer()
            rightControls
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var leftControls: some View {
        if !model.input.isEmpty {
            HStack(spacing: 8) {
                Button {
                    model.clearInput()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("清除")
                // 接近上限时浮出计数，超限变 orange
                if model.input.count >= TranslatorModel.charLimit - 50 {
                    Text("\(model.input.count) / \(TranslatorModel.charLimit)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(overLimit ? Color(.systemOrange) : .secondary)
                }
            }
        }
    }

    @ViewBuilder private var rightControls: some View {
        if model.isTranslating {
            // 流式期间发送钮变停止钮
            Button { model.cancel() } label: {
                Image(systemName: "stop.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: Theme.minTouch, height: Theme.minTouch)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .accessibilityLabel("停止")
        } else if model.input.isEmpty {
            // 空态：原位「粘贴」胶囊
            Button {
                if let s = UIPasteboard.general.string { model.input = s }
            } label: {
                Label("粘贴", systemImage: "doc.on.clipboard")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .clipShape(Capsule())
        } else {
            // 44pt 圆形 accent 发送钮
            Button { model.translate() } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: Theme.minTouch, height: Theme.minTouch)
                    .background(canSend ? Color.accentColor : Color(.systemGray3), in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("翻译")
        }
    }
}

// MARK: - 译文卡（spec 3.5–3.6）

private struct OutputCard: View {
    @Bindable var model: TranslatorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 仅调制光标 ▍ 的颜色透明度做闪烁，不改变译文文本内容（否则整段译文会被 crossfade 跟着闪）
    @State private var cursorOn = true

    /// 短译文（≤120 字符）给 title3，长译文 body
    private var outputFont: Font {
        model.output.count <= 120 ? .title3 : .body
    }

    private var caption: String {
        var s: String
        if let detected = model.detected, let target = model.target {
            s = LanguageLabel.arrow(detected: detected, target: target)
        } else {
            s = "翻译中"
        }
        if model.truncated { s += " · 已截断" }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 译文 + 流式光标：▍ 的存在只由 isTranslating 决定（内容稳定），
            // 闪烁靠 cursorOn 调颜色透明度——译文本身不随闪烁重绘
            (Text(model.output)
                + Text(model.isTranslating ? " ▍" : "")
                    .foregroundColor(.accentColor.opacity(cursorOn ? 1 : 0.15)))
                .font(outputFont)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = model.output
                    Haptics.copySuccess()
                    model.didCopy = true
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        model.didCopy = false
                    }
                } label: {
                    Image(systemName: model.didCopy ? "checkmark" : "doc.on.doc")
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(model.isTranslating)
                .opacity(model.isTranslating ? 0.4 : 1)
                .accessibilityLabel("拷贝译文")
            }
        }
        .padding(Theme.Spacing.cardPadding)
        .cardBackground()
        .onAppear { if model.isTranslating { startCursorBlink() } }
        .onChange(of: model.isTranslating) { _, translating in
            if translating { startCursorBlink() }
            else { withAnimation(.linear(duration: 0.15)) { cursorOn = true } }  // 停止闪烁，停在常显
        }
    }

    /// 仅在流式期间启动；autoreverses 让 ▍ 颜色在 1↔0.15 间往返。完成后 ▍ 内容消失，动画自然失效
    private func startCursorBlink() {
        guard !reduceMotion else { cursorOn = true; return }
        cursorOn = true
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            cursorOn = false
        }
    }
}

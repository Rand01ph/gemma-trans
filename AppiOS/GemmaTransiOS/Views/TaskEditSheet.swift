import SwiftUI
import GemmaTransKit

/// 编辑 sheet 的三种打开方式。
enum TaskEditorMode: Identifiable {
    case new
    case edit(ProcessTask)
    case builtin(ProcessPreset)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let task): return task.id.uuidString
        case .builtin(let preset): return preset.id
        }
    }
}

/// 任务编辑 sheet：名称 + 指令 + 试运行。
///
/// - 自定义任务（new/edit）：可编辑，保存写 ProcessTaskStore。
/// - 内置预设（builtin）：只读查看，「复制为自定义」翻转为可编辑的新任务。
/// - 试运行用前台 EngineHolder 的 GPU 引擎（与后台 intent 的临时 CPU 引擎无关），
///   模型未就绪时按钮置灰并注明。
struct TaskEditSheet: View {
    let mode: TaskEditorMode
    let store: ProcessTaskStore

    @Environment(\.dismiss) private var dismiss
    @State private var holder = EngineHolder.shared

    @State private var name: String
    @State private var instruction: String
    /// builtin 的只读态；「复制为自定义」翻转为 false（保存时新建）
    @State private var isReadOnly: Bool
    /// edit 模式保留原 id（update）；new/builtin 为 nil（add）
    private let editingID: UUID?

    // 试运行状态
    @State private var sample = ""
    @State private var runResult = ""
    @State private var isRunning = false
    @State private var runTask: Task<Void, Never>?

    init(mode: TaskEditorMode, store: ProcessTaskStore) {
        self.mode = mode
        self.store = store
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _instruction = State(initialValue: "")
            _isReadOnly = State(initialValue: false)
            editingID = nil
        case .edit(let task):
            _name = State(initialValue: task.name)
            _instruction = State(initialValue: task.instruction)
            _isReadOnly = State(initialValue: false)
            editingID = task.id
        case .builtin(let preset):
            _name = State(initialValue: preset.name)
            _instruction = State(initialValue: preset.instruction)
            _isReadOnly = State(initialValue: true)
            editingID = nil
        }
    }

    private var title: String {
        if isReadOnly { return "内置预设" }
        return editingID != nil ? "编辑任务" : "新建任务"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                    labeledCard("名称") { nameField }
                    labeledCard("指令") { instructionField }
                    labeledCard("试运行") { TryRunCard(
                        holder: holder,
                        instruction: instruction,
                        sample: $sample,
                        result: $runResult,
                        isRunning: $isRunning,
                        onRun: run
                    ) }
                }
                .padding(.horizontal, Theme.Spacing.screenH)
                .padding(.vertical, Theme.Spacing.cardGap)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isReadOnly ? "关闭" : "取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isReadOnly {
                        Button("复制为自定义") { copyAsCustom() }
                    } else {
                        Button("保存") { save() }
                            .disabled(!canSave)
                    }
                }
            }
            .onDisappear { runTask?.cancel() }
        }
    }

    // MARK: - 字段

    @ViewBuilder private var nameField: some View {
        if isReadOnly {
            Text(name)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField("任务名称（出现在快捷指令下拉里）", text: $name)
        }
    }

    @ViewBuilder private var instructionField: some View {
        if isReadOnly {
            Text(instruction)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ZStack(alignment: .topLeading) {
                if instruction.isEmpty {
                    Text("描述要执行的处理，例如：把口语改写成正式邮件语气")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $instruction)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, maxHeight: 240)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 小标题 + 卡片容器（沿用 Theme 卡片语言：20pt continuous、secondaryGroupedBackground）
    private func labeledCard(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
                .padding(Theme.Spacing.cardPadding)
                .cardBackground()
        }
    }

    // MARK: - 动作

    /// 翻转为可编辑的新任务：editingID 为 nil，保存即 add。
    /// 名称加「副本」后缀——避免快捷指令下拉里出现两个同名任务。
    private func copyAsCustom() {
        isReadOnly = false
        name += "（副本）"
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedInstruction.isEmpty else { return }
        if let id = editingID {
            store.update(ProcessTask(id: id, name: trimmedName, instruction: trimmedInstruction))
        } else {
            store.add(ProcessTask(name: trimmedName, instruction: trimmedInstruction))
        }
        dismiss()
    }

    private func run() {
        guard let engine = holder.engine, !isRunning else { return }
        let input = sample
        let instr = instruction
        isRunning = true
        runResult = ""
        runTask = Task {
            do {
                let out = try await engine.process(input, instruction: instr)
                if !Task.isCancelled { runResult = out }
            } catch {
                if !Task.isCancelled { runResult = "运行失败：\(error)" }
            }
            isRunning = false
        }
    }
}

// MARK: - 试运行卡

/// 样例输入 + 运行按钮 + 结果展示。引擎未就绪（status != .ready）时按钮置灰附说明。
private struct TryRunCard: View {
    let holder: EngineHolder
    let instruction: String
    @Binding var sample: String
    @Binding var result: String
    @Binding var isRunning: Bool
    let onRun: () -> Void

    private var engineReady: Bool {
        holder.status == .ready && holder.engine != nil
    }

    private var canRun: Bool {
        engineReady && !isRunning
            && !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("样例输入（如一条快递短信）", text: $sample, axis: .vertical)
                    .lineLimit(1...4)
                runButton
            }
            if !engineReady {
                Text("模型加载后可用")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !result.isEmpty {
                Divider()
                Text(result)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var runButton: some View {
        Button(action: onRun) {
            Group {
                if isRunning {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: Theme.minTouch, height: Theme.minTouch)
            .background(canRun ? Color.accentColor : Color(.systemGray3), in: Circle())
        }
        .disabled(!canRun)
        .accessibilityLabel("试运行")
    }
}

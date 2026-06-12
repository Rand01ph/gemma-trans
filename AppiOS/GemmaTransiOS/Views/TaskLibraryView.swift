import SwiftUI
import GemmaTransKit

/// 任务库（范围 B 核心 UI）：内置预设只读区 + 自定义任务增删改区。
///
/// 自定义任务存 App Group suite（ModelStore.settingsSuite）——与 ProcessTaskEntity
/// 读的是同一份库：在这里保存的任务直接出现在快捷指令「本地 AI 处理」的任务下拉里。
struct TaskLibraryView: View {
    /// App Group suite：与 intent 进程共享（ProcessTaskEntity 同一约定）
    private let store = ProcessTaskStore(
        suite: UserDefaults(suiteName: ModelStore.settingsSuite) ?? .standard)

    @State private var tasks: [ProcessTask] = []
    @State private var editorMode: TaskEditorMode?

    var body: some View {
        List {
            Section {
                ForEach(ProcessPresets.all, id: \.id) { preset in
                    Button {
                        editorMode = .builtin(preset)
                    } label: {
                        TaskRow(name: preset.name, instruction: preset.instruction)
                    }
                }
            } header: {
                Text("内置")
            } footer: {
                Text("内置预设只读，点开可查看指令或复制为自定义。")
            }

            Section {
                if tasks.isEmpty {
                    Text("还没有自定义任务")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tasks) { task in
                        Button {
                            editorMode = .edit(task)
                        } label: {
                            TaskRow(name: task.name, instruction: task.instruction)
                        }
                    }
                    .onDelete(perform: delete)
                }
            } header: {
                Text("自定义")
            } footer: {
                Text("保存的任务会出现在快捷指令「本地 AI 处理」的任务下拉里。")
            }
        }
        .navigationTitle("任务库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorMode = .new
                } label: {
                    Image(systemName: "plus")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("新建任务")
            }
        }
        // onDismiss 统一刷新：保存/复制为自定义/纯关闭都走这一条，不需要 sheet 回调
        .sheet(item: $editorMode, onDismiss: reload) { mode in
            TaskEditSheet(mode: mode, store: store)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        tasks = store.list()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            store.delete(id: tasks[index].id)
        }
        reload()
    }
}

// MARK: - 任务行（名称 + 指令预览 2 行）

private struct TaskRow: View {
    let name: String
    let instruction: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .foregroundStyle(.primary)
            Text(instruction)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

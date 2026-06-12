import AppIntents
import GemmaTransKit

/// 「本地 AI 处理」的任务参数实体。
///
/// 用 AppEntity 而不是静态 AppEnum：query 动态返回 内置预设 + 任务库自定义任务，
/// 用户在 app 任务库里存的任务直接出现在快捷指令的参数下拉里——这是范围 B 的核心价值。
///
/// id 约定：内置预设沿用 ProcessPresets 的稳定 id（"builtin.courier" 等）；
/// 自定义任务用 "custom.<uuid>" 前缀区分命名空间，避免与未来内置 id 撞车。
struct ProcessTaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "处理任务"
    static let defaultQuery = ProcessTaskQuery()

    let id: String
    let name: String
    /// 实体直接携带指令全文：perform() 拿到实体即拿到指令，无需二次查库
    let instruction: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProcessTaskQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProcessTaskEntity] {
        let all = Self.allEntities()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    /// 快捷指令参数下拉的候选列表：内置在前（顺序稳定）、自定义在后
    func suggestedEntities() async throws -> [ProcessTaskEntity] {
        Self.allEntities()
    }

    /// 内置预设 + 任务库自定义任务。
    /// 自定义任务存在 App Group suite（ModelStore.settingsSuite）：
    /// intent 进程与主 app UI 进程共享同一份任务库。
    private static func allEntities() -> [ProcessTaskEntity] {
        let builtins = ProcessPresets.all.map {
            ProcessTaskEntity(id: $0.id, name: $0.name, instruction: $0.instruction)
        }
        let store = ProcessTaskStore(
            suite: UserDefaults(suiteName: ModelStore.settingsSuite) ?? .standard)
        let customs = store.list().map {
            ProcessTaskEntity(
                id: "custom.\($0.id.uuidString)", name: $0.name, instruction: $0.instruction)
        }
        return builtins + customs
    }
}

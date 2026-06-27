import Foundation

/// 用户自定义处理任务。
public struct ProcessTask: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var instruction: String

    public init(id: UUID = UUID(), name: String, instruction: String) {
        self.id = id
        self.name = name
        self.instruction = instruction
    }
}

/// 自定义任务持久化仓库。UserDefaults suite 可注入，便于单测隔离。
/// @unchecked Sendable：UserDefaults 是 ObjC 类，Swift 6 未标注 Sendable，
/// 但 Apple 文档确认其线程安全，故手工断言。
public final class ProcessTaskStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let storageKey = "com.gemmatrans.processTaskStore.tasks"

    public init(suite: UserDefaults = .standard) {
        self.defaults = suite
    }

    // MARK: - Read

    /// 读取所有自定义任务。JSON 损坏时回退空表。
    public func list() -> [ProcessTask] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        let tasks = try? JSONDecoder().decode([ProcessTask].self, from: data)
        return tasks ?? []
    }

    // MARK: - Write

    public func add(_ task: ProcessTask) {
        var tasks = list()
        tasks.append(task)
        save(tasks)
    }

    public func update(_ task: ProcessTask) {
        var tasks = list()
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx] = task
        save(tasks)
    }

    public func delete(id: UUID) {
        let tasks = list().filter { $0.id != id }
        save(tasks)
    }

    // MARK: - Private

    private func save(_ tasks: [ProcessTask]) {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct ProcessTaskStoreTests {

    /// 返回一个隔离的 UserDefaults suite，每次测试独立。
    private func freshSuite(name: String = #function) -> UserDefaults {
        let suiteName = "com.gemmatrans.test.\(name).\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        return suite
    }

    // MARK: - CRUD roundtrip

    @Test func listEmptyOnFreshStore() {
        let store = ProcessTaskStore(suite: freshSuite())
        #expect(store.list().isEmpty)
    }

    @Test func addAndList() {
        let store = ProcessTaskStore(suite: freshSuite())
        let task = ProcessTask(name: "测试任务", instruction: "提取信息")
        store.add(task)
        let tasks = store.list()
        #expect(tasks.count == 1)
        #expect(tasks[0].name == "测试任务")
        #expect(tasks[0].instruction == "提取信息")
    }

    @Test func addMultipleTasks() {
        let store = ProcessTaskStore(suite: freshSuite())
        store.add(ProcessTask(name: "任务A", instruction: "指令A"))
        store.add(ProcessTask(name: "任务B", instruction: "指令B"))
        #expect(store.list().count == 2)
    }

    @Test func updateTask() {
        let store = ProcessTaskStore(suite: freshSuite())
        let task = ProcessTask(name: "原名称", instruction: "原指令")
        store.add(task)
        var updated = task
        updated = ProcessTask(id: task.id, name: "新名称", instruction: "新指令")
        store.update(updated)
        let tasks = store.list()
        #expect(tasks.count == 1)
        #expect(tasks[0].name == "新名称")
        #expect(tasks[0].instruction == "新指令")
        #expect(tasks[0].id == task.id)
    }

    @Test func updateNonExistentTaskIsNoop() {
        let store = ProcessTaskStore(suite: freshSuite())
        let task = ProcessTask(name: "任务", instruction: "指令")
        store.add(task)
        let phantom = ProcessTask(id: UUID(), name: "幽灵", instruction: "无")
        store.update(phantom)
        // 原任务不受影响，数量不变
        #expect(store.list().count == 1)
        #expect(store.list()[0].name == "任务")
    }

    @Test func deleteTask() {
        let store = ProcessTaskStore(suite: freshSuite())
        let task = ProcessTask(name: "待删除", instruction: "指令")
        store.add(task)
        store.delete(id: task.id)
        #expect(store.list().isEmpty)
    }

    @Test func deleteOnlyRemovesTargetTask() {
        let store = ProcessTaskStore(suite: freshSuite())
        let t1 = ProcessTask(name: "任务1", instruction: "指令1")
        let t2 = ProcessTask(name: "任务2", instruction: "指令2")
        store.add(t1)
        store.add(t2)
        store.delete(id: t1.id)
        let remaining = store.list()
        #expect(remaining.count == 1)
        #expect(remaining[0].id == t2.id)
    }

    @Test func deleteNonExistentIdIsNoop() {
        let store = ProcessTaskStore(suite: freshSuite())
        let task = ProcessTask(name: "任务", instruction: "指令")
        store.add(task)
        store.delete(id: UUID())
        #expect(store.list().count == 1)
    }

    // MARK: - suite 隔离

    @Test func twoStoresWithDifferentSuitesAreIsolated() {
        let suiteA = freshSuite(name: "storeA")
        let suiteB = freshSuite(name: "storeB")
        let storeA = ProcessTaskStore(suite: suiteA)
        let storeB = ProcessTaskStore(suite: suiteB)
        storeA.add(ProcessTask(name: "只在A", instruction: "指令"))
        #expect(storeA.list().count == 1)
        #expect(storeB.list().isEmpty)
    }

    // MARK: - 损坏数据回退空表

    @Test func corruptDataFallsBackToEmpty() {
        let suite = freshSuite()
        // 写入无效 JSON
        suite.set("not-valid-json".data(using: .utf8)!, forKey: "com.gemmatrans.processTaskStore.tasks")
        let store = ProcessTaskStore(suite: suite)
        #expect(store.list().isEmpty)
    }

    // MARK: - Codable / Equatable

    @Test func processTaskIsEquatable() {
        let id = UUID()
        let t1 = ProcessTask(id: id, name: "A", instruction: "B")
        let t2 = ProcessTask(id: id, name: "A", instruction: "B")
        #expect(t1 == t2)
    }

    @Test func processTaskRoundTripsCodable() throws {
        let task = ProcessTask(name: "编码测试", instruction: "测试指令")
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(ProcessTask.self, from: data)
        #expect(decoded == task)
    }
}

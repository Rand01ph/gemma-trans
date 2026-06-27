import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct InstalledModelsTests {
    private func tempBase() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // 在 base 下伪造某 catalog 条目的快照目录（含完成标记），scan 应识别
    @Test func scan_findsCompletedSnapshot() throws {
        let base = tempBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let repo = ModelCatalog.entry(id: "gemma-e2b-4bit")!.repo
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: repo)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = dir.appendingPathComponent("model.safetensors")
        try Data(repeating: 0, count: 2048).write(to: payload)
        // 完成标记：文件名→字节数（与 ModelDownloader.isComplete 一致）
        let marker = ["model.safetensors": Int64(2048)]
        try JSONEncoder().encode(marker).write(to: dir.appendingPathComponent(".download-complete"))

        let found = InstalledModels.scan(base: base)
        #expect(found.map(\.id) == ["gemma-e2b-4bit"])
        #expect(found.first!.bytesOnDisk >= 2048)
    }

    @Test func scan_ignoresIncompleteOrUnknown() throws {
        let base = tempBase()
        defer { try? FileManager.default.removeItem(at: base) }
        // 不完整（无标记）的已知仓库目录
        let repo = ModelCatalog.entry(id: "gemma-e4b-4bit")!.repo
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: repo)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 10).write(to: dir.appendingPathComponent("partial.bin"))
        #expect(InstalledModels.scan(base: base).isEmpty)
    }

    @Test func delete_removesSnapshot() throws {
        let base = tempBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let repo = ModelCatalog.entry(id: "gemma-e2b-4bit")!.repo
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: repo)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try InstalledModels.delete(id: "gemma-e2b-4bit", base: base)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }
}

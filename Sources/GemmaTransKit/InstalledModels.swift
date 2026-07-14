import Foundation

public struct InstalledModel: Sendable, Equatable {
    public let id: String
    public let bytesOnDisk: UInt64
}

public enum InstalledModels {
    public static func isInstalled(id: String, base: URL) -> Bool {
        guard let entry = ModelCatalog.entry(id: id) else { return false }
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: entry.repo)
        return ModelDownloader.isComplete(dir)
    }

    /// 遍历 catalog，凡在 base 下有完整快照（ModelDownloader.isComplete）者计入，附目录体积。
    public static func scan(base: URL) -> [InstalledModel] {
        ModelCatalog.entries.compactMap { entry in
            let dir = ModelDownloader.snapshotDirectory(in: base, repo: entry.repo)
            guard ModelDownloader.isComplete(dir) else { return nil }
            return InstalledModel(id: entry.id, bytesOnDisk: directorySize(dir))
        }
    }

    public static func delete(id: String, base: URL) throws {
        guard let entry = ModelCatalog.entry(id: id) else { return }
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: entry.repo)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private static func directorySize(_ dir: URL) -> UInt64 {
        guard let en = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in en {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += UInt64(size)
        }
        return total
    }
}

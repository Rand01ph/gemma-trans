import Foundation

public struct InstalledModel: Sendable, Equatable {
    public let id: String
    public let bytesOnDisk: UInt64
}

public enum InstalledModels {
    public static var defaultLegacyHuggingFaceHub: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
    }

    public static func isInstalled(
        id: String,
        base: URL,
        legacyHuggingFaceHub: URL? = nil
    ) -> Bool {
        guard let entry = ModelCatalog.entry(id: id) else { return false }
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: entry.repo)
        return ModelDownloader.isComplete(dir)
            || legacyDirectoryIfInstalled(for: entry, hub: legacyHuggingFaceHub) != nil
    }

    /// 遍历 catalog，识别新快照与旧版 Hugging Face 缓存，附实际目录体积。
    public static func scan(
        base: URL,
        legacyHuggingFaceHub: URL? = nil
    ) -> [InstalledModel] {
        ModelCatalog.entries.compactMap { entry in
            let snapshot = ModelDownloader.snapshotDirectory(in: base, repo: entry.repo)
            let dir: URL
            if ModelDownloader.isComplete(snapshot) {
                dir = snapshot
            } else if let legacy = legacyDirectoryIfInstalled(
                for: entry,
                hub: legacyHuggingFaceHub
            ) {
                dir = legacy
            } else {
                return nil
            }
            return InstalledModel(id: entry.id, bytesOnDisk: directorySize(dir))
        }
    }

    public static func delete(
        id: String,
        base: URL,
        legacyHuggingFaceHub: URL? = nil
    ) throws {
        guard let entry = ModelCatalog.entry(id: id) else { return }
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: entry.repo)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        if entry.family == .gemma, let legacyHuggingFaceHub {
            let legacy = legacyDirectory(repo: entry.repo, hub: legacyHuggingFaceHub)
            if FileManager.default.fileExists(atPath: legacy.path) {
                try FileManager.default.removeItem(at: legacy)
            }
        }
    }

    static func legacyCacheHasModel(repo: String, hub: URL) -> Bool {
        let dir = legacyDirectory(repo: repo, hub: hub)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return !contents.isEmpty
    }

    private static func legacyDirectoryIfInstalled(
        for entry: ModelCatalogEntry,
        hub: URL?
    ) -> URL? {
        guard entry.family == .gemma,
              let hub,
              legacyCacheHasModel(repo: entry.repo, hub: hub) else { return nil }
        return legacyDirectory(repo: entry.repo, hub: hub)
    }

    private static func legacyDirectory(repo: String, hub: URL) -> URL {
        hub.appendingPathComponent(
            "models--\(repo.replacingOccurrences(of: "/", with: "--"))",
            isDirectory: true
        )
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

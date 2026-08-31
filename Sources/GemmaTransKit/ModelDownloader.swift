import Foundation
import CryptoKit

/// 下载进度。HF 宏路径只有 fraction（字节数未知）；自研下载器两者都有。
public struct DownloadProgress: Sendable, Equatable {
    public let fraction: Double
    public let completedBytes: Int64?
    public let totalBytes: Int64?
    public init(fraction: Double, completedBytes: Int64? = nil, totalBytes: Int64? = nil) {
        self.fraction = fraction
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }
}

/// 模型下载源。默认下载策略会先尝试 Hugging Face，连接不可用时自动回退 ModelScope；
/// 显式 source 只保留给 CLI、诊断和需要固定来源的调用方。
public enum ModelSource: String, Sendable {
    case huggingFace
    case modelScope
}

public enum ModelDownloadError: Error, LocalizedError, Equatable {
    case notHTTPResponse(URL)
    case httpStatus(Int, URL)
    case modelScopeError(code: Int)
    case emptyFileList(repo: String)
    case sizeMismatch(path: String, expected: Int64, actual: Int64)
    case checksumMismatch(path: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .notHTTPResponse(let url): "非 HTTP 响应：\(url)"
        case .httpStatus(let code, let url): "HTTP \(code)：\(url)"
        case .modelScopeError(let code): "ModelScope API 错误 Code=\(code)"
        case .emptyFileList(let repo): "文件列表为空：\(repo)"
        case .sizeMismatch(let path, let expected, let actual):
            "字节数不符 \(path)：期望 \(expected)，实得 \(actual)"
        case .checksumMismatch(let path, let expected, let actual):
            "模型文件校验失败，请重试（\(path)：期望 \(expected)，实得 \(actual)）"
        }
    }
}

/// 自研模型下载器：双源（HuggingFace/ModelScope）+ .part 断点续传 + 字节级进度。
///
/// 替换 swift-huggingface HubClient 下载路径的动机：
/// 1. HubClient 的进度回调在 3.5GB 单文件期间长时间不动（macOS「下载没进度」根因），
///    本下载器按 累计字节/总字节 回调真实进度；
/// 2. 国内网络需要 ModelScope 源，HubClient 只认 HF 布局。
///
/// Swift 6 并发安全：不用 URLSession delegate，全程在调用方的单个 Task 里顺序执行
/// （`URLSession.bytes` 流式读 + `FileHandle` 写），无共享可变状态；
/// progress 闭包标 @Sendable，跨线程安全由调用方保证（与引擎既有约定一致）。
public enum ModelDownloader {

    struct CompletionMarker: Codable, Sendable, Equatable {
        struct File: Codable, Sendable, Equatable {
            let path: String
            let size: Int64
            let sha256: String?
        }

        let version: Int
        let files: [File]
    }

    /// 远端文件描述（两源的列表解析归一到此结构）
    struct RemoteFile: Sendable, Equatable {
        let path: String
        let size: Int64
    }

    /// 推理用不到的仓库杂项，跳过不下载
    static let skippedFiles: Set<String> = [".gitattributes", "README.md", "configuration.json"]

    static let completionMarkerName = ".download-complete"

    /// 写盘缓冲：1MB 一刷，进度回调同频（3.6GB 约 3600 次回调，UI 足够平滑且无开销问题）
    private static let chunkSize = 1 << 20

    /// 自动选源只做轻量探测，不让不可达的 Hugging Face 阻塞完整下载重试。
    private static let sourceProbeTimeout: TimeInterval = 8

    // MARK: - 公开接口

    /// 快照目录：`base/<repo 的 "/" 换 "--">/`
    public static func snapshotDirectory(in base: URL, repo: String) -> URL {
        base.appendingPathComponent(
            repo.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    /// 是否下载完整：兼容 2.0 的字典标记和 2.1 的结构化标记。
    /// 目录存在 ≠ 完整——下载中途被杀的半成品没有标记；文件被外力删改则字节数对不上。
    public static func isComplete(_ dir: URL) -> Bool {
        let marker = dir.appendingPathComponent(completionMarkerName)
        guard let data = try? Data(contentsOf: marker) else { return false }
        if let manifest = try? JSONDecoder().decode(CompletionMarker.self, from: data),
           manifest.version == 2,
           !manifest.files.isEmpty {
            return manifest.files.allSatisfy { file in
                fileSize(at: dir.appendingPathComponent(file.path)) == file.size
            }
        }
        guard let legacy = try? JSONDecoder().decode([String: Int64].self, from: data),
              !legacy.isEmpty else { return false }
        return legacy.allSatisfy { path, size in
            fileSize(at: dir.appendingPathComponent(path)) == size
        }
    }

    /// 对固定单文件模型还要验证完成标记中的文件名、大小和摘要，防止同目录旧文件被误认。
    static func isComplete(_ dir: URL, for entry: ModelCatalogEntry) -> Bool {
        guard case .singleFile(let file) = entry.distribution else { return isComplete(dir) }
        let markerURL = dir.appendingPathComponent(completionMarkerName)
        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(CompletionMarker.self, from: data),
              marker.version == 2,
              marker.files == [CompletionMarker.File(
                path: file.fileName, size: file.bytes, sha256: file.sha256
              )] else { return false }
        return fileSize(at: dir.appendingPathComponent(file.fileName)) == file.bytes
    }

    static func modelFileURL(in dir: URL, for entry: ModelCatalogEntry) -> URL? {
        guard case .singleFile(let file) = entry.distribution else { return nil }
        return dir.appendingPathComponent(file.fileName)
    }

    /// 下载整仓库到快照目录并返回该目录。
    /// source 为 nil 时先尝试 Hugging Face；仅遇到远端连接、HTTP、清单解析或字节校验
    /// 问题才自动回退 ModelScope。取消、磁盘写入等本地错误不会换源掩盖根因。
    /// - 已存在且字节数相符的文件跳过（计入进度基数）
    /// - 每文件先写 `<file>.part`，已有 N 字节则带 `Range: bytes=N-` 续传（ModelScope 206 已实测）；
    ///   完成校验字节数后改名为正式文件，不符删 .part 抛错
    /// - progress 按 累计字节/总字节 回调（字节级真实进度，completed/total 都有值）
    /// - 单文件失败内部重试 2 次后抛出；上层（EngineHolder/调用方）退避重试时
    ///   重调本函数即从断点继续，进度天然包含已落盘部分
    public static func download(
        repo: String,
        from source: ModelSource? = nil,
        into base: URL,
        progress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        if let source {
            return try await download(
                repo: repo,
                from: source,
                into: base,
                reportInitialProgress: true,
                progress: progress
            )
        }

        do {
            try await verifyHuggingFaceReachability(repo: repo)
            return try await download(
                repo: repo,
                from: .huggingFace,
                into: base,
                reportInitialProgress: true,
                progress: progress
            )
        } catch {
            guard shouldFallbackToModelScope(after: error) else { throw error }
            GTLog.info("Hugging Face unavailable for \(repo); falling back to ModelScope: \(error)")
            return try await download(
                repo: repo,
                from: .modelScope,
                into: base,
                reportInitialProgress: false,
                progress: progress
            )
        }
    }

    /// 按目录条目的分发约定下载。旧四款仍走整仓快照；策展 GGUF 只请求固定 revision 的
    /// 唯一文件，不先读仓库清单，也不会把同仓库内的旧 GGUF、报告或图片下载下来。
    public static func download(
        entry: ModelCatalogEntry,
        from source: ModelSource? = nil,
        into base: URL,
        progress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        switch entry.distribution {
        case .repositorySnapshot:
            return try await download(
                repo: entry.repo, from: source, into: base, progress: progress)
        case .singleFile(let file):
            if let source {
                return try await downloadSingleFile(
                    repo: entry.repo, file: file, from: source, into: base,
                    reportInitialProgress: true, progress: progress)
            }
            do {
                return try await downloadSingleFile(
                    repo: entry.repo, file: file, from: .huggingFace, into: base,
                    reportInitialProgress: true, progress: progress)
            } catch {
                guard shouldFallbackToModelScope(after: error) else { throw error }
                GTLog.info("Hugging Face unavailable for \(entry.repo)/\(file.fileName); " +
                           "falling back to ModelScope: \(error)")
                return try await downloadSingleFile(
                    repo: entry.repo, file: file, from: .modelScope, into: base,
                    reportInitialProgress: false, progress: progress)
            }
        }
    }

    /// 自动换源只处理“远端不可用或内容异常”，不处理取消和本地文件系统错误。
    static func shouldFallbackToModelScope(after error: Error) -> Bool {
        if error is CancellationError { return false }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code != NSURLErrorCancelled
        }
        if error is DecodingError { return true }

        guard let downloadError = error as? ModelDownloadError else { return false }
        switch downloadError {
        case .notHTTPResponse, .httpStatus, .emptyFileList, .sizeMismatch, .checksumMismatch:
            return true
        case .modelScopeError:
            return false
        }
    }

    /// 在开始大文件下载前，用短超时验证 Hugging Face 的清单与最大权重首字节。
    /// 只读 1 byte，既覆盖 API 可达性，也覆盖实际承载权重的 CDN/Xet 路径。
    private static func verifyHuggingFaceReachability(repo: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = sourceProbeTimeout
        configuration.timeoutIntervalForResource = sourceProbeTimeout
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let list = listURL(repo: repo, source: .huggingFace)
        let (data, response) = try await session.data(from: list)
        try ensureOK(response, url: list)
        let files = try parseFileList(data, source: .huggingFace)
        guard let probeFile = probeFile(in: files) else {
            throw ModelDownloadError.emptyFileList(repo: repo)
        }

        let url = fileURL(repo: repo, path: probeFile.path, source: .huggingFace)
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (bytes, fileResponse) = try await session.bytes(for: request)
        guard let http = fileResponse as? HTTPURLResponse else {
            throw ModelDownloadError.notHTTPResponse(url)
        }
        guard (200...299).contains(http.statusCode) else {
            throw ModelDownloadError.httpStatus(http.statusCode, url)
        }

        var iterator = bytes.makeAsyncIterator()
        guard try await iterator.next() != nil else {
            throw ModelDownloadError.sizeMismatch(path: probeFile.path, expected: 1, actual: 0)
        }
    }

    private static func download(
        repo: String,
        from source: ModelSource,
        into base: URL,
        reportInitialProgress: Bool,
        progress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        let dir = snapshotDirectory(in: base, repo: repo)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // 卡死检测：60s 收不到数据即抛 NSURLError，交给重试（曾见 HF 直连「无进度挂死」）。
        // timeoutIntervalForResource 给整次取数（含清单与单文件）兜一个上限，避免极端慢网
        // 下某个请求虽偶有零星字节、过不了 60s 空闲超时却也永远下不完，让 UI 无限停在某个百分比。
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 6 * 60 * 60  // 6h
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let list = listURL(repo: repo, source: source)
        let (listData, listResponse) = try await session.data(from: list)
        try ensureOK(listResponse, url: list)
        let files = try parseFileList(listData, source: source)
        guard !files.isEmpty else { throw ModelDownloadError.emptyFileList(repo: repo) }

        // 小文件在前：配置/分词器先就位，大权重殿后（中断时损失最小）
        let ordered = files.sorted { $0.size < $1.size }
        let totalBytes = ordered.reduce(Int64(0)) { $0 + $1.size }
        var doneBytes: Int64 = 0
        // 自研路径字节数已知：completed/total 都给（UI 据此显示「已下/总量」）
        let report: @Sendable (Int64) -> Void = { completed in
            progress(DownloadProgress(
                fraction: fraction(completed, of: totalBytes),
                completedBytes: completed, totalBytes: totalBytes))
        }
        // 清单解析成功即回调一次（首个文件字节到达前）：UI 据此立即从「加载中」切到
        // 「下载 0%」，不会停留在无进度的哑状态；已存在跳过的文件随后在循环里逐个计入
        // （纯磁盘 stat，毫秒级推进进度基数）。
        if reportInitialProgress {
            report(0)
        }

        for file in ordered {
            let dest = dir.appendingPathComponent(file.path)
            if fileSize(at: dest) == file.size {
                doneBytes += file.size  // 已有完整文件：跳过下载，计入进度基数
                report(doneBytes)
                continue
            }
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let url = fileURL(repo: repo, path: file.path, source: source)
            let base = doneBytes
            try await fetchWithRetry(file, from: url, to: dest, session: session) { fileBytes in
                report(base + fileBytes)
            }
            doneBytes += file.size
            report(doneBytes)
        }

        let manifest = CompletionMarker(
            version: 2,
            files: ordered.map { CompletionMarker.File(path: $0.path, size: $0.size, sha256: nil) }
        )
        let markerData = try JSONEncoder().encode(manifest)
        try markerData.write(to: dir.appendingPathComponent(completionMarkerName), options: .atomic)
        GTLog.info("model downloaded: \(repo) via \(source.rawValue), \(ordered.count) files, \(totalBytes) bytes")
        return dir
    }

    // MARK: - 文件列表（纯函数，可单测）

    /// 解析两源的文件列表 JSON：过滤目录项与杂项文件，归一为 RemoteFile
    static func parseFileList(_ data: Data, source: ModelSource) throws -> [RemoteFile] {
        switch source {
        case .huggingFace:
            // GET https://huggingface.co/api/models/<repo>/tree/main?recursive=true
            // → [{type:"file"|"directory", size, path}]（目录项可无 size）
            struct Entry: Decodable {
                let type: String
                let size: Int64?
                let path: String
            }
            let entries = try JSONDecoder().decode([Entry].self, from: data)
            return entries
                .filter { $0.type == "file" && !isSkipped($0.path) }
                .map { RemoteFile(path: $0.path, size: $0.size ?? 0) }
        case .modelScope:
            // GET https://modelscope.cn/api/v1/models/<repo>/repo/files?Revision=master&Recursive=true
            // → {Code:200, Data:{Files:[{Type:"blob"|"tree", Size, Path}]}}
            struct Response: Decodable {
                struct Body: Decodable { let Files: [File] }
                struct File: Decodable {
                    let `Type`: String
                    let Size: Int64
                    let Path: String
                }
                let Code: Int
                let Data: Body
            }
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard response.Code == 200 else {
                throw ModelDownloadError.modelScopeError(code: response.Code)
            }
            return response.Data.Files
                .filter { $0.Type == "blob" && !isSkipped($0.Path) }
                .map { RemoteFile(path: $0.Path, size: $0.Size) }
        }
    }

    static func listURL(repo: String, source: ModelSource) -> URL {
        switch source {
        case .huggingFace:
            URL(string: "https://huggingface.co/api/models/\(repo)/tree/main?recursive=true")!
        case .modelScope:
            URL(string: "https://modelscope.cn/api/v1/models/\(repo)/repo/files?Revision=master&Recursive=true")!
        }
    }

    /// 文件字节端点（两源都 302 到各自 CDN，URLSession 自动跟随）
    static func fileURL(repo: String, path: String, source: ModelSource) -> URL {
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return switch source {
        case .huggingFace:
            URL(string: "https://huggingface.co/\(repo)/resolve/main/\(escaped)")!
        case .modelScope:
            URL(string: "https://modelscope.cn/models/\(repo)/resolve/master/\(escaped)")!
        }
    }

    /// 策展单文件的不可变下载端点。revision 必须是完整提交 ID，不能使用 main/master。
    static func singleFileURL(
        repo: String,
        file: SingleFileDistribution,
        source: ModelSource
    ) -> URL {
        let escaped = file.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? file.fileName
        return switch source {
        case .huggingFace:
            URL(string: "https://huggingface.co/\(repo)/resolve/\(file.huggingFaceRevision)/\(escaped)")!
        case .modelScope:
            URL(string: "https://modelscope.cn/models/\(repo)/resolve/\(file.modelScopeRevision)/\(escaped)")!
        }
    }

    /// 用最大文件探测实际权重分发路径，避免只测小型 JSON 后在权重 CDN 上卡住。
    static func probeFile(in files: [RemoteFile]) -> RemoteFile? {
        files.max { lhs, rhs in lhs.size < rhs.size }
    }

    private static func isSkipped(_ path: String) -> Bool {
        skippedFiles.contains((path as NSString).lastPathComponent)
    }

    // MARK: - 单文件下载

    private static func downloadSingleFile(
        repo: String,
        file: SingleFileDistribution,
        from source: ModelSource,
        into base: URL,
        reportInitialProgress: Bool,
        progress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        let dir = snapshotDirectory(in: base, repo: repo)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(file.fileName)

        if reportInitialProgress {
            progress(DownloadProgress(fraction: 0, completedBytes: 0, totalBytes: file.bytes))
        }

        // 没有标记但完整文件还在时（例如写标记前进程退出），只需重新校验并收口。
        if fileSize(at: dest) == file.bytes {
            let actual = try sha256(of: dest)
            if actual == file.sha256 {
                try writeCompletionMarker(file: file, in: dir)
                progress(DownloadProgress(
                    fraction: 1, completedBytes: file.bytes, totalBytes: file.bytes))
                return dir
            }
            try? fm.removeItem(at: dest)
            GTLog.error("GGUF checksum mismatch source=local revision=existing " +
                        "expected=\(file.sha256) actual=\(actual)")
        } else if fm.fileExists(atPath: dest.path) {
            try? fm.removeItem(at: dest)
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let url = singleFileURL(repo: repo, file: file, source: source)
        let remote = RemoteFile(path: file.fileName, size: file.bytes)
        try await fetchVerifiedSingleWithRetry(
            remote, expectedSHA256: file.sha256, from: url, to: dest, session: session
        ) { completed in
            progress(DownloadProgress(
                fraction: fraction(completed, of: file.bytes),
                completedBytes: completed,
                totalBytes: file.bytes
            ))
        }
        try writeCompletionMarker(file: file, in: dir)
        progress(DownloadProgress(fraction: 1, completedBytes: file.bytes, totalBytes: file.bytes))
        GTLog.info("model downloaded: \(repo)/\(file.fileName) via \(source.rawValue), " +
                   "revision=\(source == .huggingFace ? file.huggingFaceRevision : file.modelScopeRevision), " +
                   "\(file.bytes) bytes sha256=\(file.sha256)")
        return dir
    }

    private static func fetchVerifiedSingleWithRetry(
        _ file: RemoteFile,
        expectedSHA256: String,
        from url: URL,
        to dest: URL,
        session: URLSession,
        fileProgress: @Sendable (Int64) -> Void
    ) async throws {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                try await fetchVerifiedSingleOnce(
                    file, expectedSHA256: expectedSHA256, from: url, to: dest,
                    session: session, fileProgress: fileProgress)
                return
            } catch {
                if isCancellation(error) { throw error }
                attempt += 1
                guard attempt <= 2 else { throw error }
                GTLog.info("download retry \(attempt)/2 for \(file.path): \(error)")
            }
        }
    }

    private static func fetchVerifiedSingleOnce(
        _ file: RemoteFile,
        expectedSHA256: String,
        from url: URL,
        to dest: URL,
        session: URLSession,
        fileProgress: @Sendable (Int64) -> Void
    ) async throws {
        let fm = FileManager.default
        let part = dest.appendingPathExtension("part")
        var existing = fileSize(at: part) ?? 0
        if existing > file.size {
            try fm.removeItem(at: part)
            existing = 0
        }

        if existing < file.size {
            var request = URLRequest(url: url)
            if existing > 0 {
                request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
            }
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ModelDownloadError.notHTTPResponse(url)
            }
            switch (http.statusCode, existing > 0) {
            case (200, false), (206, true):
                break
            case (200, true):
                try fm.removeItem(at: part)
                existing = 0
            default:
                throw ModelDownloadError.httpStatus(http.statusCode, url)
            }
            fileProgress(existing)
            try await writeStream(
                bytes, to: part, resumingAt: existing, fileProgress: fileProgress)
        }

        let actualBytes = fileSize(at: part) ?? 0
        guard actualBytes == file.size else {
            // 短文件可安全续传；超长文件不能，需丢弃。
            if actualBytes > file.size { try? fm.removeItem(at: part) }
            throw ModelDownloadError.sizeMismatch(
                path: file.path, expected: file.size, actual: actualBytes)
        }
        let actualSHA256 = try sha256(of: part)
        guard actualSHA256 == expectedSHA256 else {
            // 摘要错误的完整 .part 不是安全断点，不能继续续传。
            try? fm.removeItem(at: part)
            GTLog.error("GGUF checksum mismatch source=\(url.host ?? "unknown") " +
                        "revision=\(url.pathComponents.dropLast().last ?? "unknown") " +
                        "expected=\(expectedSHA256) actual=\(actualSHA256)")
            throw ModelDownloadError.checksumMismatch(
                path: file.path, expected: expectedSHA256, actual: actualSHA256)
        }
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: part, to: dest)
    }

    private static func writeCompletionMarker(file: SingleFileDistribution, in dir: URL) throws {
        let marker = CompletionMarker(
            version: 2,
            files: [CompletionMarker.File(
                path: file.fileName, size: file.bytes, sha256: file.sha256
            )]
        )
        let data = try JSONEncoder().encode(marker)
        try data.write(to: dir.appendingPathComponent(completionMarkerName), options: .atomic)
    }

    /// CryptoKit 的流式摘要，避免把 440–573 MiB GGUF 一次性读入内存。
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fetchWithRetry(
        _ file: RemoteFile,
        from url: URL,
        to dest: URL,
        session: URLSession,
        fileProgress: @Sendable (Int64) -> Void
    ) async throws {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                try await fetchOnce(file, from: url, to: dest, session: session, fileProgress: fileProgress)
                return
            } catch {
                if isCancellation(error) { throw error }
                attempt += 1
                guard attempt <= 2 else { throw error }
                GTLog.info("download retry \(attempt)/2 for \(file.path): \(error)")
            }
        }
    }

    private static func fetchOnce(
        _ file: RemoteFile,
        from url: URL,
        to dest: URL,
        session: URLSession,
        fileProgress: @Sendable (Int64) -> Void
    ) async throws {
        let fm = FileManager.default
        let part = dest.appendingPathExtension("part")

        var existing = fileSize(at: part) ?? 0
        if existing > file.size {
            try fm.removeItem(at: part)  // 比目标还大：脏数据，从头来
            existing = 0
        }
        if existing == file.size, file.size > 0 {
            try promoteValidated(part: part, to: dest, file: file)  // 上次已下完只差改名（改名前被杀）
            return
        }

        var request = URLRequest(url: url)
        if existing > 0 {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelDownloadError.notHTTPResponse(url)
        }
        switch (http.statusCode, existing > 0) {
        case (200, false), (206, true):
            break  // 全新下载 / 服务端接受 Range 从断点续传
        case (200, true):
            try fm.removeItem(at: part)  // 服务端无视 Range 给了全量：丢弃已有部分从头写
            existing = 0
        default:
            throw ModelDownloadError.httpStatus(http.statusCode, url)
        }
        fileProgress(existing)

        try await writeStream(bytes, to: part, resumingAt: existing, fileProgress: fileProgress)
        try promoteValidated(part: part, to: dest, file: file)
    }

    /// 流式落盘：1MB 缓冲一刷，每刷回调一次累计字节。
    /// 中途网络错误时已写部分留在 .part，下次带 Range 续传。
    private static func writeStream(
        _ bytes: URLSession.AsyncBytes,
        to part: URL,
        resumingAt existing: Int64,
        fileProgress: @Sendable (Int64) -> Void
    ) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: part.path) {
            fm.createFile(atPath: part.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: part)
        defer { try? handle.close() }  // 函数返回即关闭，调用方此后才校验/改名
        try handle.seekToEnd()

        var written = existing
        var buffer = Data(capacity: chunkSize)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                fileProgress(written)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            fileProgress(written)
        }
    }

    /// 校验 .part 字节数后改名为正式文件；不符则删 .part 抛错（重试会从头下，避免续传脏数据）
    private static func promoteValidated(part: URL, to dest: URL, file: RemoteFile) throws {
        let actual = fileSize(at: part) ?? 0
        guard actual == file.size else {
            try? FileManager.default.removeItem(at: part)
            throw ModelDownloadError.sizeMismatch(path: file.path, expected: file.size, actual: actual)
        }
        try? FileManager.default.removeItem(at: dest)  // 旧的字节数不符文件（相符者上游已跳过）
        try FileManager.default.moveItem(at: part, to: dest)
    }

    // MARK: - 杂项

    private static func ensureOK(_ response: URLResponse, url: URL) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ModelDownloadError.notHTTPResponse(url)
        }
        guard http.statusCode == 200 else {
            throw ModelDownloadError.httpStatus(http.statusCode, url)
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private static func fraction(_ done: Int64, of total: Int64) -> Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 1
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.int64Value
    }
}

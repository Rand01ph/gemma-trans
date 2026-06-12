import Foundation

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

/// 模型下载源。HF 的 Xet CDN（cas-bridge.xethub.hf.co）国内不可达、hf-mirror.com 已失效，
/// 故提供 ModelScope（魔搭）作为国内源——同一仓库名在两源的文件清单与字节数完全一致（真机/真网已验证）。
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

    public var errorDescription: String? {
        switch self {
        case .notHTTPResponse(let url): "非 HTTP 响应：\(url)"
        case .httpStatus(let code, let url): "HTTP \(code)：\(url)"
        case .modelScopeError(let code): "ModelScope API 错误 Code=\(code)"
        case .emptyFileList(let repo): "文件列表为空：\(repo)"
        case .sizeMismatch(let path, let expected, let actual):
            "字节数不符 \(path)：期望 \(expected)，实得 \(actual)"
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

    // MARK: - 公开接口

    /// 快照目录：`base/<repo 的 "/" 换 "--">/`
    public static func snapshotDirectory(in base: URL, repo: String) -> URL {
        base.appendingPathComponent(
            repo.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    /// 是否下载完整：完成标记 `.download-complete` 存在，且标记内记录的
    /// 文件名→字节数 逐一与磁盘相符。
    /// 目录存在 ≠ 完整——下载中途被杀的半成品没有标记；文件被外力删改则字节数对不上。
    public static func isComplete(_ dir: URL) -> Bool {
        let marker = dir.appendingPathComponent(completionMarkerName)
        guard let data = try? Data(contentsOf: marker),
              let manifest = try? JSONDecoder().decode([String: Int64].self, from: data),
              !manifest.isEmpty else { return false }
        return manifest.allSatisfy { path, size in
            fileSize(at: dir.appendingPathComponent(path)) == size
        }
    }

    /// 下载整仓库到快照目录并返回该目录。
    /// - 已存在且字节数相符的文件跳过（计入进度基数）
    /// - 每文件先写 `<file>.part`，已有 N 字节则带 `Range: bytes=N-` 续传（ModelScope 206 已实测）；
    ///   完成校验字节数后改名为正式文件，不符删 .part 抛错
    /// - progress 按 累计字节/总字节 回调（字节级真实进度，completed/total 都有值）
    /// - 单文件失败内部重试 2 次后抛出；上层（EngineHolder/调用方）退避重试时
    ///   重调本函数即从断点继续，进度天然包含已落盘部分
    public static func download(
        repo: String,
        from source: ModelSource,
        into base: URL,
        progress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        let dir = snapshotDirectory(in: base, repo: repo)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // 卡死检测：60s 收不到数据即抛 NSURLError，交给重试（曾见 HF 直连「无进度挂死」）
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
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
        report(0)

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

        let manifest = Dictionary(uniqueKeysWithValues: ordered.map { ($0.path, $0.size) })
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

    private static func isSkipped(_ path: String) -> Bool {
        skippedFiles.contains((path as NSString).lastPathComponent)
    }

    // MARK: - 单文件下载

    private static func fetchWithRetry(
        _ file: RemoteFile,
        from url: URL,
        to dest: URL,
        session: URLSession,
        fileProgress: @Sendable (Int64) -> Void
    ) async throws {
        var attempt = 0
        while true {
            do {
                try await fetchOnce(file, from: url, to: dest, session: session, fileProgress: fileProgress)
                return
            } catch {
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

    private static func fraction(_ done: Int64, of total: Int64) -> Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 1
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.int64Value
    }
}

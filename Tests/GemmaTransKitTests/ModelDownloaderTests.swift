import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct ModelDownloaderTests {

    // MARK: - 文件列表解析（fixture 为真实 API 响应的精简版，字节数取自真实仓库）

    /// HF: GET https://huggingface.co/api/models/<repo>/tree/main?recursive=true
    /// 目录项故意不带 size，验证可选字段解码
    private let hfFixture = Data("""
    [
      {"type":"file","oid":"a1","size":1519,"path":".gitattributes"},
      {"type":"file","oid":"a2","size":9684,"path":"README.md"},
      {"type":"file","oid":"a3","size":111,"path":"configuration.json"},
      {"type":"file","oid":"a4","size":5996,"path":"config.json"},
      {"type":"file","oid":"a5","size":3581101896,"path":"model.safetensors","lfs":{"size":3581101896}},
      {"type":"directory","oid":"a6","path":"assets"},
      {"type":"file","oid":"a7","size":32169626,"path":"assets/tokenizer.json"}
    ]
    """.utf8)

    /// ModelScope: GET https://modelscope.cn/api/v1/models/<repo>/repo/files?Revision=master&Recursive=true
    private let msFixture = Data("""
    {"Code":200,"Data":{"Files":[
      {"Name":".gitattributes","Path":".gitattributes","Size":1519,"Type":"blob"},
      {"Name":"README.md","Path":"README.md","Size":9684,"Type":"blob"},
      {"Name":"configuration.json","Path":"configuration.json","Size":111,"Type":"blob"},
      {"Name":"config.json","Path":"config.json","Size":5996,"Type":"blob"},
      {"Name":"model.safetensors","Path":"model.safetensors","Size":3581101896,"Type":"blob"},
      {"Name":"assets","Path":"assets","Size":0,"Type":"tree"}
    ]},"Message":"success","RequestId":"r1","Success":true}
    """.utf8)

    @Test func parseHuggingFaceListFiltersAndExtracts() throws {
        let files = try ModelDownloader.parseFileList(hfFixture, source: .huggingFace)
        #expect(files == [
            ModelDownloader.RemoteFile(path: "config.json", size: 5996),
            ModelDownloader.RemoteFile(path: "model.safetensors", size: 3_581_101_896),
            ModelDownloader.RemoteFile(path: "assets/tokenizer.json", size: 32_169_626),
        ])
    }

    @Test func parseModelScopeListFiltersAndExtracts() throws {
        let files = try ModelDownloader.parseFileList(msFixture, source: .modelScope)
        #expect(files == [
            ModelDownloader.RemoteFile(path: "config.json", size: 5996),
            ModelDownloader.RemoteFile(path: "model.safetensors", size: 3_581_101_896),
        ])
    }

    @Test func parseModelScopeNon200CodeThrows() {
        let bad = Data(#"{"Code":10010101,"Data":{"Files":[]},"Message":"get model failed"}"#.utf8)
        #expect(throws: ModelDownloadError.modelScopeError(code: 10010101)) {
            try ModelDownloader.parseFileList(bad, source: .modelScope)
        }
    }

    // MARK: - 下载端点拼接

    @Test func endpointURLs() {
        let repo = "mlx-community/gemma-4-e2b-it-4bit"
        #expect(ModelDownloader.listURL(repo: repo, source: .huggingFace).absoluteString
            == "https://huggingface.co/api/models/mlx-community/gemma-4-e2b-it-4bit/tree/main?recursive=true")
        #expect(ModelDownloader.listURL(repo: repo, source: .modelScope).absoluteString
            == "https://modelscope.cn/api/v1/models/mlx-community/gemma-4-e2b-it-4bit/repo/files?Revision=master&Recursive=true")
        #expect(ModelDownloader.fileURL(repo: repo, path: "model.safetensors", source: .huggingFace).absoluteString
            == "https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit/resolve/main/model.safetensors")
        #expect(ModelDownloader.fileURL(repo: repo, path: "model.safetensors", source: .modelScope).absoluteString
            == "https://modelscope.cn/models/mlx-community/gemma-4-e2b-it-4bit/resolve/master/model.safetensors")
    }

    @Test func curatedSingleFileURLsPinBothRevisions() throws {
        let entry = try #require(ModelCatalog.entry(id: "hymt2-1.25bit"))
        let file: SingleFileDistribution
        if case .singleFile(let value) = entry.distribution {
            file = value
        } else {
            Issue.record("expected single-file distribution")
            return
        }
        #expect(ModelDownloader.singleFileURL(
            repo: entry.repo, file: file, source: .huggingFace).absoluteString ==
            "https://huggingface.co/AngelSlim/Hy-MT2-1.8B-1.25Bit-GGUF/resolve/0989912c0cc2d3edeeecd76171d1c7d94ee17255/Hy-MT2-1.8B-1.25bit-v2.gguf")
        #expect(ModelDownloader.singleFileURL(
            repo: entry.repo, file: file, source: .modelScope).absoluteString ==
            "https://modelscope.cn/models/AngelSlim/Hy-MT2-1.8B-1.25Bit-GGUF/resolve/2d3896c601bb165415669c31e8cf43c2554e7900/Hy-MT2-1.8B-1.25bit-v2.gguf")
    }

    @Test func automaticSourceFallbackOnlyHandlesRemoteFailures() {
        let networkError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: nil
        )
        #expect(ModelDownloader.shouldFallbackToModelScope(after: networkError))
        #expect(ModelDownloader.shouldFallbackToModelScope(after:
            ModelDownloadError.httpStatus(503, URL(string: "https://huggingface.co")!)))
        #expect(ModelDownloader.shouldFallbackToModelScope(after:
            ModelDownloadError.emptyFileList(repo: "mlx-community/model")))

        #expect(!ModelDownloader.shouldFallbackToModelScope(after: CancellationError()))
        #expect(!ModelDownloader.shouldFallbackToModelScope(after:
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)))
        #expect(!ModelDownloader.shouldFallbackToModelScope(after:
            NSError(domain: NSCocoaErrorDomain, code: 640, userInfo: nil)))
    }

    @Test func sourceProbeTargetsLargestRemoteFile() throws {
        let files = try ModelDownloader.parseFileList(hfFixture, source: .huggingFace)
        #expect(ModelDownloader.probeFile(in: files)?.path == "model.safetensors")
    }

    // MARK: - 快照目录

    @Test func snapshotDirectoryReplacesSlashes() {
        let base = URL(fileURLWithPath: "/tmp/models")
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: "mlx-community/gemma-4-e2b-it-4bit")
        #expect(dir.path == "/tmp/models/mlx-community--gemma-4-e2b-it-4bit")
        #expect(dir.hasDirectoryPath)
    }

    // MARK: - 完成判定

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelDownloaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeMarker(_ manifest: [String: Int64], in dir: URL) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: dir.appendingPathComponent(ModelDownloader.completionMarkerName))
    }

    @Test func isCompleteWhenMarkerMatchesDisk() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0, count: 10).write(to: dir.appendingPathComponent("config.json"))
        try Data(repeating: 0, count: 3).write(to: dir.appendingPathComponent("model.safetensors"))
        try writeMarker(["config.json": 10, "model.safetensors": 3], in: dir)
        #expect(ModelDownloader.isComplete(dir))
    }

    @Test func isCompleteFalseWithoutMarker() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0, count: 10).write(to: dir.appendingPathComponent("config.json"))
        #expect(!ModelDownloader.isComplete(dir))
    }

    @Test func isCompleteFalseOnSizeMismatch() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0, count: 9).write(to: dir.appendingPathComponent("config.json"))
        try writeMarker(["config.json": 10], in: dir)
        #expect(!ModelDownloader.isComplete(dir))
    }

    @Test func isCompleteFalseWhenListedFileMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0, count: 10).write(to: dir.appendingPathComponent("config.json"))
        try writeMarker(["config.json": 10, "model.safetensors": 3], in: dir)
        #expect(!ModelDownloader.isComplete(dir))
    }

    @Test func isCompleteFalseOnEmptyManifest() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeMarker([:], in: dir)
        #expect(!ModelDownloader.isComplete(dir))
    }

    @Test func structuredMarkerBindsCuratedFileMetadata() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let entry = try #require(ModelCatalog.entry(id: "hymt2-1.25bit"))
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: entry.repo)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file: SingleFileDistribution
        if case .singleFile(let value) = entry.distribution {
            file = value
        } else {
            Issue.record("expected single-file distribution")
            return
        }
        _ = FileManager.default.createFile(
            atPath: dir.appendingPathComponent(file.fileName).path,
            contents: nil
        )
        // 使用 0 字节 fixture 验证 marker 绑定逻辑，避免单测创建 440 MiB 文件。
        let marker = ModelDownloader.CompletionMarker(
            version: 2,
            files: [.init(path: file.fileName, size: 0, sha256: file.sha256)]
        )
        try JSONEncoder().encode(marker).write(
            to: dir.appendingPathComponent(ModelDownloader.completionMarkerName))
        #expect(ModelDownloader.isComplete(dir))
        #expect(!ModelDownloader.isComplete(dir, for: entry))
    }

    @Test func cryptoKitSHA256IsIncrementalAndStable() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("digest.bin")
        try Data("abc".utf8).write(to: file)
        #expect(try ModelDownloader.sha256(of: file) ==
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

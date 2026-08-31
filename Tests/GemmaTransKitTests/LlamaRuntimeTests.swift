import Foundation
import Testing
@testable import GemmaTransKit

@Suite(.serialized) struct LlamaRuntimeTests {
    @Test func utf8AccumulatorJoinsCodePointAcrossPieces() throws {
        var accumulator = UTF8StreamAccumulator()
        #expect(accumulator.append([0xE4]) == nil)
        #expect(accumulator.append([0xBD]) == nil)
        #expect(accumulator.append([0xA0]) == "你")
        try accumulator.finish()
    }

    @Test func utf8AccumulatorRejectsIncompleteTail() {
        var accumulator = UTF8StreamAccumulator()
        #expect(accumulator.append([0xE4, 0xBD]) == nil)
        #expect(throws: LlamaRuntimeError.invalidUTF8) {
            try accumulator.finish()
        }
    }

    /// 本地/发布门通过 GT_STQ_MODEL 与 GT_Q2C_MODEL 注入固定 v2 文件；普通 CI 无大模型时跳过。
    @Test func curatedModelsUseOneRuntimeAndCanSwitchBack() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let stqPath = environment["GT_STQ_MODEL"],
              let q2cPath = environment["GT_Q2C_MODEL"] else { return }

        let runtime = LlamaRuntime()
        try await runtime.load(
            fileURL: URL(fileURLWithPath: stqPath), quantization: .stq1_0)
        let first = try await translateOnce(runtime)
        #expect(first.contains("Hello") || first.contains("GemmaTrans"))
        await runtime.unload()

        try await runtime.load(
            fileURL: URL(fileURLWithPath: q2cPath), quantization: .q2_0c)
        let second = try await translateOnce(runtime)
        #expect(second.contains("Hello") || second.contains("GemmaTrans"))
        await runtime.unload()

        try await runtime.load(
            fileURL: URL(fileURLWithPath: stqPath), quantization: .stq1_0)
        let switchedBack = try await translateOnce(runtime)
        #expect(!switchedBack.isEmpty)
        await runtime.unload()
    }

    @Test func translationEngineRoutesGGUFAndCancelsPromptDecode() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let stqPath = environment["GT_STQ_MODEL"] else { return }
        let entry = try #require(ModelCatalog.entry(id: "hymt2-1.25bit"))
        guard case .singleFile(let file) = entry.distribution else {
            Issue.record("expected single-file distribution")
            return
        }

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LlamaEngineTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let snapshot = ModelDownloader.snapshotDirectory(in: base, repo: entry.repo)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.linkItem(
            at: URL(fileURLWithPath: stqPath),
            to: snapshot.appendingPathComponent(file.fileName)
        )
        let marker = ModelDownloader.CompletionMarker(
            version: 2,
            files: [.init(path: file.fileName, size: file.bytes, sha256: file.sha256)]
        )
        try JSONEncoder().encode(marker).write(
            to: snapshot.appendingPathComponent(ModelDownloader.completionMarkerName))

        let engine = TranslationEngine(settings: AppSettings())
        let resolved = try #require(ActiveModelResolver.resolve(selectedID: entry.id))
        try await engine.load(resolved: resolved, cacheDirectory: base)
        let translated = try await engine.translate("你好，欢迎使用 GemmaTrans。", target: "en")
        #expect(try await translated.fullText().contains("GemmaTrans"))

        let longTranslation = try await engine.translate(
            String(repeating: "这是一个用于验证取消响应速度的长输入。", count: 100),
            target: "en"
        )
        let consumer = Task {
            for try await _ in longTranslation.chunks {}
        }
        try await Task.sleep(for: .milliseconds(50))
        let started = ContinuousClock.now
        consumer.cancel()
        _ = try? await consumer.value
        let elapsed = ContinuousClock.now - started
        #expect(elapsed < .seconds(1))
        await engine.unload()
    }

    @Test func curatedQualityCorpusHasRequiredCoverage() throws {
        let corpus = try qualityCorpus()
        #expect(corpus.filter { $0.category == "zh-en" }.count == 10)
        #expect(corpus.filter { $0.category == "en-zh" }.count == 10)
        #expect(corpus.filter { $0.category == "mixed" }.count >= 8)
        for language in ["ja", "ko", "fr", "de", "es", "ru", "ar"] {
            #expect(corpus.filter { $0.category == "other-zh" && $0.sourceLanguage == language }.count == 2)
        }
        #expect(Set(corpus.map(\.id)).count == corpus.count)
    }

    /// 正式质量门由 GT_RUN_QUALITY_CORPUS=1 显式开启；普通 CI 不下载或运行大模型。
    /// 自动检查结构性缺陷，语义正确率和关键语义反转仍以 TestFlight 人工复核为准。
    @Test func realCuratedModelsPassStructuralQualityCorpus() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GT_RUN_QUALITY_CORPUS"] == "1",
              let stqPath = environment["GT_STQ_MODEL"],
              let q2cPath = environment["GT_Q2C_MODEL"] else { return }

        let corpus = try qualityCorpus()
        let runtime = LlamaRuntime()
        for (path, quantization, label) in [
            (stqPath, GGUFQuantization.stq1_0, "1.25-bit"),
            (q2cPath, GGUFQuantization.q2_0c, "2-bit"),
        ] {
            try await runtime.load(fileURL: URL(fileURLWithPath: path), quantization: quantization)
            for item in corpus {
                let output = try await qualityTranslate(runtime, item: item)
                #expect(!output.isEmpty, Comment(rawValue: "\(label) \(item.id): empty"))
                #expect(output != item.source, Comment(rawValue: "\(label) \(item.id): source echoed"))
                #expect(!output.localizedCaseInsensitiveContains("additional explanation"),
                        Comment(rawValue: "\(label) \(item.id): prompt leaked"))
                #expect(!output.contains("<｜") && !output.contains("<|") &&
                        !output.contains("[end of text]"),
                        Comment(rawValue: "\(label) \(item.id): special token leaked"))
                for token in item.mustPreserve {
                    #expect(output.contains(token),
                            Comment(rawValue: "\(label) \(item.id): missing \(token)"))
                }
            }
            await runtime.unload()
        }
    }

    private func translateOnce(_ runtime: LlamaRuntime) async throws -> String {
        final class Output: @unchecked Sendable {
            let lock = NSLock()
            var text = ""
            func append(_ chunk: String) {
                lock.lock()
                text += chunk
                lock.unlock()
            }
        }
        let output = Output()
        let metrics = try await runtime.generate(
            userPrompt: PromptBuilder.userPrompt(text: "你好，欢迎使用 GemmaTrans。", target: "en"),
            maxTokens: 64,
            onChunk: { output.append($0) }
        )
        #expect(metrics.firstTokenSeconds < 3)
        #expect(metrics.tokensPerSecond >= 8)
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct QualityCase: Decodable {
        let id: String
        let category: String
        let sourceLanguage: String
        let target: String
        let source: String
        let mustPreserve: [String]
    }

    private func qualityCorpus() throws -> [QualityCase] {
        let url = try #require(Bundle.module.url(
            forResource: "hymt2-quality", withExtension: "json"))
        return try JSONDecoder().decode([QualityCase].self, from: Data(contentsOf: url))
    }

    private func qualityTranslate(_ runtime: LlamaRuntime, item: QualityCase) async throws -> String {
        final class Output: @unchecked Sendable {
            private let lock = NSLock()
            private var value = ""
            func append(_ text: String) { lock.withLock { value += text } }
            func read() -> String { lock.withLock { value } }
        }
        let output = Output()
        _ = try await runtime.generate(
            userPrompt: PromptBuilder.userPrompt(text: item.source, target: item.target),
            maxTokens: 96,
            onChunk: { output.append($0) }
        )
        return output.read().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

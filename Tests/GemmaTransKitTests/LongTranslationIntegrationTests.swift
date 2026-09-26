import Foundation
import Testing
@testable import GemmaTransKit

@Suite(.serialized) struct LongTranslationIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GT_LONG_MODEL_BASE"] != nil),
          arguments: ["hymt2-4bit", "hymt2-1.25bit"])
    func translatesEntireArticle(modelID: String) async throws {
        let env = ProcessInfo.processInfo.environment
        let base = URL(fileURLWithPath: try #require(env["GT_LONG_MODEL_BASE"]))
        let resolved = try #require(ActiveModelResolver.resolve(selectedID: modelID))
        let snapshot = ModelDownloader.snapshotDirectory(in: base, repo: resolved.entry.repo)
        #expect(ModelDownloader.isComplete(snapshot, for: resolved.entry))
        guard ModelDownloader.isComplete(snapshot, for: resolved.entry) else { return }
        let engine = TranslationEngine(settings: AppSettings())
        try await engine.load(resolved: resolved, cacheDirectory: base)
        let paragraphs = (1...12).map { number in
            "GT\(String(format: "%03d", number)): The library opens at nine in the morning. Visitors can read books, borrow a computer, and ask for help at the front desk. Please keep this reference code unchanged when translating. Every Saturday, the library offers a free workshop for families who want to learn about local history."
        }
        let source = paragraphs.joined(separator: "\n\n")
        let result = try await engine.translate(source, target: "zh-Hans")
        let output = try await result.fullText()
        let metrics = await result.statistics.metrics
        #expect(!result.truncated)
        #expect(metrics?.tokensPerSecond != nil)
        var previous = output.startIndex
        for n in 1...12 {
            let marker = String(format: "GT%03d", n)
            #expect(output.components(separatedBy: marker).count == 2)
            if let range = output.range(of: marker) {
                #expect(range.lowerBound >= previous)
                previous = range.upperBound
            } else { Issue.record("Missing article marker: \(marker)") }
        }
        if let destination = env["GT_LONG_REPORT"] {
            let directory = URL(fileURLWithPath: destination)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try source.write(to: directory.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)
            try output.write(to: directory.appendingPathComponent(modelID + ".txt"), atomically: true, encoding: .utf8)
            let summary: [String: Any] = ["model": modelID, "inputCharacters": source.count,
                "outputCharacters": output.count, "tokensPerSecond": metrics?.tokensPerSecond ?? 0,
                "allMarkers": (1...12).allSatisfy { output.contains(String(format: "GT%03d", $0)) }]
            try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent(modelID + ".json"))
        }
        await engine.unload()
    }
}

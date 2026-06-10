import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct EngineIntegrationTests {
    static var modelPath: String? {
        let env = ProcessInfo.processInfo.environment["GEMMA_MODEL_PATH"]
        let fallback = AppSettings().modelPath
        if let env, FileManager.default.fileExists(atPath: env) { return env }
        if FileManager.default.fileExists(atPath: fallback) { return fallback }
        return nil
    }

    @Test(.enabled(if: modelPath != nil))
    func translatesEnglishToChinese() async throws {
        var settings = AppSettings()
        settings.modelPath = Self.modelPath!
        let engine = TranslationEngine(settings: settings)
        try await engine.load()
        let result = try await engine.translate("Good morning", target: nil)
        #expect(result.detected == "en")
        #expect(result.target == "zh-Hans")
        let text = try await result.fullText()
        #expect(!text.isEmpty)
        print("译文: \(text)")
    }
}

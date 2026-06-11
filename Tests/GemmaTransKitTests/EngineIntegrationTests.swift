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

    /// 去抖依据：生成进行中 isGenerating 为真，完整消费后归假
    @Test(.enabled(if: modelPath != nil))
    func isGeneratingReflectsInflightWork() async throws {
        var settings = AppSettings()
        settings.modelPath = Self.modelPath!
        let engine = TranslationEngine(settings: settings)
        try await engine.load()
        #expect(await engine.isGenerating == false)
        let result = try await engine.translate("Good evening", target: nil)
        #expect(await engine.isGenerating == true)   // 生成已排队，尚未消费
        _ = try await result.fullText()
        // 计数器在生成任务收尾时归零，比流结束晚极小一段；最终一致即可（去抖按秒计，无影响）
        try await Task.sleep(for: .milliseconds(50))
        #expect(await engine.isGenerating == false)
    }
}

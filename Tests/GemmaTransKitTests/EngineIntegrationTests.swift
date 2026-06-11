import Testing
import Foundation
@testable import GemmaTransKit

/// 注意：MLX 的 Metal 着色器无法经 `swift test` 编译运行——本 suite 必须经
/// xcodebuild 跑（xcodebuild test -scheme gemma-trans-Package …）或在 Xcode 中执行。
/// `swift test` 下用 GEMMA_MLX_TEST=1 才启用，避免默认全量测试因 metallib 崩溃。
@Suite struct EngineIntegrationTests {
    static var enabled: Bool {
        // Hub 缓存存在（模型已下载）且显式要求跑 MLX 集成
        let cache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--mlx-community--gemma-4-e4b-it-4bit")
        return FileManager.default.fileExists(atPath: cache.path)
            && ProcessInfo.processInfo.environment["GEMMA_MLX_TEST"] == "1"
    }

    @Test(.enabled(if: enabled))
    func translatesEnglishToChinese() async throws {
        let engine = TranslationEngine(settings: AppSettings())
        try await engine.load()
        let result = try await engine.translate("Good morning", target: nil)
        #expect(result.detected == "en")
        #expect(result.target == "zh-Hans")
        let text = try await result.fullText()
        #expect(!text.isEmpty)
        print("译文: \(text)")
    }

    /// 去抖依据：生成进行中 isGenerating 为真，完整消费后归假
    @Test(.enabled(if: enabled))
    func isGeneratingReflectsInflightWork() async throws {
        let engine = TranslationEngine(settings: AppSettings())
        try await engine.load()
        #expect(await engine.isGenerating == false)
        let result = try await engine.translate("Good evening", target: nil)
        #expect(await engine.isGenerating == true)
        _ = try await result.fullText()
        // 计数器在生成任务收尾时归零，比流结束晚极小一段；最终一致即可（去抖按秒计，无影响）
        try await Task.sleep(for: .milliseconds(50))
        #expect(await engine.isGenerating == false)
    }
}

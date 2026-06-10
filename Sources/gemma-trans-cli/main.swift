import Foundation
import GemmaTransKit
import GemmaTransServer
import LiteRTLM

// 重定向到文件/管道时 print 默认块缓冲，"Model ready" 等状态行会滞留不可见
setvbuf(stdout, nil, _IOLBF, 0)

let settings: AppSettings = {
    var s = AppSettings.load()
    if let p = ProcessInfo.processInfo.environment["GEMMA_MODEL_PATH"] { s.modelPath = p }
    return s
}()

let mode = CommandLine.arguments.dropFirst().first ?? "serve"

switch mode {
case "spike":
    await runSpike(settings: settings)
case "serve":
    let engine = TranslationEngine(settings: settings)
    print("Loading model: \(settings.modelPath)")
    do { try await engine.load() } catch {
        print("模型加载失败: \(error)\n请确认模型文件存在，下载命令见 README。")
        exit(1)
    }
    print("Model ready. Listening on http://127.0.0.1:\(settings.port)")
    let api = APIServer(translator: engine, port: settings.port)
    try await api.run()
default:
    print("usage: gemma-trans-cli [spike|serve]")
    exit(2)
}

/// 可行性 spike：直接走 LiteRT-LM 原生 API 加载模型并流式翻译一句话。
func runSpike(settings: AppSettings) async {
    do {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GemmaTrans").path
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

        print("Loading model: \(settings.modelPath)")
        let clock = ContinuousClock()
        let loadStart = clock.now
        let config = try EngineConfig(
            modelPath: settings.modelPath,
            backend: .gpu,
            maxNumTokens: 4096,
            cacheDir: cacheDir
        )
        let engine = Engine(engineConfig: config)
        try await engine.initialize()
        print("Model ready in \(clock.now - loadStart). Translating…")

        let genStart = clock.now
        let prompt = "Translate the following text into Simplified Chinese. Output only the translation.\n\nThe quick brown fox jumps over the lazy dog."
        try await engine.spikeStream(prompt: prompt)
        print("\n--- spike OK (generation took \(clock.now - genStart)) ---")
    } catch {
        print("SPIKE FAILED: \(error)")
        exit(1)
    }
}

extension Engine {
    /// Conversation 非 Sendable，整个流式过程留在 Engine actor 内。
    func spikeStream(prompt: String) async throws {
        let conversation = try createConversation()
        for try await chunk in conversation.sendMessageStream(Message(prompt)) {
            print(chunk.toString, terminator: "")
        }
    }
}

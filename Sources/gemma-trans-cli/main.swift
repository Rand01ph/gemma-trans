import Foundation
import GemmaTransKit
import GemmaTransServer

// 重定向到文件/管道时 print 默认块缓冲，"Model ready" 等状态行会滞留不可见
setvbuf(stdout, nil, _IOLBF, 0)

// 注意：MLX 的 Metal 着色器无法用 `swift build` 编译，本 CLI 需经 xcodebuild 构建：
//   xcodebuild -scheme gemma-trans-cli -destination 'platform=macOS' -skipMacroValidation build
let settings = AppSettings.load()
let mode = CommandLine.arguments.dropFirst().first ?? "serve"

switch mode {
case "spike":
    // 可行性验证：经统一引擎跑一次流式翻译（首次自动下载模型）
    let clock = ContinuousClock()
    let engine = TranslationEngine(settings: settings)
    do {
        let loadStart = clock.now
        try await engine.load { p in
            print("download: \(Int(p * 100))%", terminator: "\r")
        }
        print("\nModel ready in \(clock.now - loadStart)")
        let genStart = clock.now
        let result = try await engine.translate(
            "The quick brown fox jumps over the lazy dog.", target: nil)
        for try await chunk in result.chunks {
            print(chunk, terminator: "")
        }
        print("\n--- spike OK (\(clock.now - genStart)) ---")
    } catch {
        print("SPIKE FAILED: \(error)")
        exit(1)
    }
case "serve":
    let engine = TranslationEngine(settings: settings)
    print("Loading model (首次自动下载约 1.5-2.4GB)…")
    do {
        try await engine.load { p in
            print("download: \(Int(p * 100))%", terminator: "\r")
        }
    } catch {
        print("模型加载失败: \(error)")
        exit(1)
    }
    print("Model ready. Listening on http://127.0.0.1:\(settings.port)")
    let api = APIServer(translator: engine, port: settings.port)
    try await api.run()
default:
    print("usage: gemma-trans-cli [spike|serve]")
    exit(2)
}

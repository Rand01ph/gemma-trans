import Foundation
import GemmaTransKit
import GemmaTransServer

// 重定向到文件/管道时 print 默认块缓冲，"Model ready" 等状态行会滞留不可见
setvbuf(stdout, nil, _IOLBF, 0)

/// 「download: 35% (1.2/3.4 GB)」；字节未知（HF 宏路径）时只打百分比
func printDownloadProgress(_ p: DownloadProgress) {
    let pct = Int(p.fraction * 100)
    if let done = p.completedBytes, let total = p.totalBytes {
        let bytes = String(format: "%.1f/%.1f GB", Double(done) / 1e9, Double(total) / 1e9)
        print("download: \(pct)% (\(bytes))", terminator: "\r")
    } else {
        print("download: \(pct)%", terminator: "\r")
    }
}

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
            printDownloadProgress(p)
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
            printDownloadProgress(p)
        }
    } catch {
        print("模型加载失败: \(error)")
        exit(1)
    }
    print("Model ready. Listening on http://127.0.0.1:\(settings.port)")
    let api = APIServer(translator: engine, port: settings.port)
    try await api.run()
case "download-e2b":
    // iOS 真机配套：国内网络 HF Xet CDN（cas-bridge.xethub.hf.co）被墙、hf-mirror 已失效，
    // 手机端直连 HF 不可达。此命令在 Mac 上用与 iOS 完全相同的代码路径（ModelDownloader
    // 快照布局 + E2B 档）下载到指定目录，再经 devicectl 推入手机 App Group 容器。
    // 第三个参数选下载源：hf（HuggingFace）| ms（ModelScope，默认，国内可达且支持断点续传）。
    let args = CommandLine.arguments.dropFirst(2)
    guard let dir = args.first else {
        print("usage: gemma-trans-cli download-e2b <cache-dir> [hf|ms]")
        exit(2)
    }
    let source: ModelSource
    switch args.dropFirst().first ?? "ms" {
    case "hf": source = .huggingFace
    case "ms": source = .modelScope
    default:
        print("usage: gemma-trans-cli download-e2b <cache-dir> [hf|ms]")
        exit(2)
    }
    let engine = TranslationEngine(settings: settings)
    do {
        try await engine.load(
            cacheDirectory: URL(fileURLWithPath: dir),
            modelSource: source,
            tuningOverride: EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700)
        ) { p in
            printDownloadProgress(p)
        }
        print("\nE2B 下载完成且已验证可加载（含预热）：\(dir)")
    } catch {
        print("DOWNLOAD FAILED: \(error)")
        exit(1)
    }
case "hunyuan-spike":
    // Plan A 决策门：注册混元类型 → 从本地目录加载 Hy-MT2 → 跑一次生成，人工核对输出。
    let args = CommandLine.arguments.dropFirst(2)
    guard let dir = args.first else {
        print("usage: gemma-trans-cli hunyuan-spike <model-dir> [text]")
        exit(2)
    }
    let text = args.dropFirst().first
        ?? "Translate the following Chinese into English:\n今天天气很好，我们一起去公园散步吧。"
    let clock = ContinuousClock()
    do {
        let t0 = clock.now
        print("--- output ---")
        let out = try await hunyuanSpikeTranslate(
            modelDir: URL(fileURLWithPath: dir), text: text)
        print("--- hunyuan-spike done in \(clock.now - t0), \(out.count) chars ---")
    } catch {
        print("HUNYUAN-SPIKE FAILED: \(error)")
        exit(1)
    }
case "engine-translate":
    // Plan C 验证：走正式引擎路径（load(resolved:) + translate）测某 catalog 模型的端到端翻译。
    let args = Array(CommandLine.arguments.dropFirst(2))
    guard args.count >= 2 else {
        print("usage: gemma-trans-cli engine-translate <model-id> <cache-dir> [text]")
        exit(2)
    }
    let resolved = ActiveModelResolver.resolve(
        selectedID: args[0],
        physicalMemory: SystemMemory.physical(),
        availableMemory: SystemMemory.available())
    let engine = TranslationEngine(settings: settings)
    do {
        try await engine.load(
            resolved: resolved,
            cacheDirectory: URL(fileURLWithPath: args[1]),
            modelSource: .modelScope
        ) { p in printDownloadProgress(p) }
        let text = args.count >= 3 ? args[2] : "今天天气很好，我们一起去公园散步吧。"
        print("\n--- translate via engine (family=\(resolved.entry.family.rawValue)) ---")
        let result = try await engine.translate(text, target: nil)
        for try await chunk in result.chunks { print(chunk, terminator: "") }
        print("\n--- engine-translate OK (detected=\(result.detected) target=\(result.target)) ---")
    } catch {
        print("ENGINE-TRANSLATE FAILED: \(error)")
        exit(1)
    }
default:
    print("usage: gemma-trans-cli [spike|serve|hunyuan-spike <model-dir> [text]|engine-translate <model-id> <cache-dir> [text]|download-e2b <cache-dir> [hf|ms]]")
    exit(2)
}

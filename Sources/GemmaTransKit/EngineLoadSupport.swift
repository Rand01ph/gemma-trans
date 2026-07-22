import Foundation

/// 引擎加载的跨端共享支持：网络退避重试 + 失败信息人话化。
/// 由 iOS EngineHolder 上移而来，macOS EngineController 与 iOS 共用一份，
/// 避免两端各自维护重试/文案逻辑导致体验漂移。

/// 网络类错误自动重试（真机现象：3.6GB 下载途中 NSURLError -1005「连接断开」）。
/// ModelDownloader 以 .part 文件 + Range 头断点续传：重调 op 即从断点继续，
/// 字节级进度回调含已落盘部分——重试期间调用方的 UI 状态无需重置，续传自会推进进度。
/// 非 NSURLErrorDomain 错误（解析失败、磁盘满等）不重试，原样抛出。
/// - Parameter onRetry: 每次决定重试后、退避休眠前回调（attempt 为即将进行的第几次重试，
///   1 起算）。UI 用它把「静默退避」变成可见的「网络异常，Ns 后第 a/m 次重试…」；
///   默认 nil，既有调用点零改动。
public func withNetworkRetry<T: Sendable>(
    onRetry: (@Sendable (_ attempt: Int, _ maxRetries: Int, _ delaySeconds: Int) -> Void)? = nil,
    _ op: @Sendable () async throws -> T
) async throws -> T {
    let backoffSeconds: [UInt64] = [2, 4, 8, 15, 15]  // 最多重试 5 次，退避 min 封顶 15s
    var attempt = 0
    while true {
        do {
            return try await op()
        } catch {
            let nsError = error as NSError
            guard nsError.domain == NSURLErrorDomain, attempt < backoffSeconds.count else {
                throw error
            }
            let delay = backoffSeconds[attempt]
            attempt += 1
            GTLog.info("engine load network error (code \(nsError.code)), retry \(attempt)/\(backoffSeconds.count) in \(delay)s")
            onRetry?(attempt, backoffSeconds.count, Int(delay))
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
        }
    }
}

/// 失败信息人性化：网络错误和模型结构不兼容错误给可行动的短句，
/// 其他错误截断 120 字符防 NSError 全文刷屏 UI（完整错误由调用方落日志）。
public func engineLoadFailureMessage(for error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        return "网络中断（已下载部分已保留，可重试继续）[\(nsError.code)]"
    }

    let description = String(describing: error)
    if description.contains("keyNotFound(path:") && description.contains("language_model") {
        return "模型格式与当前 App 版本不兼容，请更新 App 后重新加载。"
    }

    return String("加载失败：\(error)".prefix(120))
}

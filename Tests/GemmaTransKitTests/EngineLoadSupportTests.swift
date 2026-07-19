import Foundation
import Testing
@testable import GemmaTransKit

@Suite("Engine load failure messages")
struct EngineLoadSupportTests {
    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    @Test("Gemma weight schema errors do not expose raw tensor paths")
    func modelSchemaErrorGetsActionableMessage() {
        let error = StubError(
            description: #"keyNotFound(path: ["language_model", "model", "layers", "24", "self_attn", "k_norm", "weight"], modules: ["Gemma4Model"])"#
        )

        #expect(
            engineLoadFailureMessage(for: error)
                == "模型格式与当前 App 版本不兼容，请更新 App 后重新加载。"
        )
    }

    @Test("Network errors retain a short retry hint and error code")
    func networkErrorGetsRetryMessage() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: nil
        )

        #expect(
            engineLoadFailureMessage(for: error)
                == "网络中断（已下载部分已保留，可重试继续）[-1005]"
        )
    }

    @Test("Unknown errors remain bounded for UI presentation")
    func genericErrorIsTruncated() {
        let error = StubError(description: String(repeating: "x", count: 200))
        let message = engineLoadFailureMessage(for: error)

        #expect(message.hasPrefix("加载失败："))
        #expect(message.count == 120)
    }
}

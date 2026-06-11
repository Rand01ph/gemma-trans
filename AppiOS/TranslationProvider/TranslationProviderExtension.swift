import SwiftUI
import ExtensionKit
import TranslationUIProvider

@main
final class TranslationProviderExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            SpringboardPanelView(box: ContextBox(value: context))
        }
    }
}

/// 把非 Sendable 的 context 装箱跨进 MainActor 的 View init——
/// 场景 content 闭包来自 @preconcurrency 框架（非 MainActor 声明，实际主线程回调），
/// Swift 6 区域隔离不许直接传，装箱后在 init 里取出。
struct ContextBox: @unchecked Sendable {
    let value: any TranslationUIProviderContext
}

/// 轻量跳板面板：只展示选中文字 + 一键跳主 app 翻译。
/// 不 import GemmaTransKit、不碰 EngineHolder/ModelStore——
/// 本扩展进程额度仅 221MB（spike 真机实测），碰模型即被 jetsam 杀。
struct SpringboardPanelView: View {
    @State var context: any TranslationUIProviderContext
    @Environment(\.openURL) private var openURL
    @State private var jumpFailed = false

    init(box: ContextBox) {
        self.context = box.value
    }

    private var sourceText: String {
        context.inputText.map { String($0.characters) } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sourceText)
                .lineLimit(3).font(.subheadline).foregroundStyle(.secondary)
            Button {
                // URL 长度兜底：超长选区截到 2000 字符（与引擎 maxInputChars 同量级）
                let text = String(sourceText.prefix(2000))
                var comps = URLComponents()
                comps.scheme = "gemmatrans"
                comps.host = "translate"
                comps.queryItems = [URLQueryItem(name: "text", value: text)]
                if let url = comps.url {
                    openURL(url) { accepted in jumpFailed = !accepted }
                }
            } label: {
                Label("在 GemmaTrans 中翻译", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            if jumpFailed {
                // spike 备用出口：openURL 在此扩展点不可用时给用户兜底指引
                Label("无法直接跳转，请复制后打开 GemmaTrans 粘贴翻译", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("拷贝原文") {
                    UIPasteboard.general.string = sourceText
                }
            }
        }
        .padding()
    }
}

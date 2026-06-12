import SwiftUI
import ExtensionKit
import TranslationUIProvider

@main
final class TranslationProviderExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            HandoffPanelView(box: ContextBox(value: context))
        }
    }
}

/// 把非 Sendable 的 context 装箱跨进 MainActor 的 View init——
/// 场景 content 闭包来自 @preconcurrency 框架（非 MainActor 声明，实际主线程回调），
/// Swift 6 区域隔离不许直接传，装箱后在 init 里取出。
struct ContextBox: @unchecked Sendable {
    let value: any TranslationUIProviderContext
}

/// 轻量接力面板（spec 第 4 节）：选中文字预览 + 一键跳主 app 翻译。
/// 本扩展进程额度仅 221MB（spike 真机实测），不加载模型——只读 ModelStore 的文件级完成标记
/// 决定按钮文案（已下载→「在 GemmaTrans 中翻译」/ 未下载→「打开 GemmaTrans 下载模型」）。
/// 接力链路：写 App Group（pendingHandoffText + 时间戳）+ deep link 双通道，主 app 启动即灌入并自动译。
struct HandoffPanelView: View {
    @State var context: any TranslationUIProviderContext
    @Environment(\.openURL) private var openURL
    @State private var jumpFailed = false

    /// 模型是否已下载（文件级标记，不触碰模型权重）
    private let modelReady = ModelStore.modelDownloaded

    init(box: ContextBox) {
        self.context = box.value
    }

    private var sourceText: String {
        context.inputText.map { String($0.characters) } ?? ""
    }

    private var buttonTitle: String {
        modelReady ? "在 GemmaTrans 中翻译" : "打开 GemmaTrans 下载模型"
    }

    private var footnote: String {
        modelReady ? "本地模型翻译 · 文本不上传" : "首次使用需下载 3.6GB 本地模型"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !sourceText.isEmpty {
                // 预览区：首行装饰引号、3 行截断
                Text("\u{201C}\(sourceText)\u{201D}")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Button(action: handoff) {
                Label(buttonTitle, systemImage: "arrow.up.forward")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .modifier(PanelButtonStyle())

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            if jumpFailed {
                // openURL 在此扩展点不可用时的兜底出口（spec 第 4 节末注）
                Label("无法直接跳转，请拷贝后打开 GemmaTrans 粘贴翻译", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("拷贝原文") { UIPasteboard.general.string = sourceText }
            }
        }
        .padding()
    }

    private func handoff() {
        // URL 长度兜底：超长选区截到 2000 字符（与引擎 maxInputChars 同量级）
        let text = String(sourceText.prefix(2000))
        // 双通道：App Group 兜底（deep link 失败时主 app 前台化仍能捡起）
        ModelStore.writeHandoff(text)
        var comps = URLComponents()
        comps.scheme = "gemmatrans"
        comps.host = "translate"
        comps.queryItems = [URLQueryItem(name: "text", value: text)]
        if let url = comps.url {
            openURL(url) { accepted in jumpFailed = !accepted }
        }
    }
}

/// 主按钮样式：iOS 26+ 走 Liquid Glass，18.4 回退 borderedProminent。
/// （扩展不引入主 app 的 Theme.swift，此处独立一份最小回退。）
private struct PanelButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).tint(.accentColor)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

import SwiftUI
import GemmaTransKit

@main
struct GemmaTransiOSApp: App {
    /// 冷启动时从 App Group 消费一次接力文本（扩展可能写了 pendingHandoffText 但 deep link 未达）
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { consumeHandoffIfAny() }
                .onChange(of: scenePhase) { _, phase in
                    // 回到前台再消费一次：扩展在 app 已运行时拉起，靠 deep link；
                    // deep link 失败时 App Group 兜底，前台化即捡起
                    if phase == .active { consumeHandoffIfAny() }
                }
                .onOpenURL { handleIncomingURL($0) }
        }
    }

    /// deep link 入口：gemmatrans://translate?text=...（扩展点按 → 拉起主 app）
    private func handleIncomingURL(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.host == "translate" else { return }
        let text = comps.queryItems?.first(where: { $0.name == "text" })?.value
        // URL 带文本优先；否则回落 App Group 接力（扩展可能只写了 App Group）
        if let text, !text.isEmpty {
            deliver(text)
        } else {
            consumeHandoffIfAny()
        }
    }

    /// 消费 App Group 接力文本（>60s 丢弃由 ModelStore.consumeHandoff 处理）
    private func consumeHandoffIfAny() {
        if let text = ModelStore.consumeHandoff() {
            deliver(text)
        }
    }

    /// 灌入 TranslatorModel 并（引擎就绪时）自动翻译；未就绪由 ContentView 在 .ready 时补触发
    @MainActor
    private func deliver(_ text: String) {
        TranslatorModel.shared.handoff(text)
        EngineHolder.shared.loadIfDownloaded()  // 冷启动时 .task 也会调，幂等
    }
}

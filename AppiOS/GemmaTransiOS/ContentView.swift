import SwiftUI
import GemmaTransKit

/// 纯状态路由（spec 2.1）：模型未就绪→OnboardingView 全屏接管；就绪/加载→TranslatorView。
/// 另负责防锁屏 isIdleTimerDisabled 的 onChange，以及就绪后补触发接力翻译。
struct ContentView: View {
    @State private var holder = EngineHolder.shared
    @State private var model = TranslatorModel.shared
    @State private var showSettings = false

    var body: some View {
        Group {
            switch holder.status {
            case .idle, .downloading, .failed:
                OnboardingView()
            case .loading, .ready:
                TranslatorView(showSettings: $showSettings)
            }
        }
        .animation(.default, value: holder.status)
        .task { holder.loadIfDownloaded() }
        .onChange(of: holder.status) { _, newStatus in
            // 锁屏/挂起会掐断 3.6GB 长连接（真机 NSURLError -1005 的来源之一）：
            // 下载期间禁用自动锁屏，结束（就绪/失败/回到 idle）即恢复
            switch newStatus {
            case .downloading:
                UIApplication.shared.isIdleTimerDisabled = true
            case .ready, .failed, .idle:
                UIApplication.shared.isIdleTimerDisabled = false
            case .loading:
                break  // 下载→加载的中间态，维持现状即可
            }
            // 接力文本：引擎就绪时若已灌入但因引擎未就绪未译，此刻补触发
            if newStatus == .ready, !model.input.isEmpty, model.output.isEmpty, !model.isTranslating {
                model.translate()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
    }
}

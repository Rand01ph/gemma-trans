import SwiftUI
import GemmaTransKit

struct ContentView: View {
    @State private var holder = EngineHolder.shared
    @State private var input = ""
    @State private var output = ""
    @State private var translating = false
    /// 国内源开关：写入共享 defaults，EngineHolder 加载时经 ModelStore.modelSource 读取
    @AppStorage(ModelStore.sourceKey, store: UserDefaults(suiteName: ModelStore.settingsSuite))
    private var useCNSource = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader
                TextField("输入或粘贴要翻译的文本", text: $input, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("粘贴") {
                        if let s = UIPasteboard.general.string { input = s }
                    }
                    .buttonStyle(.bordered)
                    Button("翻译") { translate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(holder.status != .ready || translating || input.isEmpty)
                }
                ScrollView {
                    Text(output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("GemmaTrans")
        }
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
        }
    }

    @ViewBuilder private var statusHeader: some View {
        switch holder.status {
        case .idle:
            // 模型未下载：显式确认后才下 3.6GB（真机反馈：启动即自动下载太粗暴）
            VStack(alignment: .leading, spacing: 8) {
                Label("模型未下载（约 3.6GB，建议 Wi-Fi）", systemImage: "arrow.down.circle")
                Toggle("使用国内源（ModelScope）", isOn: $useCNSource)
                Text("国内网络建议开启")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("下载模型") { holder.download() }
                    .buttonStyle(.borderedProminent)
            }
        case .loading:
            Label("正在加载模型…", systemImage: "hourglass")
        case .downloading(let pct):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(pct), total: 100) { Text("下载模型 \(pct)%") }
                Text("下载期间请保持 App 在前台")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .ready:
            Label("引擎就绪（本地 Gemma）", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 8) {
                Label(msg, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .lineLimit(2)
                // 模型已下载完成时 download() 自然走纯加载路径，失败重试统一调它
                Button("重试") { holder.download() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func translate() {
        guard let engine = holder.engine else { return }
        translating = true
        output = ""
        let text = input
        Task {
            do {
                let result = try await engine.translate(text, target: nil)
                for try await chunk in result.chunks { output += chunk }
            } catch {
                output = "翻译失败：\(error)"
            }
            translating = false
        }
    }
}

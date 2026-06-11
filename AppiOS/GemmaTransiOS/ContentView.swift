import SwiftUI
import GemmaTransKit

struct ContentView: View {
    @State private var holder = EngineHolder.shared
    @State private var input = ""
    @State private var output = ""
    @State private var translating = false
    /// 国内镜像开关：写入共享 defaults，EngineHolder 加载时经 ModelStore.hubHost 读取
    @AppStorage(ModelStore.mirrorKey, store: UserDefaults(suiteName: ModelStore.settingsSuite))
    private var useMirror = false

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
    }

    @ViewBuilder private var statusHeader: some View {
        switch holder.status {
        case .idle:
            // 模型未下载：显式确认后才下 1.4GB（真机反馈：启动即自动下载太粗暴）
            VStack(alignment: .leading, spacing: 8) {
                Label("模型未下载（约 1.4GB，建议 Wi-Fi）", systemImage: "arrow.down.circle")
                Toggle("使用国内镜像（hf-mirror.com）", isOn: $useMirror)
                Text("国内网络建议开启")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("下载模型") { holder.download() }
                    .buttonStyle(.borderedProminent)
            }
        case .loading:
            Label("正在加载模型…", systemImage: "hourglass")
        case .downloading(let pct):
            ProgressView(value: Double(pct), total: 100) { Text("下载模型 \(pct)%") }
        case .ready:
            Label("引擎就绪（本地 Gemma）", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.octagon").foregroundStyle(.red)
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

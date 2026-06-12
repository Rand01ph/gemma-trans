import SwiftUI
import GemmaTransKit

/// 首启仪式：模型未就绪（idle / downloading / failed）时全屏接管。
/// 三态线框见 spec 第 3.1–3.3 节。下载是仪式不是报错——失败用 systemOrange 不用红色。
struct OnboardingView: View {
    @State private var holder = EngineHolder.shared
    /// 国内源开关：从原 ContentView 迁来，写入共享 defaults，引擎加载经 ModelStore.modelSource 读取
    @AppStorage(ModelStore.sourceKey, store: UserDefaults(suiteName: ModelStore.settingsSuite))
    private var useCNSource = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            content
                .padding(.horizontal, Theme.Spacing.screenH)
                .frame(maxWidth: 480)
        }
        .transition(.opacity)
    }

    @ViewBuilder private var content: some View {
        switch holder.status {
        case .downloading(let progress):
            DownloadingView(progress: progress)
        case .failed(let message):
            FailedView(message: message, useCNSource: $useCNSource) { holder.download() }
        default:
            // .idle（也兜底 .loading/.ready，这些状态由上层路由到 TranslatorView，不会到这）
            IdleView(useCNSource: $useCNSource) { holder.download() }
        }
    }
}

// MARK: - idle（3.1 首启未下载）

private struct IdleView: View {
    @Binding var useCNSource: Bool
    let onDownload: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.section) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 64, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("完全离线的本地翻译")
                    .font(.title2.weight(.semibold))
                Text("Gemma 模型在你的 iPhone 上运行，文本永远不离开设备。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                LabeledContent("模型大小") { Text("3.6 GB") }
                    .padding(Theme.Spacing.cardPadding)
                Divider().padding(.leading, Theme.Spacing.cardPadding)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("使用国内源", isOn: $useCNSource)
                    Text("国内网络建议开启（ModelScope 魔搭）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(Theme.Spacing.cardPadding)
            }
            .cardBackground()

            Spacer()

            VStack(spacing: 8) {
                Button(action: onDownload) {
                    Label("下载模型", systemImage: "arrow.down")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .adaptiveGlassButton()
                .controlSize(.large)

                Text("建议在 Wi-Fi 环境下载")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.section)
    }
}

// MARK: - downloading（3.2 下载中）

private struct DownloadingView: View {
    let progress: DownloadProgress

    var body: some View {
        VStack(spacing: Theme.Spacing.section) {
            Spacer()
            ProgressRing(progress: progress)
            VStack(spacing: 6) {
                Text("正在下载翻译模型")
                    .font(.headline)
                Text("请保持 GemmaTrans 在前台\n（已为你暂停自动锁屏）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("支持断点续传，中断后可继续")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            Spacer()
        }
    }
}

/// 120pt 环形进度（accent，圆头线帽）。中心百分比 + 字节行（HF 宏路径字节为 nil 时隐藏字节行）。
private struct ProgressRing: View {
    let progress: DownloadProgress

    private var byteLine: String? {
        guard let done = progress.completedBytes, let total = progress.totalBytes else { return nil }
        return String(format: "%.1f GB / %.1f GB", Double(done) / 1e9, Double(total) / 1e9)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.001, progress.fraction))
                .stroke(.tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring, value: progress.fraction)
            VStack(spacing: 2) {
                Text("\(Int(progress.fraction * 100))%")
                    .font(.title2.monospacedDigit())
                if let byteLine {
                    Text(byteLine)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 120, height: 120)
    }
}

// MARK: - failed（3.3 下载失败 + 重试）

private struct FailedView: View {
    let message: String
    @Binding var useCNSource: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.section) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(.systemOrange))

            VStack(spacing: 8) {
                Text("下载中断了")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("已下载的部分已保留，可继续下载。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onRetry) {
                Text("继续下载")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .adaptiveGlassButton()
            .controlSize(.large)

            // 失败态把源开关再次亮出——最常见自救路径就是切源
            VStack(alignment: .leading, spacing: 4) {
                Toggle("使用国内源（ModelScope）", isOn: $useCNSource)
                Text("切换下载源后再次「继续下载」")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.cardPadding)
            .cardBackground()

            Spacer()
        }
    }
}

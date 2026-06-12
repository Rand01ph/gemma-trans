import SwiftUI
import BackgroundTasks
import GemmaTransKit
import os

@main
struct GemmaTransiOSApp: App {
    init() {
        Self.logCapabilityProbe()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }

    /// spike 探针：记录本机后台 GPU 能力与前台内存额度。
    /// 后台 GPU（BGContinuedProcessingTask 的 .gpu 资源，iOS 26+）是 iPhone 上能否
    /// 「不切走当前 app 还跑 MLX 推理」的硬门槛；旧资料称 15/16 Pro 不支持，本探针实测本机。
    private static func logCapabilityProbe() {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let foregroundMB = os_proc_available_memory() / 1_048_576
        var bgGPU = "n/a(<iOS26)"
        if #available(iOS 26.0, *) {
            bgGPU = BGTaskScheduler.supportedResources.contains(.gpu) ? "YES" : "no"
        }
        GTLog.info("[diag] \(os) | foreground avail: \(foregroundMB)MB | bgGPU(BGContinuedProcessing): \(bgGPU)")
    }
}

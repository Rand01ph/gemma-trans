import Foundation
import os

/// 极简文件日志：GUI app 的 stderr 会被丢弃，引擎错误必须落盘才能事后定位。
/// 同时写 os_log（Console.app 可见）。
public enum GTLog {
    public static let logFileURL = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/GemmaTrans/gemmatrans.log")

    private static let osLog = Logger(subsystem: "com.gemmatrans.app", category: "engine")
    private static let queue = DispatchQueue(label: "com.gemmatrans.log")

    public static func error(_ message: String) { write("ERROR", message) }
    public static func info(_ message: String) { write("INFO", message) }

    private static func write(_ level: String, _ message: String) {
        osLog.log(level: level == "ERROR" ? .error : .info, "\(message, privacy: .public)")
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            let dir = logFileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: logFileURL)
            }
        }
    }
}

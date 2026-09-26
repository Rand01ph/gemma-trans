#if DEBUG
import AppKit
import Foundation
import GemmaTransKit

/// Deterministic, Debug-only fixtures used to capture App Store screenshots
/// without enabling accessibility automation or changing production behavior.
@MainActor
enum GTDebugScreenshotFixture {
    static let scene: String? = {
        if let environmentValue = ProcessInfo.processInfo.environment["GEMMATRANS_SCREENSHOT_SCENE"] {
            return environmentValue
        }
        if let defaultsValue = UserDefaults(suiteName: GemmaTransKit.AppSettings.suiteName)?
            .string(forKey: "debugScreenshotScene"),
           !defaultsValue.isEmpty {
            return defaultsValue
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--screenshot-scene"),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        return arguments[flagIndex + 1]
    }()

    static let mainInput = "真正好的工具不会打断工作，而是在需要时安静地出现。"
    static let mainOutput = "Great tools don’t interrupt your work; they simply appear quietly when needed."
    static let panelOutput = "Great tools don’t interrupt your flow. They simply appear, quietly, when you need them."

    static var isMain: Bool { scene?.hasPrefix("main") == true }
    static var isPanel: Bool { scene?.hasPrefix("panel") == true }
    static var state: String { scene?.split(separator: "-").dropFirst().first.map(String.init) ?? "completed" }

    static var settingsSection: SettingsSection? {
        guard let scene, scene.hasPrefix("settings-") else { return nil }
        return SettingsSection(rawValue: String(scene.dropFirst("settings-".count)))
    }

    private static var didScheduleCapture = false
    private static var backdrop: NSWindow?

    static func prepareMenuBackdrop() {
        guard let screen = NSScreen.main else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        window.isOpaque = true
        window.level = .floating
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        backdrop = window
    }

    static func captureIfRequested(window: NSWindow, matching requestedScene: String) {
        guard (scene == requestedScene || (isMain && requestedScene == "main")),
              !didScheduleCapture,
              let outputPath = ProcessInfo.processInfo.environment["GEMMATRANS_SCREENSHOT_PATH"]
        else { return }
        didScheduleCapture = true

        Task { @MainActor in
            if let appearanceName = ProcessInfo.processInfo.environment["GEMMATRANS_SCREENSHOT_APPEARANCE"],
               let appearance = NSAppearance(
                named: appearanceName == "light" ? .aqua : .darkAqua
               ) {
                NSApp.appearance = appearance
                window.appearance = appearance
                window.contentView?.appearance = appearance
                window.contentView?.needsDisplay = true
            }
            let background = NSWindow(contentRect: window.frame, styleMask: .borderless,
                backing: .buffered, defer: false)
            background.backgroundColor = NSColor(calibratedWhite: 0.5, alpha: 1)
            background.isOpaque = true
            background.level = window.level
            background.ignoresMouseEvents = true
            background.order(.below, relativeTo: window.windowNumber)
            backdrop = background
            try? await Task.sleep(for: .seconds(1))
            window.displayIfNeeded()
            guard let contentView = window.contentView else { return }
            var captureView = contentView
            while let superview = captureView.superview {
                captureView = superview
            }
            captureView.layoutSubtreeIfNeeded()
            captureView.wantsLayer = true
            let scale = window.backingScaleFactor
            let width = Int(captureView.bounds.width * scale)
            let height = Int(captureView.bounds.height * scale)
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
            bitmap.size = captureView.bounds.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.setFillColor(NSColor(calibratedWhite: 0.5, alpha: 1).cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.cgContext.scaleBy(x: scale, y: scale)
            captureView.layer?.render(in: context.cgContext)
            NSGraphicsContext.restoreGraphicsState()
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            let metadata: [String: Any] = [
                "windowNumber": window.windowNumber,
                "scene": scene ?? requestedScene,
                "appearance": ProcessInfo.processInfo.environment["GEMMATRANS_SCREENSHOT_APPEARANCE"] ?? "light",
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "scale": scale, "width": width, "height": height,
                "font": NSFont.systemFont(ofSize: 13).fontName,
                "elements": UIContractRegistry.elements.values.filter { $0.id.hasPrefix((scene?.split(separator: "-").first.map(String.init) ?? "main") + ".") }.sorted { $0.id < $1.id }.map {
                    ["id": $0.id, "text": $0.text, "enabled": $0.enabled, "frame": $0.frame] as [String: Any]
                }
            ]
            if let json = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
                try? json.write(to: URL(fileURLWithPath: outputPath).deletingPathExtension().appendingPathExtension("json"))
            }
            if ProcessInfo.processInfo.environment["GEMMATRANS_NATIVE_CAPTURE"] == "1" {
                let done = outputPath + ".captured"
                for _ in 0..<200 {
                    if FileManager.default.fileExists(atPath: done) { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            NSApp.terminate(nil)
        }
    }
}
#endif

#if DEBUG
import AppKit
import Foundation

/// Deterministic, Debug-only fixtures used to capture App Store screenshots
/// without enabling accessibility automation or changing production behavior.
@MainActor
enum GTDebugScreenshotFixture {
    static let scene: String? = {
        if let environmentValue = ProcessInfo.processInfo.environment["GEMMATRANS_SCREENSHOT_SCENE"] {
            return environmentValue
        }
        if let defaultsValue = UserDefaults(suiteName: "com.gemmatrans.app")?
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

    static var isMain: Bool { scene == "main" }
    static var isPanel: Bool { scene == "panel" }

    static var settingsSection: SettingsSection? {
        guard let scene, scene.hasPrefix("settings-") else { return nil }
        return SettingsSection(rawValue: String(scene.dropFirst("settings-".count)))
    }

    private static var didScheduleCapture = false

    static func captureIfRequested(window: NSWindow, matching requestedScene: String) {
        guard scene == requestedScene,
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
            context.cgContext.scaleBy(x: scale, y: scale)
            captureView.layer?.render(in: context.cgContext)
            NSGraphicsContext.restoreGraphicsState()
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            NSApp.terminate(nil)
        }
    }
}
#endif

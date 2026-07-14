import Foundation

/// 翻译浮窗几何计算。纯函数（Double，无 AppKit 依赖），便于单测。
public enum PanelGeometry {
    public static let panelWidth: Double = 500
    /// Result-only layout: 100pt of header/actions/chrome plus a measured result surface.
    public static let chromeHeight: Double = 100
    public static let minHeight: Double = 176
    /// Streaming starts at a stable, comfortable size and settles once after completion.
    public static let initialHeight: Double = 220
    public static let maxHeight: Double = 340
    public static let maxScreenFraction: Double = 0.50
    public static let minimumResultSurfaceHeight: Double = 76
    public static let streamingResultSurfaceHeight: Double = 120
    public static let maximumResultSurfaceHeight: Double = 240
    /// Transparent AppKit window space reserved for the rounded SwiftUI shadow.
    /// This must exceed the blur sampling radius so it never clips to NSPanel's rectangle.
    public static let shadowGutter: Double = 30
    /// 流式期间小于该差值不调整，防抖
    public static let resizeThreshold: Double = 24

    public static func targetHeight(contentHeight: Double, screenVisibleHeight: Double) -> Double {
        let screenCap = min(maxHeight, screenVisibleHeight * maxScreenFraction)
        return min(max(contentHeight, minHeight), screenCap)
    }

    public static func windowWidth(forVisualWidth visualWidth: Double = panelWidth) -> Double {
        visualWidth + shadowGutter * 2
    }

    public static func windowHeight(forVisualHeight visualHeight: Double) -> Double {
        visualHeight + shadowGutter * 2
    }

    public static func resultSurfaceHeight(measuredContentHeight: Double) -> Double {
        min(max(measuredContentHeight, minimumResultSurfaceHeight), maximumResultSurfaceHeight)
    }

    /// The translation surface is bounded and scrolls internally. The caller supplies a measured
    /// surface height only after generation finishes, avoiding token-by-token window resizing.
    public static func preferredHeight(resultSurfaceHeight: Double) -> Double {
        let clampedSurfaceHeight = self.resultSurfaceHeight(
            measuredContentHeight: resultSurfaceHeight
        )
        return min(maxHeight, max(minHeight, chromeHeight + clampedSurfaceHeight))
    }
}

import Foundation

/// 翻译浮窗几何计算。纯函数（Double，无 AppKit 依赖），便于单测。
public enum PanelGeometry {
    public static let panelWidth: Double = 480
    /// Result-only layout: compact header/actions/chrome plus a measured result surface.
    public static let chromeHeight: Double = 82
    public static let minHeight: Double = 132
    /// Streaming starts at a stable, comfortable size and settles once after completion.
    public static let initialHeight: Double = 174
    public static let maxHeight: Double = 340
    public static let maxScreenFraction: Double = 0.50
    public static let minimumResultSurfaceHeight: Double = 50
    public static let streamingResultSurfaceHeight: Double = 92
    public static let maximumResultSurfaceHeight: Double = 258
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

    /// Keeps a locked panel's top-left anchor stable while its height changes, clamping only
    /// when the window would leave the display's visible frame.
    public static func lockedWindowOrigin(anchorX: Double,
                                          anchorTopY: Double,
                                          windowWidth: Double,
                                          windowHeight: Double,
                                          visibleMinX: Double,
                                          visibleMinY: Double,
                                          visibleMaxX: Double,
                                          visibleMaxY: Double,
                                          margin: Double = 10) -> (x: Double, y: Double) {
        let minimumX = visibleMinX + margin
        let maximumX = max(minimumX, visibleMaxX - windowWidth - margin)
        let minimumTopY = visibleMinY + windowHeight + margin
        let maximumTopY = max(minimumTopY, visibleMaxY - margin)
        let clampedX = min(max(anchorX, minimumX), maximumX)
        let clampedTopY = min(max(anchorTopY, minimumTopY), maximumTopY)
        return (clampedX, clampedTopY - windowHeight)
    }

    public static func resultSurfaceHeight(measuredContentHeight: Double) -> Double {
        min(max(measuredContentHeight, minimumResultSurfaceHeight), maximumResultSurfaceHeight)
    }

    /// Returns whether the viewport still has meaningful content below it. A small tolerance
    /// avoids flashing the overflow fade for subpixel layout differences at the bottom edge.
    public static func hasContentBelow(contentHeight: Double,
                                       visibleMaxY: Double,
                                       tolerance: Double = 1) -> Bool {
        contentHeight > visibleMaxY + tolerance
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

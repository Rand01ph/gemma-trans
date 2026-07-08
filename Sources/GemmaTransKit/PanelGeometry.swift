import Foundation

/// 翻译浮窗几何计算。纯函数（Double，无 AppKit 依赖），便于单测。
public enum PanelGeometry {
    public static let panelWidth: Double = 620
    public static let minHeight: Double = 330
    public static let maxHeight: Double = 520
    public static let maxScreenFraction: Double = 0.56
    public static let shadowGutter: Double = 18
    /// 流式期间小于该差值不调整，防抖
    public static let resizeThreshold: Double = 10

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
}

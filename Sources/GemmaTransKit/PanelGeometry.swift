import Foundation

/// 翻译浮窗几何计算。纯函数（Double，无 AppKit 依赖），便于单测。
public enum PanelGeometry {
    public static let panelWidth: Double = 420
    public static let minHeight: Double = 140
    public static let maxScreenFraction: Double = 0.7
    /// 内边距 + 状态/按钮行 + 隐藏标题区
    public static let chromeHeight: Double = 96
    /// 流式期间小于该差值不调整，防抖
    public static let resizeThreshold: Double = 8

    public static func targetHeight(contentHeight: Double, screenVisibleHeight: Double) -> Double {
        min(max(contentHeight + chromeHeight, minHeight), screenVisibleHeight * maxScreenFraction)
    }
}

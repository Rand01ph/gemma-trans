import Foundation

/// 翻译浮窗几何计算。纯函数（Double，无 AppKit 依赖），便于单测。
public enum PanelGeometry {
    public struct Frame: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var minX: Double { x }
        public var minY: Double { y }
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
    }

    public static let panelWidth: Double = 420
    public static let minHeight: Double = 140
    public static let maxScreenFraction: Double = 0.7
    /// 内边距 + 状态/按钮行
    public static let chromeHeight: Double = 76
    /// 流式期间小于该差值不调整，防抖
    public static let resizeThreshold: Double = 8

    public static func targetHeight(contentHeight: Double, screenVisibleHeight: Double) -> Double {
        min(max(contentHeight + chromeHeight, minHeight), screenVisibleHeight * maxScreenFraction)
    }

    public static func clampedFrame(_ frame: Frame, visibleFrame: Frame) -> Frame {
        var clamped = frame

        if clamped.width >= visibleFrame.width {
            clamped.x = visibleFrame.minX
        } else if clamped.minX < visibleFrame.minX {
            clamped.x = visibleFrame.minX
        } else if clamped.maxX > visibleFrame.maxX {
            clamped.x = visibleFrame.maxX - clamped.width
        }

        if clamped.height >= visibleFrame.height {
            clamped.y = visibleFrame.minY
        } else if clamped.minY < visibleFrame.minY {
            clamped.y = visibleFrame.minY
        } else if clamped.maxY > visibleFrame.maxY {
            clamped.y = visibleFrame.maxY - clamped.height
        }

        return clamped
    }

    public static func resizedFrameKeepingTop(
        _ frame: Frame, targetHeight: Double, visibleFrame: Frame
    ) -> Frame {
        clampedFrame(
            Frame(x: frame.x, y: frame.maxY - targetHeight, width: frame.width, height: targetHeight),
            visibleFrame: visibleFrame
        )
    }
}

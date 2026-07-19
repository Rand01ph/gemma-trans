import SwiftUI
import GemmaTransKit

enum GTGlassTokens {
    enum Radius {
        static let control: CGFloat = 12
        static let card: CGFloat = 18
        static let panel: CGFloat = 26
        static let window: CGFloat = 28

        static func inset(from outer: CGFloat, by inset: CGFloat) -> CGFloat {
            max(0, outer - inset)
        }
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Toolbar {
        static let controlHeight: CGFloat = 38
        static var radius: CGFloat { controlHeight / 2 }
    }

    enum Window {
        static let defaultSize = CGSize(width: 980, height: 570)
        static let minSize = CGSize(width: 760, height: 520)
        static let contentInset: CGFloat = 18
    }

    enum Panel {
        static let translationVisualWidth = CGFloat(PanelGeometry.panelWidth)
        static let translationMinVisualHeight = CGFloat(PanelGeometry.minHeight)
        static let translationInitialVisualHeight = CGFloat(PanelGeometry.initialHeight)
        static let translationMaxVisualHeight = CGFloat(PanelGeometry.maxHeight)
        static let translationShadowGutter = CGFloat(PanelGeometry.shadowGutter)
        static let translationWindowWidth = translationVisualWidth + translationShadowGutter * 2
        static let translationWindowMinHeight = translationMinVisualHeight + translationShadowGutter * 2
        static let messageVisualSize = CGSize(width: 420, height: 144)
        static let messageWindowSize = CGSize(width: messageVisualSize.width + translationShadowGutter * 2,
                                              height: messageVisualSize.height + translationShadowGutter * 2)
        static let settingsWidth: CGFloat = 640
        static let settingsHeight: CGFloat = 500
    }

    enum Icon {
        static let chip: CGFloat = 34
        static let toolbar: CGFloat = 28
        static let row: CGFloat = 24
    }
}

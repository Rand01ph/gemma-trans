import AppKit
import SwiftUI

struct GTVisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}

struct GTContentBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            GTVisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow)
            GTGlassPalette.windowBackground(for: colorScheme)
                .opacity(backgroundOpacity)
        }
        .ignoresSafeArea()
    }

    private var backgroundOpacity: Double {
        if reduceTransparency || contrast == .increased { return 1 }
        return colorScheme == .dark ? 0.92 : 0.86
    }
}

struct GTExteriorShadow: View {
    var cornerRadius: CGFloat
    var color: Color
    var radius: CGFloat
    var y: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape
                .fill(color)
                .blur(radius: radius)
                .offset(y: y)
            shape
                .fill(.black)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}

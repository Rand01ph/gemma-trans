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

    var body: some View {
        ZStack {
            GTVisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow)
            GTGlassPalette.backgroundOverlay(for: colorScheme)
            LinearGradient(
                colors: backgroundStops,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)
        }
        .ignoresSafeArea()
    }

    private var backgroundStops: [Color] {
        if colorScheme == .dark {
            return [
                Color.black.opacity(0.16),
                GTGlassPalette.semanticBlue.opacity(0.035),
                Color.black.opacity(0.08)
            ]
        }
        return [
            Color.clear,
            GTGlassPalette.semanticBlue.opacity(0.018),
            Color.black.opacity(0.018)
        ]
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

import SwiftUI

struct GTGlassSurface: ViewModifier {
    enum Level {
        case window
        case panel
        case card
        case flat
    }

    var level: Level = .card
    var cornerRadius: CGFloat = GTGlassTokens.Radius.card
    var fill: Color? = nil
    var fillOpacity: Double = 0.18
    var gradient = true
    var interactive = false
    var stroke = true

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .clipShape(shape)
            .background {
                if level != .flat {
                    GTExteriorShadow(cornerRadius: cornerRadius,
                                     color: shadowColor,
                                     radius: shadowRadius,
                                     y: shadowY)
                }
            }
            .glassEffect(glass, in: shape)
            .background {
                shape.fill(fillStyle)
            }
            .overlay {
                if stroke {
                    shape.strokeBorder(strokeColor, lineWidth: level == .window ? 1.1 : 1)
                }
            }
    }

    private var glass: Glass {
        let base = Glass.regular
        return interactive ? base.interactive() : base
    }

    private var fillStyle: AnyShapeStyle {
        let base = fill ?? GTGlassPalette.defaultSurfaceBase(for: colorScheme)
        let opacity = fillOpacity * (colorScheme == .dark ? 0.92 : 0.68)
        if gradient {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    base.opacity(opacity * 1.08),
                    GTGlassPalette.lavender.opacity(opacity * (colorScheme == .dark ? 0.26 : 0.42)),
                    GTGlassPalette.peach.opacity(opacity * (colorScheme == .dark ? 0.20 : 0.36)),
                    GTGlassPalette.innerNeutral.opacity(opacity * 0.54)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        return AnyShapeStyle(base.opacity(opacity))
    }

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.18) : .white.opacity(0.34)
    }

    private var shadowColor: Color {
        switch level {
        case .window:
            return .black.opacity(colorScheme == .dark ? 0.58 : 0.22)
        case .panel:
            return .black.opacity(colorScheme == .dark ? 0.52 : 0.20)
        case .card:
            return .black.opacity(colorScheme == .dark ? 0.38 : 0.14)
        case .flat:
            return .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch level {
        case .window: return 30
        case .panel: return 24
        case .card: return 14
        case .flat: return 0
        }
    }

    private var shadowY: CGFloat {
        switch level {
        case .window: return 16
        case .panel: return 10
        case .card: return 5
        case .flat: return 0
        }
    }
}

extension View {
    func gtGlassSurface(_ level: GTGlassSurface.Level = .card,
                        cornerRadius: CGFloat = GTGlassTokens.Radius.card,
                        fill: Color? = nil,
                        fillOpacity: Double = 0.18,
                        gradient: Bool = true,
                        interactive: Bool = false,
                        stroke: Bool = true) -> some View {
        modifier(GTGlassSurface(level: level,
                                cornerRadius: cornerRadius,
                                fill: fill,
                                fillOpacity: fillOpacity,
                                gradient: gradient,
                                interactive: interactive,
                                stroke: stroke))
    }
}

struct GTGlassCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var systemImage: String? = nil
    var fill: Color? = nil
    var elevated = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: GTGlassTokens.Space.m) {
            if title != nil || subtitle != nil || systemImage != nil {
                HStack(alignment: .top, spacing: GTGlassTokens.Space.m) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.headline)
                            .frame(width: GTGlassTokens.Icon.chip, height: GTGlassTokens.Icon.chip)
                            .gtGlassSurface(.flat,
                                            cornerRadius: GTGlassTokens.Radius.control,
                                            fill: fill ?? GTGlassPalette.innerNeutral,
                                            fillOpacity: 0.22,
                                            gradient: true,
                                            stroke: false)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            Text(title)
                                .font(.headline.weight(.semibold))
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            content()
        }
        .padding(GTGlassTokens.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gtGlassSurface(elevated ? .card : .flat,
                        cornerRadius: GTGlassTokens.Radius.card,
                        fill: fill,
                        fillOpacity: elevated ? 0.20 : 0.12)
    }
}

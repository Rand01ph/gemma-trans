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
        let opacity = fillOpacity * (colorScheme == .dark ? 1.0 : 0.78)
        if gradient {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    base.opacity(opacity),
                    base.opacity(opacity * 0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        return AnyShapeStyle(base.opacity(opacity))
    }

    private var strokeColor: Color {
        let separator = GTGlassPalette.separator(for: colorScheme)
        switch level {
        case .window: return separator.opacity(1.0)
        case .panel: return separator.opacity(0.92)
        case .card: return separator.opacity(0.78)
        case .flat: return separator.opacity(0.58)
        }
    }

    private var shadowColor: Color {
        switch level {
        case .window:
            return .black.opacity(colorScheme == .dark ? 0.58 : 0.22)
        case .panel:
            return .black.opacity(colorScheme == .dark ? 0.52 : 0.20)
        case .card:
            return .black.opacity(colorScheme == .dark ? 0.32 : 0.06)
        case .flat:
            return .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch level {
        case .window: return 30
        case .panel: return 24
        case .card: return colorScheme == .dark ? 12 : 8
        case .flat: return 0
        }
    }

    private var shadowY: CGFloat {
        switch level {
        case .window: return 16
        case .panel: return 10
        case .card: return colorScheme == .dark ? 5 : 3
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

enum GTContentSurfaceRole {
    case reading
    case form
    case subtle
}

struct GTContentSurface: ViewModifier {
    var role: GTContentSurfaceRole = .reading
    var cornerRadius: CGFloat = GTGlassTokens.Radius.control
    var fill: Color? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let base = fill ?? surfaceBase

        content
            .clipShape(shape)
            .background {
                shape.fill(base.opacity(surfaceOpacity))
            }
            .overlay {
                shape.strokeBorder(
                    surfaceStroke,
                    lineWidth: contrast == .increased ? 1.25 : 1
                )
            }
    }

    private var surfaceBase: Color {
        switch role {
        case .reading: return GTGlassPalette.contentSurfaceBase(for: colorScheme)
        case .form: return GTGlassPalette.formSurfaceBase(for: colorScheme)
        case .subtle: return GTGlassPalette.subtleSurfaceBase(for: colorScheme)
        }
    }

    private var surfaceOpacity: Double {
        if reduceTransparency {
            switch role {
            case .reading: return colorScheme == .dark ? 0.98 : 1.0
            case .form: return colorScheme == .dark ? 0.96 : 1.0
            case .subtle: return colorScheme == .dark ? 0.92 : 1.0
            }
        }
        if contrast == .increased {
            switch role {
            case .reading: return colorScheme == .dark ? 0.98 : 1.0
            case .form: return colorScheme == .dark ? 0.94 : 1.0
            case .subtle: return colorScheme == .dark ? 0.88 : 1.0
            }
        }
        switch role {
        case .reading: return colorScheme == .dark ? 0.96 : 0.94
        case .form: return colorScheme == .dark ? 0.90 : 0.88
        case .subtle: return colorScheme == .dark ? 0.78 : 0.80
        }
    }

    private var strokeOpacity: Double {
        if contrast == .increased {
            return 1.0
        }
        switch role {
        case .reading: return 0.92
        case .form: return 0.82
        case .subtle: return 1.0
        }
    }

    private var surfaceStroke: Color {
        if role == .subtle {
            return GTGlassPalette.controlBoundary(
                for: colorScheme,
                increased: contrast == .increased
            )
        }
        return GTGlassPalette.separator(for: colorScheme).opacity(strokeOpacity)
    }
}

extension View {
    func gtContentSurface(_ role: GTContentSurfaceRole = .reading,
                          cornerRadius: CGFloat = GTGlassTokens.Radius.control,
                          fill: Color? = nil) -> some View {
        modifier(GTContentSurface(role: role, cornerRadius: cornerRadius, fill: fill))
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
                            .foregroundStyle(GTGlassPalette.secondaryText)
                            .frame(width: GTGlassTokens.Icon.chip, height: GTGlassTokens.Icon.chip)
                            .background {
                                RoundedRectangle(cornerRadius: GTGlassTokens.Radius.control,
                                                 style: .continuous)
                                    .fill(Color.primary.opacity(0.07))
                            }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            Text(title)
                                .font(.headline.weight(.semibold))
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(GTGlassPalette.secondaryText)
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

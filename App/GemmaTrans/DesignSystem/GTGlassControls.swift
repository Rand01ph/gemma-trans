import SwiftUI

enum GTGlassEmphasis: Equatable {
    case secondary
    case primary
    case selected
    case warning
    case destructive
    case successFeedback

    fileprivate var usesProminentStyle: Bool {
        self == .primary
    }

    fileprivate var tint: Color? {
        switch self {
        case .secondary:
            return nil
        case .primary, .selected:
            return GTGlassPalette.controlAccent
        case .warning:
            return GTGlassPalette.semanticOrange
        case .destructive:
            return GTGlassPalette.semanticRed
        case .successFeedback:
            return GTGlassPalette.semanticGreen
        }
    }
}

struct GTGlassButton<Label: View>: View {
    var role: ButtonRole? = nil
    var emphasis: GTGlassEmphasis = .secondary
    var minWidth: CGFloat? = nil
    var compact = false
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @ViewBuilder
    var body: some View {
        if emphasis.usesProminentStyle, let tint = emphasis.tint {
            baseButton
                .buttonStyle(.glassProminent)
                .tint(tint)
        } else if let tint = emphasis.tint {
            baseButton
                .buttonStyle(.glass)
                .tint(tint)
        } else {
            baseButton
                .buttonStyle(.glass)
        }
    }

    private var baseButton: some View {
        Button(role: role, action: action) {
            label()
                .font((compact ? Font.callout : Font.body).weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, compact ? 2 : GTGlassTokens.Space.xs)
                .frame(minWidth: minWidth, minHeight: compact ? 16 : 20)
        }
        .buttonBorderShape(.roundedRectangle(radius: 9))
        .controlSize(compact ? .small : .regular)
    }
}

extension GTGlassButton where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String,
         systemImage: String,
         role: ButtonRole? = nil,
         emphasis: GTGlassEmphasis = .secondary,
         minWidth: CGFloat? = nil,
         compact: Bool = false,
         action: @escaping () -> Void) {
        self.role = role
        self.emphasis = emphasis
        self.minWidth = minWidth
        self.compact = compact
        self.action = action
        self.label = { Label(title, systemImage: systemImage) }
    }
}

struct GTGlassButtonGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, GTGlassTokens.Space.xs)
        .frame(height: GTGlassTokens.Toolbar.controlHeight)
        .gtGlassSurface(.flat,
                        cornerRadius: GTGlassTokens.Toolbar.radius,
                        fillOpacity: 0.16,
                        gradient: false,
                        interactive: true)
    }
}

struct GTSearchField: View {
    @Binding var text: String
    var placeholder = "Search settings, models, or actions"
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: GTGlassTokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GTGlassPalette.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .focused($focused)
            if text.isEmpty {
                Text("⌘K")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(GTGlassPalette.tertiaryText)
            } else {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(GTGlassPalette.secondaryText)
                .help("Clear search")
            }
        }
        .padding(.horizontal, GTGlassTokens.Space.m)
        .frame(height: GTGlassTokens.Toolbar.controlHeight)
        .contentShape(Capsule(style: .continuous))
        .gtGlassSurface(.flat,
                        cornerRadius: GTGlassTokens.Toolbar.radius,
                        fillOpacity: focused ? 0.20 : 0.12,
                        gradient: false,
                        interactive: true)
        .onTapGesture { focused = true }
    }
}

struct GTStatusBadge: View {
    var title: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: GTGlassTokens.Space.s) {
            Image(systemName: systemImage)
            Text(title)
                .fontWeight(.semibold)
        }
        .font(.callout)
        .foregroundStyle(tint)
        .padding(.horizontal, GTGlassTokens.Space.l)
        .frame(height: GTGlassTokens.Toolbar.controlHeight)
        .gtGlassSurface(.flat,
                        cornerRadius: GTGlassTokens.Toolbar.radius,
                        fill: tint,
                        fillOpacity: 0.14,
                        gradient: true,
                        interactive: false)
    }
}

struct GTGlassIconButton: View {
    var title: String
    var systemImage: String
    var emphasis: GTGlassEmphasis = .secondary
    var quiet = false
    var size: CGFloat = GTGlassTokens.Toolbar.controlHeight
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    @ViewBuilder
    var body: some View {
        Group {
            if emphasis.usesProminentStyle, let tint = emphasis.tint {
                baseButton
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            } else if let tint = emphasis.tint {
                baseButton
                    .buttonStyle(.glass)
                    .tint(tint)
            } else {
                baseButton
                    .buttonStyle(.glass)
            }
        }
        .opacity(isEnabled ? (quiet && !hovering ? 0.72 : 1) : 0.5)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityLabel(title)
    }

    private var baseButton: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: max(14, size - 10), height: max(14, size - 10))
                .contentShape(Circle())
        }
        .buttonBorderShape(.circle)
        .controlSize(.small)
    }
}

import SwiftUI

enum GTGlassEmphasis: Equatable {
    case secondary
    case primary
    case selected
    case interrupt
    case destructive
    case feedback

    fileprivate var usesProminentStyle: Bool {
        self == .primary
    }

    /// Routine actions and feedback stay monochrome. Accent marks selection
    /// and the single primary action; red is reserved for destructive actions.
    fileprivate var foregroundTint: Color? {
        switch self {
        case .selected:
            return GTGlassPalette.accentForeground
        case .destructive:
            return GTGlassPalette.semanticRed
        default:
            return nil
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

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        if emphasis.usesProminentStyle {
            baseButton
                .buttonStyle(.glassProminent)
                .tint(GTGlassPalette.primaryControlTint(for: colorScheme))
        } else {
            baseButton
                .buttonStyle(.glass)
        }
    }

    private var baseButton: some View {
        Button(role: role, action: action) {
            styledLabel
        }
        .buttonBorderShape(.roundedRectangle(radius: 9))
        .controlSize(compact ? .small : .regular)
    }

    @ViewBuilder
    private var styledLabel: some View {
        if let tint = emphasis.foregroundTint {
            buttonLabel.foregroundStyle(isEnabled ? tint : GTGlassPalette.tertiaryText)
        } else {
            buttonLabel
        }
    }

    private var buttonLabel: some View {
        label()
            .font((compact ? Font.callout : Font.body).weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, compact ? 2 : GTGlassTokens.Space.xs)
            .frame(minWidth: minWidth, minHeight: compact ? 16 : 20)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    @ViewBuilder
    var body: some View {
        Group {
            if emphasis.usesProminentStyle {
                baseButton
                    .buttonStyle(.glassProminent)
                    .tint(GTGlassPalette.primaryControlTint(for: colorScheme))
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
            styledIcon
        }
        .buttonBorderShape(.circle)
        .controlSize(.small)
    }

    @ViewBuilder
    private var styledIcon: some View {
        if let tint = emphasis.foregroundTint {
            icon.foregroundStyle(tint)
        } else {
            icon
        }
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: size * 0.42, weight: .semibold))
            .frame(width: max(14, size - 10), height: max(14, size - 10))
            .contentShape(Circle())
            .contentTransition(.symbolEffect(.replace))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: systemImage)
    }
}

import SwiftUI

struct GTGlassButton<Label: View>: View {
    var role: ButtonRole? = nil
    var tint: Color? = nil
    var prominent = false
    var minWidth: CGFloat? = nil
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            label()
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, GTGlassTokens.Space.m)
                .frame(height: GTGlassTokens.Toolbar.controlHeight)
                .frame(minWidth: minWidth)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.capsule)
        .disabled(!isEnabled)
        .background {
            Capsule(style: .continuous)
                .fill(backgroundFill)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .glassEffect(glass, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.28), lineWidth: 1)
        }
        .onHover { hovering = $0 }
        .opacity(isEnabled ? 1 : 0.58)
        .help(helpText)
    }

    private var glass: Glass {
        let base: Glass
        if prominent {
            base = .regular.tint((tint ?? GTGlassPalette.innerNeutral).opacity(0.30))
        } else {
            base = .regular
        }
        return base.interactive()
    }

    private var foregroundStyle: AnyShapeStyle {
        if role == .destructive { return AnyShapeStyle(Color.red) }
        if prominent { return AnyShapeStyle(Color.primary) }
        return AnyShapeStyle(Color.primary)
    }

    private var backgroundFill: Color {
        if role == .destructive {
            return Color.red.opacity(hovering ? 0.20 : 0.12)
        }
        if prominent {
            return (tint ?? GTGlassPalette.innerNeutral).opacity(hovering ? 0.32 : 0.22)
        }
        return Color.white.opacity(hovering ? (colorScheme == .dark ? 0.14 : 0.24) : 0.06)
    }

    private var helpText: String {
        role == .destructive ? "删除" : ""
    }
}

extension GTGlassButton where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String,
         systemImage: String,
         role: ButtonRole? = nil,
         tint: Color? = nil,
         prominent: Bool = false,
         minWidth: CGFloat? = nil,
         action: @escaping () -> Void) {
        self.role = role
        self.tint = tint
        self.prominent = prominent
        self.minWidth = minWidth
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
                        fill: GTGlassPalette.innerNeutral,
                        fillOpacity: 0.16,
                        gradient: true,
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
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .focused($focused)
            if text.isEmpty {
                Text("⌘K")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } else {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }
        }
        .padding(.horizontal, GTGlassTokens.Space.m)
        .frame(height: GTGlassTokens.Toolbar.controlHeight)
        .contentShape(Capsule(style: .continuous))
        .gtGlassSurface(.flat,
                        cornerRadius: GTGlassTokens.Toolbar.radius,
                        fill: GTGlassPalette.innerNeutral,
                        fillOpacity: focused ? 0.20 : 0.12,
                        gradient: true,
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
    var tint: Color? = nil
    var filled = false
    var size: CGFloat = GTGlassTokens.Toolbar.controlHeight
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(foreground)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            Circle()
                .fill(background)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .glassEffect(glass, in: Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.26), lineWidth: 1)
        }
        .onHover { hovering = $0 }
        .opacity(isEnabled ? 1 : 0.55)
        .help(title)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        if filled { return GTGlassPalette.primaryActionForeground(for: colorScheme) }
        return tint ?? Color.primary
    }

    private var background: Color {
        if filled {
            return GTGlassPalette.primaryActionFill(for: colorScheme)
                .opacity(hovering ? 0.94 : 0.86)
        }
        return (tint ?? GTGlassPalette.innerNeutral)
            .opacity(hovering ? 0.22 : 0.12)
    }

    private var glass: Glass {
        let base = filled
            ? Glass.regular.tint(GTGlassPalette.primaryActionFill(for: colorScheme).opacity(0.28))
            : Glass.regular
        return base.interactive()
    }
}

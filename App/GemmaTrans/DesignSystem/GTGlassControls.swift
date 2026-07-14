import SwiftUI

struct GTGlassButton<Label: View>: View {
    var role: ButtonRole? = nil
    var tint: Color? = nil
    var prominent = false
    var minWidth: CGFloat? = nil
    var compact = false
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        if prominent {
            baseButton
                .buttonStyle(.glassProminent)
                .tint(tint ?? GTGlassPalette.primaryActionTint(for: colorScheme))
        } else if let tint {
            baseButton
                .buttonStyle(.glass)
                .tint(tint)
        } else {
            baseButton
                .buttonStyle(.glass)
                .tint(GTGlassPalette.neutralControlTint(for: colorScheme))
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
         tint: Color? = nil,
         prominent: Bool = false,
         minWidth: CGFloat? = nil,
         compact: Bool = false,
         action: @escaping () -> Void) {
        self.role = role
        self.tint = tint
        self.prominent = prominent
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
    var tint: Color? = nil
    var filled = false
    var quiet = false
    var size: CGFloat = GTGlassTokens.Toolbar.controlHeight
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    @ViewBuilder
    var body: some View {
        Group {
            if filled {
                baseButton
                    .buttonStyle(.glassProminent)
                    .tint(tint ?? GTGlassPalette.primaryActionTint(for: colorScheme))
            } else if let tint {
                baseButton
                    .buttonStyle(.glass)
                    .tint(tint)
            } else {
                baseButton
                    .buttonStyle(.glass)
                    .tint(GTGlassPalette.neutralControlTint(for: colorScheme))
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

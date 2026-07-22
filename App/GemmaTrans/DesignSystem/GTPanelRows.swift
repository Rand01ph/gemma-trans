import SwiftUI

struct GTPanelSection<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: GTGlassTokens.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(GTGlassPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, GTGlassTokens.Space.xs)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            // 垂直留白由每个 row 自己拥有。若把上下 padding 放在整张卡片上，
            // 首行会显得偏下、末行会显得偏上，Divider 也不再是真正的行边界。
            .padding(.horizontal, GTGlassTokens.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gtContentSurface(.form, cornerRadius: GTGlassTokens.Radius.card)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GTPanelDivider: View {
    var body: some View {
        Divider()
    }
}

struct GTPanelRow<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var error: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: GTGlassTokens.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(error == nil ? .primary : GTGlassPalette.semanticRed)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(GTGlassPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: GTGlassTokens.Space.m)
                trailing()
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(GTGlassPalette.semanticRed)
            }
        }
        .gtSettingsRowLayout()
    }
}

extension GTPanelRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, error: String? = nil) {
        self.init(title: title, subtitle: subtitle, error: error) { EmptyView() }
    }
}

struct GTPanelField<Control: View>: View {
    var label: String
    var subtitle: String? = nil
    var labelWidth: CGFloat = 150
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: GTGlassTokens.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(GTGlassPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: labelWidth, alignment: .leading)
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .gtSettingsRowLayout()
    }
}

struct GTSettingsTextFieldRow: View {
    var label: String
    var subtitle: String? = nil
    var prompt: String
    @Binding var text: String
    var error: String? = nil
    var usesMonospacedDigits = false
    var labelWidth: CGFloat = GTSettingsControlMetrics.labelWidth

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .center, spacing: GTGlassTokens.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(GTGlassPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: labelWidth, alignment: .leading)

                Spacer(minLength: GTGlassTokens.Space.m)

                TextField(label, text: $text, prompt: Text(prompt))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                    .font(usesMonospacedDigits ? .body.monospacedDigit() : .body)
                    .frame(width: GTSettingsControlMetrics.compactFieldWidth)
                    .accessibilityHint(error ?? "示例：\(prompt)")
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(GTGlassPalette.semanticRed)
                    .frame(width: GTSettingsControlMetrics.compactFieldWidth,
                           alignment: .leading)
            }
        }
        .gtSettingsRowLayout()
    }
}

struct GTPanelToggleRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        GTPanelRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

enum GTSettingsControlMetrics {
    static let rowMinHeight: CGFloat = 44
    static let rowVerticalPadding: CGFloat = 6
    static let labelWidth: CGFloat = 150
    static let compactFieldWidth: CGFloat = 232
    static let actionWidth: CGFloat = 92
    static let actionHeight: CGFloat = 28
    static let iconSize: CGFloat = 28
    static let cornerRadius: CGFloat = 8
}

private struct GTSettingsRowLayoutModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .padding(.vertical, GTSettingsControlMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity,
                   minHeight: GTSettingsControlMetrics.rowMinHeight,
                   alignment: .center)
    }
}

private extension View {
    func gtSettingsRowLayout() -> some View {
        modifier(GTSettingsRowLayoutModifier())
    }
}

struct GTSettingsActionButton: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(GTSettingsQuietButtonStyle(isHovering: isHovering,
                                                isFocused: isFocused))
        .frame(width: GTSettingsControlMetrics.actionWidth,
               height: GTSettingsControlMetrics.actionHeight)
        .focused($isFocused)
        .onHover { isHovering = $0 }
    }
}

struct GTSettingsDestructiveIconButton: View {
    var title: String
    var action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(GTSettingsQuietButtonStyle(tone: .destructive,
                                                isHovering: isHovering,
                                                isFocused: isFocused))
        .frame(width: GTSettingsControlMetrics.iconSize,
               height: GTSettingsControlMetrics.iconSize)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

private enum GTSettingsButtonTone {
    case neutral
    case destructive
}

private struct GTSettingsQuietButtonStyle: ButtonStyle {
    var tone: GTSettingsButtonTone = .neutral
    var isHovering = false
    var isFocused = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .background {
                RoundedRectangle(cornerRadius: GTSettingsControlMetrics.cornerRadius,
                                 style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .overlay {
                RoundedRectangle(cornerRadius: GTSettingsControlMetrics.cornerRadius,
                                 style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 2 : 1)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.46)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12),
                       value: configuration.isPressed)
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch tone {
        case .neutral:
            return .primary
        case .destructive:
            return isHovering || isFocused || isPressed
                ? GTGlassPalette.semanticRed
                : GTGlassPalette.secondaryText
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        let emphasized = isPressed || isHovering
        switch tone {
        case .neutral:
            return Color.primary.opacity(emphasized
                ? (colorScheme == .dark ? 0.12 : 0.08)
                : (colorScheme == .dark ? 0.065 : 0.045))
        case .destructive:
            return emphasized
                ? GTGlassPalette.semanticRed.opacity(0.12)
                : Color.primary.opacity(colorScheme == .dark ? 0.065 : 0.045)
        }
    }

    private var borderColor: Color {
        if isFocused {
            return GTGlassPalette.accent(for: colorScheme).opacity(0.82)
        }
        switch tone {
        case .neutral:
            return Color.primary.opacity(colorScheme == .dark ? 0.13 : 0.10)
        case .destructive:
            return isHovering || isFocused
                ? GTGlassPalette.semanticRed.opacity(0.34)
                : Color.primary.opacity(colorScheme == .dark ? 0.13 : 0.10)
        }
    }
}

struct GTModelStateBadge: View {
    var text = "当前使用"

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .foregroundStyle(GTGlassPalette.accentForeground)
            Text(text)
                .foregroundStyle(.primary)
        }
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .frame(width: GTSettingsControlMetrics.actionWidth,
                   height: GTSettingsControlMetrics.actionHeight)
            .background {
                RoundedRectangle(cornerRadius: GTSettingsControlMetrics.cornerRadius,
                                 style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.065 : 0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: GTSettingsControlMetrics.cornerRadius,
                                 style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.13 : 0.10),
                                  lineWidth: 1)
            }
            .accessibilityLabel(text)
    }
}

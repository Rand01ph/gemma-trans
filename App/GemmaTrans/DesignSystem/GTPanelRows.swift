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
            .padding(GTGlassTokens.Space.m)
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
                        .foregroundStyle(error == nil ? .primary : Color.red)
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
                    .foregroundStyle(.red)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, GTSettingsControlMetrics.rowVerticalPadding)
        .frame(minHeight: GTSettingsControlMetrics.rowMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .contentShape(Rectangle())
        .padding(.vertical, GTSettingsControlMetrics.rowVerticalPadding)
        .frame(minHeight: GTSettingsControlMetrics.rowMinHeight)
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
                    .foregroundStyle(.red)
                    .frame(width: GTSettingsControlMetrics.compactFieldWidth,
                           alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, GTSettingsControlMetrics.rowVerticalPadding)
        .frame(minHeight: GTSettingsControlMetrics.rowMinHeight)
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
                .tint(GTGlassPalette.semanticGreen)
        }
    }
}

enum GTSettingsControlMetrics {
    static let rowMinHeight: CGFloat = 40
    static let rowVerticalPadding: CGFloat = 6
    static let labelWidth: CGFloat = 150
    static let compactFieldWidth: CGFloat = 232
    static let actionWidth: CGFloat = 92
    static let actionHeight: CGFloat = 28
    static let iconSize: CGFloat = 28
    static let cornerRadius: CGFloat = 8
}

struct GTSettingsActionButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: GTSettingsControlMetrics.cornerRadius))
        .controlSize(.small)
        .frame(width: GTSettingsControlMetrics.actionWidth,
               height: GTSettingsControlMetrics.actionHeight)
    }
}

struct GTSettingsOverflowMenu<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu(content: content) {
            Image(systemName: "ellipsis")
                .font(.callout.weight(.semibold))
                .frame(width: GTSettingsControlMetrics.iconSize,
                       height: GTSettingsControlMetrics.iconSize)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .frame(width: GTSettingsControlMetrics.iconSize,
               height: GTSettingsControlMetrics.iconSize)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct GTModelStateBadge: View {
    var text = "当前使用"

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(text, systemImage: "checkmark")
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .frame(width: GTSettingsControlMetrics.actionWidth,
                   height: GTSettingsControlMetrics.actionHeight)
            .foregroundStyle(GTGlassPalette.accent(for: colorScheme))
            .background {
                RoundedRectangle(cornerRadius: GTSettingsControlMetrics.cornerRadius,
                                 style: .continuous)
                    .fill(GTGlassPalette.accent(for: colorScheme)
                        .opacity(colorScheme == .dark ? 0.14 : 0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: GTSettingsControlMetrics.cornerRadius,
                                 style: .continuous)
                    .strokeBorder(GTGlassPalette.accent(for: colorScheme).opacity(0.18), lineWidth: 1)
            }
            .accessibilityLabel(text)
    }
}

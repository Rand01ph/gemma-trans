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
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, GTGlassTokens.Space.xs)

            VStack(alignment: .leading, spacing: GTGlassTokens.Space.m) {
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Divider()
            .opacity(colorScheme == .dark ? 0.55 : 0.36)
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
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: labelWidth, alignment: .leading)
                control()
                    .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
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

struct GTSettingsGlassButton: View {
    var title: String
    var systemImage: String
    var minWidth: CGFloat = 72
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: minWidth, minHeight: 20)
        }
        .buttonStyle(.glass)
        .tint(GTGlassPalette.neutralControlTint(for: colorScheme))
        .buttonBorderShape(.roundedRectangle(radius: 9))
        .controlSize(.regular)
    }
}

struct GTSettingsGlassMenu<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Menu(content: content) {
            Image(systemName: "ellipsis")
                .font(.callout.weight(.semibold))
                .frame(width: 28, height: 20)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .tint(GTGlassPalette.neutralControlTint(for: colorScheme))
        .buttonBorderShape(.roundedRectangle(radius: 9))
        .controlSize(.regular)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct GTModelStateBadge: View {
    var text = "当前使用"

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(text, systemImage: "checkmark")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundStyle(GTGlassPalette.positiveForeground(for: colorScheme))
            .glassEffect(
                .regular.tint(GTGlassPalette.positiveSurfaceTint(for: colorScheme)),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
    }
}

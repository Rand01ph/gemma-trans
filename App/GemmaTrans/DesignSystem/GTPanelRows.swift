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
            .gtGlassSurface(.flat,
                            cornerRadius: GTGlassTokens.Radius.card,
                            fill: GTGlassPalette.innerNeutral,
                            fillOpacity: 0.13,
                            gradient: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GTPanelDivider: View {
    var body: some View {
        Divider()
            .opacity(0.55)
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

struct GTActiveBadge: View {
    var text = "活跃"

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, GTGlassTokens.Space.s)
            .padding(.vertical, 3)
            .foregroundStyle(GTGlassPalette.semanticGreen)
            .gtGlassSurface(.flat,
                            cornerRadius: 7,
                            fill: GTGlassPalette.semanticGreen,
                            fillOpacity: 0.20,
                            gradient: false,
                            stroke: false)
    }
}

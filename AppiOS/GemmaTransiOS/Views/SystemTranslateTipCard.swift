import SwiftUI

/// 就绪空态时一次性引导卡（spec 3.4）：教用户「在任何 App 选中文字即可用 GemmaTrans 翻译」。
/// @AppStorage 记忆 dismissed，去设置或以后再说后永不再现（设置 sheet 保留常驻入口）。
struct SystemTranslateTipCard: View {
    @AppStorage("tipDismissed") private var dismissed = false
    /// 「去设置」：跳系统设置（与 SettingsSheet 同款入口）
    let onOpenSettings: () -> Void

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "character.bubble")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 10) {
                    Text("在任何 App 选中文字即可用 GemmaTrans 翻译")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Button("去设置") {
                            onOpenSettings()
                            dismissed = true
                        }
                        .font(.subheadline.weight(.medium))
                        Button("以后再说") { dismissed = true }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(Theme.Spacing.cardPadding)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

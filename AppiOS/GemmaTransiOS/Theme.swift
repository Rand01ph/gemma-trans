import SwiftUI

/// 设计语言常量与共享 helper（详见 docs/superpowers/specs/2026-06-12-ios-ui-redesign.md 第 1 节）。
/// 全部系统语义色 + 系统材质，唯一品牌色 AccentColor（Assets 双值松石绿）。
enum Theme {
    /// 4pt 网格间距
    enum Spacing {
        static let screenH: CGFloat = 16      // 屏幕水平边距
        static let cardPadding: CGFloat = 16  // 卡内 padding
        static let cardGap: CGFloat = 12      // 卡间距
        static let section: CGFloat = 24      // 区块间距
    }

    /// 圆角（iOS 26 大圆角语境）。卡片 20、卡内嵌控件 12，遵守同心圆角。
    enum Radius {
        static let card: CGFloat = 20
        static let inner: CGFloat = 12
    }

    /// 触控目标下限
    static let minTouch: CGFloat = 44
}

// MARK: - 自适应主按钮（iOS26 glassEffect / 18.4 borderedProminent 回退）

extension View {
    /// 主操作按钮样式：iOS 26+ 走 Liquid Glass，18.4 回退 borderedProminent。
    /// 仅用于全宽 capsule 主按钮（下载、继续下载、面板跳转）。
    @ViewBuilder
    func adaptiveGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .tint(.accentColor)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - 卡片容器

/// 分组背景上的实底卡：secondarySystemGroupedBackground + 20pt continuous 圆角，无阴影无描边。
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}

// MARK: - 拷贝触感

enum Haptics {
    /// 拷贝成功的轻触感反馈
    static func copySuccess() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - 语向标签

enum LanguageLabel {
    /// BCP-47 代码 → 中文可读名（仅覆盖产品常见语向，未命中回落代码本身）
    static func display(_ code: String) -> String {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        switch base {
        case "zh": return "中文"
        case "en": return "English"
        case "ja": return "日本語"
        case "ko": return "한국어"
        case "fr": return "Français"
        case "de": return "Deutsch"
        case "es": return "Español"
        case "ru": return "Русский"
        case "it": return "Italiano"
        case "pt": return "Português"
        case "und": return "自动"
        default:
            let id = Locale(identifier: "zh-Hans")
            return id.localizedString(forLanguageCode: base) ?? code
        }
    }

    /// `中文 → English`（翻译完成后的实际语向）
    static func arrow(detected: String, target: String) -> String {
        "\(display(detected)) → \(display(target))"
    }
}

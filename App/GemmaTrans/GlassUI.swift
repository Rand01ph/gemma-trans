import AppKit
import GemmaTransKit
import SwiftUI

enum GlassMetrics {
    static let windowCornerRadius: CGFloat = 22
    static let windowChromeHeight: CGFloat = 42
    static let panelCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 8
    static let rowHeight: CGFloat = 44
    static let controlHeight: CGFloat = 30
    static let sidebarWidth: CGFloat = 148
    static let settingsWidth: CGFloat = 780
    static let settingsHeight: CGFloat = 620
}

final class GlassWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor @Observable
final class AppearanceController {
    static let shared = AppearanceController()

    var mode: AppAppearanceMode {
        didSet { persistMode() }
    }

    private init() {
        mode = AppSettings.load().appearanceMode
    }

    func setMode(_ mode: AppAppearanceMode) {
        self.mode = mode
    }

    private func persistMode() {
        var settings = AppSettings.load()
        guard settings.appearanceMode != mode else { return }
        settings.appearanceMode = mode
        settings.save()
    }
}

struct GlassTheme {
    let isDark: Bool
    let windowOverlay: Color
    let panelOverlay: Color
    let insetOverlay: Color
    let controlFill: Color
    let activeControlFill: Color
    let selectedControlFill: Color
    let selectedControlText: Color
    let primaryControlFill: Color
    let primaryControlText: Color
    let disabledControlFill: Color
    let disabledControlText: Color
    let successFill: Color
    let successText: Color
    let hairline: Color
    let innerHairline: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let shadow: Color
    let accent: Color
    let destructive: Color
    let preferredColorScheme: ColorScheme?
    let nsAppearance: NSAppearance.Name?
    let nsTextColor: NSColor
    let nsInsertionPointColor: NSColor
    let nsWindowBackgroundColor: NSColor

    static func resolve(mode: AppAppearanceMode, systemScheme: ColorScheme) -> GlassTheme {
        switch mode {
        case .light:
            return .light(forced: true)
        case .dark:
            return .dark(forced: true)
        case .system:
            return systemScheme == .dark ? .dark(forced: false) : .light(forced: false)
        }
    }

    private static func light(forced: Bool) -> GlassTheme {
        GlassTheme(
            isDark: false,
            windowOverlay: Color(red: 0.78, green: 0.84, blue: 0.91).opacity(0.58),
            panelOverlay: .white.opacity(0.84),
            insetOverlay: .white.opacity(0.72),
            controlFill: .white.opacity(0.78),
            activeControlFill: Color(red: 0.16, green: 0.43, blue: 0.86).opacity(0.16),
            selectedControlFill: Color(red: 0.18, green: 0.48, blue: 0.92).opacity(0.86),
            selectedControlText: .white,
            primaryControlFill: Color(red: 0.15, green: 0.42, blue: 0.86).opacity(0.92),
            primaryControlText: .white,
            disabledControlFill: Color(red: 0.82, green: 0.86, blue: 0.91).opacity(0.74),
            disabledControlText: .black.opacity(0.36),
            successFill: Color(red: 0.16, green: 0.68, blue: 0.36).opacity(0.16),
            successText: Color(red: 0.05, green: 0.45, blue: 0.21),
            hairline: .black.opacity(0.18),
            innerHairline: .white.opacity(0.46),
            textPrimary: Color(red: 0.08, green: 0.10, blue: 0.13),
            textSecondary: .black.opacity(0.70),
            textTertiary: .black.opacity(0.52),
            shadow: .black.opacity(0.11),
            accent: Color(red: 0.12, green: 0.40, blue: 0.86),
            destructive: Color(red: 0.84, green: 0.16, blue: 0.16),
            preferredColorScheme: forced ? .light : nil,
            nsAppearance: forced ? .aqua : nil,
            nsTextColor: NSColor(calibratedWhite: 0.12, alpha: 1),
            nsInsertionPointColor: .controlAccentColor,
            nsWindowBackgroundColor: NSColor(calibratedRed: 0.84, green: 0.86, blue: 0.90, alpha: 0.96)
        )
    }

    private static func dark(forced: Bool) -> GlassTheme {
        GlassTheme(
            isDark: true,
            windowOverlay: Color(red: 0.03, green: 0.07, blue: 0.10).opacity(0.54),
            panelOverlay: .white.opacity(0.12),
            insetOverlay: .white.opacity(0.075),
            controlFill: .white.opacity(0.16),
            activeControlFill: Color(red: 0.32, green: 0.58, blue: 1.00).opacity(0.18),
            selectedControlFill: Color(red: 0.20, green: 0.47, blue: 0.95).opacity(0.82),
            selectedControlText: .white.opacity(0.96),
            primaryControlFill: Color(red: 0.22, green: 0.49, blue: 0.96).opacity(0.78),
            primaryControlText: .white.opacity(0.96),
            disabledControlFill: .white.opacity(0.10),
            disabledControlText: .white.opacity(0.40),
            successFill: Color(red: 0.24, green: 0.82, blue: 0.44).opacity(0.17),
            successText: Color(red: 0.46, green: 0.92, blue: 0.61),
            hairline: .white.opacity(0.12),
            innerHairline: .white.opacity(0.08),
            textPrimary: .white.opacity(0.95),
            textSecondary: .white.opacity(0.72),
            textTertiary: .white.opacity(0.54),
            shadow: .black.opacity(0.34),
            accent: Color(red: 0.44, green: 0.66, blue: 1.00),
            destructive: Color(red: 1.00, green: 0.36, blue: 0.34),
            preferredColorScheme: forced ? .dark : nil,
            nsAppearance: forced ? .darkAqua : nil,
            nsTextColor: NSColor(calibratedWhite: 0.90, alpha: 1),
            nsInsertionPointColor: .controlAccentColor,
            nsWindowBackgroundColor: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 0.96)
        )
    }
}

extension View {
    func glassPreferredColorScheme(_ theme: GlassTheme) -> some View {
        preferredColorScheme(theme.preferredColorScheme)
    }
}

struct GlassWindowConfigurator: NSViewRepresentable {
    var hideTitle = false
    var movableByBackground = false
    var appearanceName: NSAppearance.Name?
    var backgroundColor: NSColor = .clear
    var cornerRadius: CGFloat = GlassMetrics.windowCornerRadius

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = backgroundColor
        window.hasShadow = false
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = movableByBackground
        if let appearanceName {
            window.appearance = NSAppearance(named: appearanceName)
        } else {
            window.appearance = nil
        }
        [window.contentView, window.contentView?.superview].forEach { view in
            view?.wantsLayer = true
            view?.layer?.cornerRadius = cornerRadius
            view?.layer?.masksToBounds = true
        }
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        if hideTitle {
            window.titleVisibility = .hidden
        }
    }
}

struct GlassWindowControls: View {
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            control(.close)
            control(.minimize)
            control(.zoom)
        }
        .onHover { isHovering = $0 }
    }

    private func control(_ control: GlassWindowControl) -> some View {
        Button {
            control.perform()
        } label: {
            ZStack {
                Circle()
                    .fill(control.color(isHovering: isHovering))
                if isHovering {
                    Image(systemName: control.symbol)
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(control.symbolColor)
                }
            }
            .frame(width: 13, height: 13)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private enum GlassWindowControl {
    case close
    case minimize
    case zoom

    var symbol: String {
        switch self {
        case .close: "xmark"
        case .minimize: "minus"
        case .zoom: "plus"
        }
    }

    var symbolColor: Color {
        switch self {
        case .close: Color(red: 0.45, green: 0.02, blue: 0.04)
        case .minimize: Color(red: 0.45, green: 0.28, blue: 0.00)
        case .zoom: Color(red: 0.09, green: 0.32, blue: 0.08)
        }
    }

    func color(isHovering: Bool) -> Color {
        let opacity = isHovering ? 1.0 : 0.76
        switch self {
        case .close:
            return Color(red: 1.00, green: 0.33, blue: 0.37).opacity(opacity)
        case .minimize:
            return Color(red: 1.00, green: 0.75, blue: 0.16).opacity(opacity)
        case .zoom:
            return Color(red: 0.20, green: 0.78, blue: 0.30).opacity(opacity)
        }
    }

    @MainActor
    func perform() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        switch self {
        case .close:
            window.close()
        case .minimize:
            window.miniaturize(nil)
        case .zoom:
            window.zoom(nil)
        }
    }
}

struct GlassWindowBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared

    var cornerRadius: CGFloat = 0

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if cornerRadius > 0 {
                shape.fill(theme.isDark ? .regularMaterial : .thinMaterial)
                    .overlay { shape.fill(theme.windowOverlay) }
            } else {
                Rectangle().fill(theme.isDark ? .regularMaterial : .thinMaterial)
                    .overlay { Rectangle().fill(theme.windowOverlay) }
            }
        }
        .ignoresSafeArea()
    }
}

struct GlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared

    var cornerRadius: CGFloat = GlassMetrics.panelCornerRadius
    var fill: Color?
    var stroke: Color?
    var shadowOpacity: Double?
    var shadowRadius: CGFloat = 9
    var shadowY: CGFloat = 4

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fillColor = fill ?? theme.panelOverlay
        let strokeColor = stroke ?? theme.hairline
        let shadowAlpha = shadowOpacity ?? (theme.isDark ? 0.30 : 0.08)

        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(fillColor), in: .rect(cornerRadius: cornerRadius))
                .overlay { shape.fill(fillColor) }
                .overlay { shape.strokeBorder(strokeColor, lineWidth: 0.5) }
                .shadow(color: theme.shadow.opacity(shadowAlpha), radius: shadowRadius, x: 0, y: shadowY)
        } else {
            shape
                .fill(theme.isDark ? .regularMaterial : .thinMaterial)
                .overlay { shape.fill(fillColor) }
                .overlay { shape.strokeBorder(strokeColor, lineWidth: 0.5) }
                .shadow(color: theme.shadow.opacity(shadowAlpha), radius: shadowRadius, x: 0, y: shadowY)
        }
    }
}

struct GlassSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared

    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { GlassSurface(cornerRadius: GlassMetrics.panelCornerRadius) }
        }
    }
}

struct GlassIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared

    let systemName: String
    let help: String
    var isActive = false
    var isDisabled = false
    var size = CGSize(width: 26, height: 24)
    var fontSize: CGFloat = 13
    var cornerRadius: CGFloat = 7
    let action: () -> Void

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: size.width, height: size.height)
                .background { buttonShape.fill(backgroundColor) }
                .overlay { buttonShape.strokeBorder(theme.hairline, lineWidth: 0.6) }
                .contentShape(buttonShape)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var backgroundColor: Color {
        if isDisabled { return theme.disabledControlFill }
        return isActive ? theme.selectedControlFill : theme.controlFill
    }

    private var iconColor: Color {
        if isDisabled { return theme.disabledControlText }
        return isActive ? theme.selectedControlText : theme.textPrimary
    }
}

struct GlassPillButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared

    let title: String
    var isPrimary = false
    var isDestructive = false
    var isDisabled = false
    var minWidth: CGFloat = 72
    var horizontalPadding: CGFloat = 12
    let action: () -> Void

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: minWidth, minHeight: GlassMetrics.controlHeight)
                .background {
                    RoundedRectangle(cornerRadius: GlassMetrics.controlCornerRadius, style: .continuous)
                        .fill(background)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: GlassMetrics.controlCornerRadius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var background: Color {
        if isDisabled { return theme.disabledControlFill }
        if isPrimary { return theme.primaryControlFill }
        return theme.controlFill
    }

    private var foreground: Color {
        if isDisabled { return theme.disabledControlText }
        if isDestructive { return theme.destructive }
        if isPrimary { return theme.primaryControlText }
        return theme.textPrimary
    }

    private var stroke: Color {
        if isDisabled { return theme.hairline.opacity(0.80) }
        if isPrimary { return theme.accent.opacity(theme.isDark ? 0.42 : 0.32) }
        return theme.hairline
    }
}

struct GlassFieldBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = AppearanceController.shared

    private var theme: GlassTheme {
        GlassTheme.resolve(mode: appearance.mode, systemScheme: colorScheme)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: GlassMetrics.controlCornerRadius, style: .continuous)
            .fill(theme.insetOverlay)
            .overlay {
                RoundedRectangle(cornerRadius: GlassMetrics.controlCornerRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 0.6)
            }
    }
}

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = NSFont.systemFontSize
    var textColor: NSColor = .labelColor
    var insertionPointColor: NSColor = .controlAccentColor

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentInsets = NSEdgeInsetsZero

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

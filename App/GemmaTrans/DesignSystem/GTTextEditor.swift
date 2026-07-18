import AppKit
import SwiftUI

/// A narrowly wrapped native editor whose placeholder and insertion point share
/// the same AppKit text-container origin.
struct GTTextEditor: NSViewRepresentable {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var placeholder: String
    var supportingText: String

    private static let textInset = NSSize(width: 12, height: 12)

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, focused: focused)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.placeholder = placeholder
        textView.supportingText = supportingText
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.focusRingType = .none
        textView.textContainerInset = Self.textInset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }

        context.coordinator.text = $text
        context.coordinator.focused = focused

        if textView.string != text {
            textView.string = text
        }
        textView.placeholder = placeholder
        textView.supportingText = supportingText
        textView.needsDisplay = true

        guard focused.wrappedValue,
              textView.window?.firstResponder !== textView else { return }

        DispatchQueue.main.async { [weak textView] in
            guard let textView,
                  textView.window?.firstResponder !== textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var focused: FocusState<Bool>.Binding

        init(text: Binding<String>, focused: FocusState<Bool>.Binding) {
            self.text = text
            self.focused = focused
        }

        func textDidBeginEditing(_ notification: Notification) {
            focused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            focused.wrappedValue = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class PlaceholderTextView: NSTextView {
    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    var supportingText = "" {
        didSet { needsDisplay = true }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }

        let origin = textContainerOrigin
        let bodyFont = font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let placeholderString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: bodyFont,
                .foregroundColor: GTGlassPalette.secondaryTextNSColor
            ]
        )
        placeholderString.draw(at: origin)

        guard !supportingText.isEmpty else { return }
        let supportingOrigin = NSPoint(
            x: origin.x,
            y: origin.y + ceil(bodyFont.boundingRectForFont.height) + 8
        )
        NSAttributedString(
            string: supportingText,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: GTGlassPalette.secondaryTextNSColor
            ]
        ).draw(at: supportingOrigin)
    }
}

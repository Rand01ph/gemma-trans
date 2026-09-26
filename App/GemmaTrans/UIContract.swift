import SwiftUI

/// Stable identifiers in production; geometry export exists only in Debug fixtures.
extension View {
    func gtUIElement(_ id: String, text: String = "", enabled: Bool = true) -> some View {
        accessibilityIdentifier(id)
#if DEBUG
            .modifier(UIContractElement(id: id, text: text, enabled: enabled))
#endif
    }
}

#if DEBUG
struct UIElementSnapshot: Codable {
    let id: String
    let text: String
    let enabled: Bool
    let frame: [Double]
}

@MainActor
enum UIContractRegistry {
    static var elements: [String: UIElementSnapshot] = [:]
    static var owners: [String: UUID] = [:]
}

private struct UIContractElement: ViewModifier {
    let id: String
    let text: String
    let enabled: Bool
    @State private var frame = CGRect.zero
    @State private var owner = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { record(frame) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { value in
                frame = value
                record(value)
            }
            .onChange(of: text) { _, _ in record(frame) }
            .onChange(of: enabled) { _, _ in record(frame) }
            .onDisappear {
                if UIContractRegistry.owners[id] == owner {
                    UIContractRegistry.elements[id] = nil
                    UIContractRegistry.owners[id] = nil
                }
            }
    }
    private func record(_ frame: CGRect) {
        guard GTDebugScreenshotFixture.scene != nil else { return }
        UIContractRegistry.owners[id] = owner
        UIContractRegistry.elements[id] = UIElementSnapshot(
            id: id, text: text, enabled: enabled,
            frame: [frame.minX, frame.minY, frame.width, frame.height].map(Double.init))
    }
}
#endif

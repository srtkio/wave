import SwiftUI

/// Native look: system accent, semantic colours, default text styles. Only what isn't already a system value lives here.
enum Theme {
    static let accent = Color.accentColor
    /// AirInk mixes accent with accent2 along each stroke; the same colour keeps ink one calm tone.
    static let accent2 = accent
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let corner: CGFloat = 10
}

extension View {
    /// A rounded platter like a grouped-form section, for cards outside a Form.
    func card(highlighted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
        return padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? AnyShapeStyle(Theme.accent.opacity(0.12)) : AnyShapeStyle(.quinary), in: shape)
            .overlay(shape.strokeBorder(highlighted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.separator), lineWidth: highlighted ? 1.5 : 0.5))
    }
}

import SwiftUI

// One visual language for every tab: Vision Pro–style glass floating over the live camera.
enum Theme {
    static let accent = Color(red: 0.42, green: 0.78, blue: 1.0)      // icy blue
    static let accent2 = Color(red: 0.75, green: 0.55, blue: 1.0)     // soft violet
    static let success = Color(red: 0.35, green: 0.95, blue: 0.65)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let corner: CGFloat = 22
    static let pad: CGFloat = 20
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.75)

    static func title(_ s: String) -> some View {
        Text(s).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(.white)
    }
    static func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.7))
    }
}

extension View {
    /// Frosted glass card. Use for every panel drawn over the camera.
    func glass(corner: CGFloat = Theme.corner, highlighted: Bool = false) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(highlighted ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.white.opacity(0.18)),
                                  lineWidth: highlighted ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            .environment(\.colorScheme, .dark)
    }
}

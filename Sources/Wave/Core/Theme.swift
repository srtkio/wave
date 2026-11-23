import SwiftUI

// One visual language for every tab: Vision Pro–style glass floating over the live camera.
enum Theme {
    static let accent = Color(red: 0.42, green: 0.78, blue: 1.0)      // icy blue
    static let accent2 = Color(red: 0.75, green: 0.55, blue: 1.0)     // soft violet
    static let success = Color(red: 0.35, green: 0.95, blue: 0.65)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let corner: CGFloat = 28       // panels
    static let cardCorner: CGFloat = 16   // cards inside a panel
    static let pad: CGFloat = 20
    static let panelWidth: CGFloat = 360
    /// Stage margins: the top clears the traffic lights, the bottom clears the tab bar.
    static let insets = EdgeInsets(top: 44, leading: 20, bottom: 84, trailing: 20)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.75)

    static func title(_ s: String) -> some View {
        Text(s).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(.white)
    }
    static func heading(_ s: String) -> some View {
        Text(s).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
    }
    static func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.7))
    }
}

extension View {
    /// Frosted glass. Use for everything that floats directly over the camera.
    func glass(corner: CGFloat = Theme.corner, highlighted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return self
            .background(.black.opacity(0.22), in: shape) // keeps text readable over a bright room
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(highlighted ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.white.opacity(0.18)),
                                        lineWidth: highlighted ? 2 : 1))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            .environment(\.colorScheme, .dark)
    }

    /// Lighter platter for cards inside a glass panel.
    func card(highlighted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
        return self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? AnyShapeStyle(Theme.accent.opacity(0.16)) : AnyShapeStyle(.white.opacity(0.07)), in: shape)
            .overlay(shape.strokeBorder(highlighted ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.white.opacity(0.1)),
                                        lineWidth: highlighted ? 1.5 : 1))
    }

    /// Pins a tab's panel to the stage's right column, the same place on every tab.
    func stageColumn() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(Theme.insets)
    }

    /// Hugs its content when it fits the panel, scrolls when it doesn't.
    func panelScroll() -> some View {
        // The 8pt bleed keeps lit, scaled-up cards from being clipped by the scroll view's edges.
        ViewThatFits(in: .vertical) {
            self
            ScrollView { padding(8) }
                .scrollIndicators(.hidden)
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 8)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 32)
                    }
                }
                .padding(-8)
        }
    }
}

/// The one panel every tab uses: symbol, title and caption, then the tab's own content.
struct Panel<Content: View>: View {
    let symbol: String, title: String, caption: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.gradient)
                    Theme.title(title)
                }
                Theme.caption(caption).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(Theme.pad)
        .frame(width: Theme.panelWidth, alignment: .leading)
        .glass()
    }
}

/// Capsule button with hover and press feedback. `prominent` is for the one main action on screen.
struct GlassButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, prominent: prominent)
    }

    private struct GlassButton: View {
        let configuration: Configuration
        let prominent: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(prominent ? AnyShapeStyle(.black.opacity(0.82)) : AnyShapeStyle(.white))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(prominent ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.white.opacity(hover ? 0.2 : 0.12)), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(hover ? 0.4 : 0.15)))
                .brightness(prominent && hover ? 0.08 : 0)
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.95 : hover ? 1.03 : 1)
                .opacity(enabled ? 1 : 0.45)
                .onHover { hover = $0 && enabled }
                .animation(Theme.spring, value: hover)
                .animation(Theme.spring, value: configuration.isPressed)
        }
    }
}

/// Gradient switch drawn in SwiftUI, so it matches the glass and shows up in `--snapshot`.
struct GlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(configuration.isOn ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.white.opacity(0.16)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle().fill(.white).padding(2.5).shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .frame(width: 40, height: 24)
            .contentShape(Capsule())
            .onTapGesture { withAnimation(Theme.spring) { configuration.isOn.toggle() } }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
            }
    }
}

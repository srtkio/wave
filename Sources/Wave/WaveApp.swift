import AppKit
import SwiftUI

@main
struct WaveMain {
    static func main() {
        // Must branch before anything touches the camera or NSApplication.
        if CommandLine.arguments.contains("--selftest") { SelfTest.run() }
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua) // glass over a camera only works dark
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { Snapshot.run(to: CommandLine.arguments[i + 1]) }
        }
        NSApp.setActivationPolicy(.regular)
        WaveApp.main()
    }
}

struct WaveApp: App {
    var body: some Scene {
        WindowGroup("Wave", id: "main") {
            WaveRoot()
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { HandTracker.shared.start(); ShortcutEngine.shared.start(); FeatureHub.shared.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        MenuBarExtra("Wave", systemImage: "hand.wave") { MenuContent() }
    }
}

enum Tab: String, CaseIterable {
    case learn, playground, shortcuts, features

    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .learn: "hand.raised.fill"
        case .playground: "cube.transparent.fill"
        case .shortcuts: "bolt.fill"
        case .features: "switch.2"
        }
    }
}

/// The window: one camera stage shared by all tabs, with a floating tab bar.
struct WaveRoot: View {
    @State private var tab: Tab

    init(tab: Tab = .learn) { _tab = State(initialValue: tab) }

    var body: some View {
        let denied = HandTracker.shared.authorized == false
        CameraStage { size in
            Group {
                switch tab {
                case .learn: LearnView(tab: $tab)
                case .playground: PlaygroundView(size: size)
                case .shortcuts: ShortcutsView()
                case .features: FeaturesView()
                }
            }
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 30)), removal: .opacity))
        }
        .overlay(alignment: .bottom) {
            if !denied { TabBar(tab: $tab).padding(.bottom, 20).transition(.opacity) }
        }
        .toggleStyle(GlassToggleStyle())
        .ignoresSafeArea()
        .animation(Theme.spring, value: denied)
    }
}

private struct TabBar: View {
    @Binding var tab: Tab
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, t in
                TabSegment(tab: t, selected: tab == t, highlight: highlight) {
                    withAnimation(Theme.spring) { tab = t }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                .help("\(t.title) (⌘\(i + 1))")
            }
        }
        .padding(5)
        .glass(corner: 26)
    }
}

private struct TabSegment: View {
    let tab: Tab, selected: Bool, highlight: Namespace.ID, action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(tab.title, systemImage: tab.symbol)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(selected ? 1 : hover ? 0.85 : 0.6))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background {
                    if selected {
                        Capsule().fill(.white.opacity(0.2))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
                            .matchedGeometryEffect(id: "selected", in: highlight)
                    } else if hover {
                        Capsule().fill(.white.opacity(0.07))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .onHover { hover = $0 }
        .animation(Theme.spring, value: hover)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.spring, value: configuration.isPressed)
    }
}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Window") {
            // openWindow on a WindowGroup always makes a new window, so reuse an open one.
            if let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
                w.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }
            NSApp.activate()
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

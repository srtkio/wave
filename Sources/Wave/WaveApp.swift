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
        NSApp.setActivationPolicy(.accessory) // menu-bar app: no Dock icon, no window at launch
        WaveApp.main()
    }
}

struct WaveApp: App {
    init() {
        ShortcutEngine.shared.start()
        FeatureHub.shared.start()
        HandSigns.shared.start()
        CursorMode.shared.start()
    }

    var body: some Scene {
        // Optional window for Learn/Playground/etc; everything else runs from the menu bar.
        Window("Wave", id: "main") {
            WaveRoot()
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { HandTracker.shared.start() } // the window needs the camera
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .defaultLaunchBehavior(.suppressed)
        MenuBarExtra {
            MenuPanel()
        } label: {
            Image(systemName: HandTracker.shared.running ? "hand.wave.fill" : "hand.wave")
        }
        .menuBarExtraStyle(.window)
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

private struct MenuPanel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let t = HandTracker.shared
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "hand.wave.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.gradient)
                Text("Wave").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Toggle("Wave on", isOn: Binding(get: { t.running }, set: { $0 ? t.start() : t.stop() }))
                    .toggleStyle(.switch).labelsHidden()
            }
            Text(status(t)).font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            HandSignsMenu()
            Divider()
            Button("Open Wave window…") {
                openWindow(id: "main")
                NSApp.activate()
            }
            Button("Quit Wave") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(16)
        .frame(width: 300)
    }

    private func status(_ t: HandTracker) -> String {
        guard t.running else { return "Off. The camera is not in use." }
        if t.authorized == false { return "Camera access is off. Allow it in System Settings." }
        if t.cursorActive { return "Cursor mode" }
        return t.handVisible ? "Seeing: \(t.gesture.title)" : "Looking for your hand…"
    }
}

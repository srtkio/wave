import AppKit
import SwiftUI

@main
struct WaveMain {
    static func main() {
        // Must branch before anything touches the camera or NSApplication.
        if CommandLine.arguments.contains("--selftest") { SelfTest.run() }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { Snapshot.run(to: CommandLine.arguments[i + 1]) }
        }
        NSApplication.shared.setActivationPolicy(.regular) // creates NSApp; normal app: Dock icon, window at launch; menu bar + notch still work
        WaveApp.main()
    }
}

struct WaveApp: App {
    init() {
        FeatureHub.shared.start()
        HandSigns.shared.start()
        CursorMode.shared.start()
    }

    var body: some Scene {
        // Opens at launch and from the Dock icon; the menu bar and notch keep working when it is closed.
        Window("Wave", id: "main") {
            WaveRoot()
                .onAppear { HandTracker.shared.start() } // the window needs the camera
        }
        .defaultSize(width: 1180, height: 760)
        MenuBarExtra {
            MenuPanel()
        } label: {
            Image(systemName: HandTracker.shared.running ? "hand.wave.fill" : "hand.wave")
        }
        .menuBarExtraStyle(.window)
    }
}

enum Page: String, CaseIterable, Identifiable {
    case home, cursor, signs, features, learn, playground, log
    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .cursor: "Cursor"
        case .signs: "Hand Signs"
        case .features: "Features"
        case .learn: "Learn"
        case .playground: "Playground"
        case .log: "Log"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house"
        case .cursor: "cursorarrow.motionlines"
        case .signs: "hand.raised"
        case .features: "switch.2"
        case .learn: "graduationcap"
        case .playground: "cube"
        case .log: "doc.plaintext"
        }
    }
}

/// The window: a sidebar of pages, or the camera filling the window while fullscreen is on.
struct WaveRoot: View {
    @State private var page: Page?
    @State private var fullscreen = false
    @State private var enteredNativeFullscreen = false
    @Environment(\.snapshot) private var snapshot

    init(page: Page = .home) { _page = State(initialValue: page) }

    var body: some View {
        Group {
            if fullscreen {
                FullscreenCamera(playground: page == .playground) { setFullscreen(false) }
            } else {
                NavigationSplitView {
                    List(selection: $page) {
                        Section {
                            row(.home)
                        }
                        Section("Control") {
                            row(.cursor); row(.signs); row(.features)
                        }
                        Section("Practice") {
                            row(.learn); row(.playground)
                        }
                        Section {
                            row(.log)
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
                } detail: {
                    detail(page ?? .home)
                        .navigationTitle((page ?? .home).title)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func row(_ p: Page) -> some View {
        Label(p.title, systemImage: p.symbol).tag(p)
    }

    @ViewBuilder private func detail(_ p: Page) -> some View {
        let full = { setFullscreen(true) }
        switch p {
        case .home: HomeView(page: $page, onFullscreen: full)
        case .cursor: CursorView()
        case .signs: HandSignsView()
        case .features: FeaturesView()
        case .learn: LearnView(page: $page)
        case .playground: CameraStage { size in PlaygroundView(size: size, onFullscreen: full) }
        case .log: LogView()
        }
    }

    /// Fills the window with the camera and, unless the window already is, puts it in macOS fullscreen.
    private func setFullscreen(_ on: Bool) {
        if !snapshot, let w = NSApp.keyWindow {
            let native = w.styleMask.contains(.fullScreen)
            if on, !native { w.toggleFullScreen(nil); enteredNativeFullscreen = true }
            if !on, enteredNativeFullscreen, native { w.toggleFullScreen(nil) }
            if !on { enteredNativeFullscreen = false }
        }
        withAnimation(.easeInOut(duration: 0.2)) { fullscreen = on }
    }
}

private struct FullscreenCamera: View {
    let playground: Bool
    let close: () -> Void

    var body: some View {
        CameraStage { size in
            if playground { PlaygroundView(size: size, onFullscreen: nil) }
        }
        .overlay(alignment: .topLeading) { GestureBadge().padding(16) }
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Label("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .keyboardShortcut(.cancelAction) // Esc
            .controlSize(.large)
            .padding(16)
            .help("Exit full screen (Esc)")
        }
        .background(.black)
        .ignoresSafeArea()
    }
}

/// One line about what Wave is doing, shared by Home and the menu bar.
func waveStatus(_ t: HandTracker) -> String {
    guard t.running else { return "Off. The camera is not in use." }
    if t.authorized == false { return "Camera access is off. Allow it in System Settings." }
    if t.cursorActive { return "Cursor mode is on" }
    return t.handVisible ? "Seeing: \(t.gesture.title)" : "Looking for your hand…"
}

/// Menu-bar dropdown: compact, Control Center style. Everything else lives in the window.
struct MenuPanel: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable private var signs = HandSigns.shared

    var body: some View {
        let t = HandTracker.shared
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: t.running ? "hand.wave.fill" : "hand.wave")
                    .font(.system(size: 15)).frame(width: 20)
                Text("Wave").font(.headline)
                Spacer()
                Toggle("Wave", isOn: Binding(get: { t.running }, set: { $0 ? t.start() : t.stop() }))
                    .toggleStyle(.switch).labelsHidden()
            }
            .padding(.horizontal, 14).padding(.top, 12)
            Text(waveStatus(t))
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("Hand signs")
                Spacer()
                Toggle("Hand signs", isOn: $signs.enabled).toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            VStack(spacing: 0) {
                MenuRow("Open Wave…") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                MenuRow("Show Log") { NSWorkspace.shared.open(SessionLog.url) }
            }
            .padding(5)
            Divider()
            MenuRow("Quit Wave", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .padding(5)
        }
        .frame(width: 280)
    }
}

/// A full-width menu item with the native rounded hover highlight.
private struct MenuRow: View {
    let title: String, shortcut: String?, action: () -> Void
    @State private var hover = false

    init(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.shortcut = shortcut; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(hover ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary)) }
            }
            .foregroundStyle(hover ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

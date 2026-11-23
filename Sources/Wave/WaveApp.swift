import AppKit
import SwiftUI

@main
struct WaveMain {
    static func main() {
        // Must branch before anything touches the camera or NSApplication.
        if CommandLine.arguments.contains("--selftest") { SelfTest.run() }
        NSApplication.shared.setActivationPolicy(.regular)
        WaveApp.main()
    }
}

struct WaveApp: App {
    var body: some Scene {
        WindowGroup("Wave", id: "main") {
            TabView {
                LearnView().tabItem { Label("Learn", systemImage: "hand.raised") }
                PlaygroundView().tabItem { Label("Playground", systemImage: "cube") }
                ShortcutsView().tabItem { Label("Shortcuts", systemImage: "bolt") }
                FeaturesView().tabItem { Label("Features", systemImage: "switch.2") }
            }
            .frame(minWidth: 960, minHeight: 640)
            .onAppear { HandTracker.shared.start(); ShortcutEngine.shared.start(); FeatureHub.shared.start() }
        }
        MenuBarExtra("Wave", systemImage: "hand.wave") { MenuContent() }
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

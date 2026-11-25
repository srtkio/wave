import AppKit
import SwiftUI

/// `Wave --snapshot <dir>` renders the window's pages (light and dark), the menu-bar panel and the notch pill to PNGs,
/// over a neutral stand-in for the camera, without starting it.
/// Uses an offscreen window, not ImageRenderer: ImageRenderer leaves ScrollViews blank and AppKit controls as placeholders.
enum Snapshot {
    @MainActor static func run(to dir: String) -> Never {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let t = HandTracker.shared
        // Active app, so key windows draw switches and selections in the accent colour instead of inactive grey.
        // macOS only lets a process launched by LaunchServices activate, hence scripts/snapshot.sh.
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)

        // Read-only overrides: the argument domain is never written to disk.
        UserDefaults.standard.setVolatileDomain(["feature.face": true, "feature.media": true, "signs.enabled": true,
                                                 "learn.tried": "fist,open,pinch,point"], forName: UserDefaults.argumentDomain)
        t.running = true
        t.authorized = true
        let h = SelfTest.hand(.out, [true, true, true, true]) // an open palm, as the self-test builds it
        t.frame = HandFrame(hands: [h], faceLandmarks: fakeFace())
        t.gesture = .open
        t.fingers = 5
        t.handVisible = true

        let hub = FeatureHub.shared
        for f in [hub.face, hub.media] as [FeatureBase] { f.running = true; f.live = true; f.status = "Watching…" }
        hub.face.status = "Matched"
        hub.face.action = "Re-register"
        hub.face.lastDistance = 0.31
        hub.face.threshold = 0.52
        hub.face.matched = true
        ActivityFeed.shared.lines = fakeLog

        /// Renders any view in an offscreen window to a PNG.
        func render<V: View>(_ name: String, _ view: V, width: CGFloat, height: CGFloat, dark: Bool, scale: Int = 1, chrome: Bool = true) {
            let size = NSSize(width: width, height: height)
            let host = NSHostingController(rootView: view)
            host.sceneBridgingOptions = [.toolbars, .title] // so the sidebar toggle and page title show in the title bar
            let w = KeyWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: chrome ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless],
                              backing: .buffered, defer: false)
            w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            w.contentViewController = host
            w.setContentSize(size)
            w.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            w.makeKeyAndOrderFront(nil) // key, so switches and the sidebar selection draw in the accent colour
            RunLoop.main.run(until: Date().addingTimeInterval(0.8)) // let layout, tasks and animations settle
            let frameView = w.contentView?.superview ?? w.contentView!
            let rect = frameView.bounds
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width) * scale, pixelsHigh: Int(rect.height) * scale,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = rect.size
            frameView.cacheDisplay(in: rect, to: rep)
            let file = out.appending(path: "\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
            w.orderOut(nil)
            print(file.path)
        }

        func page(_ name: String, _ p: Page, width: CGFloat = 1280, height: CGFloat = 800, dark: Bool) {
            render(name, WaveRoot(page: p).environment(\.snapshot, true), width: width, height: height, dark: dark)
        }

        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            page("home-\(mode)", .home, dark: dark)
            page("cursor-\(mode)", .cursor, dark: dark)
            page("signs-\(mode)", .signs, dark: dark)
            page("features-\(mode)", .features, dark: dark)
            page("log-\(mode)", .log, dark: dark)
            render("menu-\(mode)", MenuPanel()
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: dark ? 0.12 : 0.85)),
                   width: 320, height: 250, dark: dark, scale: 2, chrome: false)
        }
        page("home-small", .home, width: 900, height: 600, dark: false)
        page("learn-light", .learn, dark: false)
        page("playground-dark", .playground, dark: true)

        /// The notch pill on a stand-in menu bar with a notch-shaped black area.
        func notch(_ name: String, _ setup: (NotchHUD) -> Void) {
            let hud = NotchHUD()
            hud.headless = true
            setup(hud)
            let n = CGSize(width: 190, height: 34)
            let strip = ZStack(alignment: .top) {
                Color(white: 0.85)
                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).fill(.black).frame(width: n.width, height: n.height)
                NotchPill(notch: n, hud: hud)
            }
            render(name, strip, width: 560, height: 56, dark: false, scale: 2, chrome: false)
        }
        notch("notch-flash") { $0.flash("\u{1F44D} Play / Pause", symbol: "play.fill", seconds: 99) }
        notch("notch-cursor") { $0.setSticky("Cursor", symbol: "cursorarrow.motionlines") }
        notch("notch-progress") { $0.setSticky("Cursor", symbol: "cursorarrow.motionlines"); $0.progress = 0.65 }
        exit(0)
    }

    /// A face outline, eyes, nose and mouth to the left of the hand, in the camera's normalised mirrored space.
    private static func fakeFace() -> [CGPoint] {
        let c = CGPoint(x: 0.27, y: 0.4), rx = 0.075, ry = 0.15
        func ring(_ n: Int, _ cx: Double, _ cy: Double, _ ax: Double, _ ay: Double, from a0: Double = 0, to a1: Double = 2 * .pi) -> [CGPoint] {
            (0..<n).map { i in
                let a = a0 + (a1 - a0) * Double(i) / Double(n - 1)
                return CGPoint(x: cx + ax * cos(a), y: cy + ay * sin(a))
            }
        }
        return ring(19, c.x, c.y + 0.02, rx, ry, from: 0.05 * .pi, to: 0.95 * .pi)           // jaw
            + ring(6, c.x - 0.03, c.y - 0.03, 0.014, 0.008) + ring(6, c.x + 0.03, c.y - 0.03, 0.014, 0.008) // eyes
            + ring(5, c.x - 0.03, c.y - 0.06, 0.02, 0.01, from: 1.1 * .pi, to: 1.9 * .pi)   // brows
            + ring(5, c.x + 0.03, c.y - 0.06, 0.02, 0.01, from: 1.1 * .pi, to: 1.9 * .pi)
            + (0..<4).map { CGPoint(x: c.x, y: c.y - 0.01 + Double($0) * 0.017) }          // nose
            + ring(10, c.x, c.y + 0.085, 0.028, 0.012)                                         // lips
    }

    private static let fakeLog: [String] = {
        var l = ["14:02:11.204 session start", "14:02:11.410 notch \"Wave on\""]
        let script = [
            "hands seen=2 kept=1 palms=[0.212,0.031] (min 0.08)", "gesture open fingers=5 palm=0.212",
            "gesture none fingers=4 palm=0.208", "sign 👍 thumbsUp", "notch \"👍 Play / Pause\"", "sign none",
            "gesture pinch fingers=3 palm=0.215", "cursor enter", "notch sticky \"Cursor\"", "notch \"Cursor on\"",
            "cursor leftClick(1)", "cursor leftClick(2)", "cursor rightClick", "cursor leftDown", "cursor leftUp",
            "cursor scrollMode(true)", "notch \"Scroll\"", "cursor scrollMode(false)", "cursor exit", "notch sticky off",
            "notch \"Cursor off\"", "gesture open fingers=5 palm=0.209", "sign 🤘 rock", "notch \"🤘 Next track\"", "sign none",
        ]
        for (i, s) in script.enumerated() { l.append(String(format: "14:02:%02d.%03d %@", 14 + i, (i * 137) % 1000, s)) }
        return l
    }()
}

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

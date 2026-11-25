import AppKit
import SwiftUI

/// `Wave --snapshot <dir>` renders every tab over a stand-in backdrop to PNGs, without starting the camera.
/// Uses an offscreen window, not ImageRenderer: ImageRenderer leaves ScrollViews blank and AppKit controls as placeholders.
enum Snapshot {
    @MainActor static func run(to dir: String) -> Never {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let t = HandTracker.shared
        ShortcutEngine.shared.items = [
            "Meet at the north entrance at 6:30, bring the projector cable and the spare HDMI adapter",
            "wave.app/beta",
            "Thanks, that works for me!",
        ]

        func hand(_ visible: Bool) {
            let h = SelfTest.hand(.out, [true, true, true, true]) // an open palm, as the self-test builds it
            t.frame = HandFrame(hands: visible ? [h] : [])
            t.gesture = visible ? .open : .none
            t.fingers = visible ? 5 : 0
            t.handVisible = visible
        }

        /// Renders any view in an offscreen window to a PNG (2x for the small shots).
        func render<V: View>(_ name: String, _ view: V, width: CGFloat, height: CGFloat, scale: Int = 1, wait: Double = 0.6, chrome: Bool = true) {
            let size = NSSize(width: width, height: height)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: size)
            // Same chrome as .hiddenTitleBar, so the traffic lights show up in the shot.
            let w = KeyWindow(contentRect: host.frame, styleMask: chrome ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless],
                              backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.contentView = host
            let frameView = host.superview ?? host
            w.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            if chrome { w.orderFrontRegardless() } else { w.makeKeyAndOrderFront(nil) } // key, so switches draw as active
            RunLoop.main.run(until: Date().addingTimeInterval(wait)) // let layout, tasks and animations settle
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            frameView.cacheDisplay(in: host.frame, to: rep)
            let file = out.appending(path: "\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
            w.orderOut(nil)
            print(file.path)
        }

        func shot(_ name: String, _ tab: Tab, width: CGFloat = 1280, height: CGFloat = 800, wait: Double = 0.6) {
            render(name, WaveRoot(tab: tab).environment(\.snapshot, true), width: width, height: height, wait: wait)
        }

        /// The notch pill on a stand-in menu bar with a notch-shaped black area.
        func notch(_ name: String, _ setup: (NotchHUD) -> Void) {
            let hud = NotchHUD()
            hud.headless = true
            setup(hud)
            let n = CGSize(width: 190, height: 34)
            let strip = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.3), Color(red: 0.3, green: 0.2, blue: 0.4)],
                               startPoint: .leading, endPoint: .trailing)
                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).fill(.black).frame(width: n.width, height: n.height)
                NotchPill(notch: n, hud: hud)
            }
            render(name, strip, width: 560, height: 56, scale: 2, chrome: false)
        }

        t.authorized = true
        hand(true)
        shot("1-learn", .learn)
        hand(false)
        shot("2-playground", .playground, wait: 3.2) // past the 2 s "Raise a hand" delay
        hand(true)
        shot("3-shortcuts", .shortcuts)
        shot("3b-shortcuts-full", .shortcuts, height: 1100) // tall enough to show the clipboard list
        shot("4-features", .features)
        shot("6-shortcuts-small", .shortcuts, width: 960, height: 640)
        hand(false)
        t.authorized = false
        shot("5-camera-denied", .learn)

        t.running = true
        t.authorized = true
        hand(true)
        t.gesture = .thumbsUp
        render("7-menu-panel", MenuPanel().background(Color(white: 0.13)).clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.22, green: 0.24, blue: 0.36)).ignoresSafeArea()
            .environment(\.colorScheme, .dark),
               width: 330, height: 520, scale: 2, chrome: false)
        notch("8-notch-flash") { $0.flash("\u{1F44D} Play / Pause", symbol: "play.fill", seconds: 99) }
        notch("9-notch-cursor") { $0.setSticky("Cursor", symbol: "cursorarrow.motionlines") }
        notch("10-notch-progress") { $0.setSticky("Cursor", symbol: "cursorarrow.motionlines"); $0.progress = 0.65 }
        exit(0)
    }
}

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

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

        func shot(_ name: String, _ tab: Tab, width: CGFloat = 1280, height: CGFloat = 800, wait: Double = 0.6) {
            let size = NSSize(width: width, height: height)
            let host = NSHostingView(rootView: WaveRoot(tab: tab).environment(\.snapshot, true))
            host.frame = NSRect(origin: .zero, size: size)
            // Same chrome as .hiddenTitleBar, so the traffic lights show up in the shot.
            let w = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.contentView = host
            let frameView = host.superview ?? host
            w.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            w.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(wait)) // let layout, tasks and animations settle
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            frameView.cacheDisplay(in: host.frame, to: rep)
            let file = out.appending(path: "\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
            w.orderOut(nil)
            print(file.path)
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
        exit(0)
    }
}

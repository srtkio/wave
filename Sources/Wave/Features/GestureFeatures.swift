import AppKit
import UserNotifications

/// Fist = play/pause. Pinch and slide up/down = volume.
final class MediaControls: FeatureBase {
    private var fist = Edge(), cooldown = Cooldown()
    private var anchor: CGFloat?

    init() {
        super.init(key: "feature.media", symbol: "play.circle", name: "Media controls",
                   blurb: "Fist plays or pauses. Pinch and slide up or down for volume.")
    }

    override func begin() {
        Output.ensureAccessibility()
        fist = Edge(); cooldown = Cooldown(); anchor = nil
        listen { [weak self] f, g in self?.tick(f, g) }
    }

    private func tick(_ f: HandFrame, _ g: Gesture) {
        if fist.rose(g == .fist), cooldown.fire(at: f.time, gap: 1) {
            Output.mediaKey(Output.NX_KEYTYPE_PLAY)
            flash("Play / pause ✓")
        }
        guard g == .pinch, let y = f.hands.first?.points[.indexTip]?.y else { anchor = nil; return }
        let a = anchor ?? y
        let n = volumeSteps(anchor: a, y: y)
        anchor = a - CGFloat(n) * 0.05
        guard n != 0 else { return }
        for _ in 0..<abs(n) { Output.mediaKey(n > 0 ? Output.NX_KEYTYPE_SOUND_UP : Output.NX_KEYTYPE_SOUND_DOWN) }
        flash(n > 0 ? "Volume up" : "Volume down")
    }
}

/// Finger on your lips for half a second toggles mute in Zoom or Google Meet.
final class MeetingMute: FeatureBase {
    private var dwell = Dwell(), cooldown = Cooldown()
    // shortcut: fixed browser list, add any Chromium/WebKit browser you use here.
    private static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.brave.Browser",
        "company.thebrowser.Browser", "com.microsoft.edgemac", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    init() {
        super.init(key: "feature.meeting", symbol: "mic.slash", name: "Meeting mute",
                   blurb: "Hold a finger to your lips to toggle mute in Zoom or Meet.")
        idle = "Waiting for your face…"
    }

    override func begin() {
        Output.ensureAccessibility()
        dwell = Dwell(); cooldown = Cooldown()
        listen { [weak self] f, _ in self?.tick(f) }
    }

    private func tick(_ f: HandFrame) {
        guard let face = f.face else { dwell = Dwell(); return }
        let zone = mouthZone(face)
        let near = f.hands.contains { $0.points[.indexTip].map(zone.contains) ?? false }
        guard dwell.held(near, at: f.time, for: 0.5), cooldown.fire(at: f.time, gap: 2) else { return }
        switch NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
        case "us.zoom.xos": Output.key(0, flags: [.maskCommand, .maskShift]) // ⌘⇧A
        case let id? where Self.browsers.contains(id): Output.key(2, flags: .maskCommand) // ⌘D (Meet)
        default: return flash("Open Zoom or Meet first")
        }
        flash("Mute toggled ✓")
    }
}

/// Hand resting on the face for 2s gets a gentle nudge, at most one a minute.
final class FaceTouch: FeatureBase {
    private var dwell = Dwell(), rate = Cooldown()

    init() {
        super.init(key: "feature.touch", symbol: "hand.raised.slash", name: "Face-touch alert",
                   blurb: "A gentle nudge when your hand lingers on your face.")
    }

    private var today: Int {
        let d = UserDefaults.standard
        return d.string(forKey: "touch.day") == Self.day ? d.integer(forKey: "touch.count") : 0
    }
    private static var day: String { Date.now.formatted(.iso8601.year().month().day()) }
    private func summary() { idle = "Watching… · \(today) today" }

    override func begin() {
        summary()
        // Notifications trap without an app bundle (plain `swift run`).
        guard Bundle.main.bundleIdentifier != nil else { idle = "Needs the app bundle (./build.sh)"; live = false; return }
        let center = UNUserNotificationCenter.current()
        center.delegate = Banner.shared
        center.requestAuthorization(options: [.alert]) { _, _ in }
        dwell = Dwell(); rate = Cooldown()
        listen { [weak self] f, _ in self?.tick(f) }
    }

    private func tick(_ f: HandFrame) {
        guard let face = f.face else { dwell = Dwell(); return }
        let inside = f.hands.reduce(0) { $0 + $1.points.values.filter(face.contains).count }
        guard dwell.held(inside >= 3, at: f.time, for: 2), rate.fire(at: f.time, gap: 60) else { return }
        let c = UNMutableNotificationContent()
        c.title = "Hands off your face 🙂"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        let d = UserDefaults.standard
        d.set(Self.day, forKey: "touch.day")
        d.set(today + 1, forKey: "touch.count")
        summary()
        flash("Nudged ✓")
    }
}

/// Lets the banner show even while Wave itself is frontmost (macOS hides it otherwise).
private final class Banner: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Banner()
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner])
    }
}

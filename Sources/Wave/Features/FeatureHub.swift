import AppKit
import SwiftUI

/// Base for every toggleable feature. State is observable so cards update live; subclasses only add behaviour.
@MainActor @Observable
class FeatureBase {
    let key: String, symbol: String, name: String, blurb: String
    var running = false
    var live = false          // green status dot
    var busy = false          // disables the card button
    var status = "Off"
    var banner: String?       // big text over the camera (countdowns)
    var action: String?       // label of the card's button, nil = none
    @ObservationIgnored var idle = "Watching…"
    @ObservationIgnored private var ids: [UUID] = []
    @ObservationIgnored private var flashes = 0

    init(key: String, symbol: String, name: String, blurb: String) {
        self.key = key; self.symbol = symbol; self.name = name; self.blurb = blurb
    }

    func begin() {}
    func end() {}
    func act() {}

    final func enable() { running = true; live = true; begin(); status = idle }
    final func disable() {
        ids.forEach(HandTracker.shared.removeListener); ids = []
        running = false; live = false; busy = false; banner = nil; action = nil
        end()
        status = "Off"
    }

    /// `always` = also while gestures are blocked (only the face check needs that).
    final func listen(always: Bool = false, _ f: @escaping (HandFrame, Gesture) -> Void) {
        let t = HandTracker.shared
        ids.append(always ? t.onAnyFrame(f) : t.onFrame(f))
    }

    /// Show a result briefly, then fall back to the idle line.
    final func flash(_ s: String) {
        status = s; flashes += 1
        let n = flashes
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if n == flashes, running { status = idle }
        }
    }
}

/// Owns every feature so they keep working on any tab. Toggles live in UserDefaults (the cards' @AppStorage).
@MainActor
final class FeatureHub {
    static let shared = FeatureHub()
    let face = FaceCheck(), media = MediaControls(), meeting = MeetingMute(), ink = AirInk(), touch = FaceTouch()
    var all: [FeatureBase] { [face, media, meeting, ink, touch] }
    private var started = false

    /// Safe to call more than once.
    func start() {
        guard !started else { return }
        started = true
        sync()
    }

    /// Reconcile running features with their saved toggles. Idempotent.
    func sync() {
        for f in all {
            let on = UserDefaults.standard.bool(forKey: f.key)
            if on != f.running { on ? f.enable() : f.disable() }
        }
        HandTracker.shared.detectFaces = [face, meeting, touch].contains { $0.running }
    }
}

// MARK: - Pure logic (no camera, no UI), covered by FeatureChecks

/// Fires at most once per `gap` seconds.
struct Cooldown {
    private var last = -Double.infinity
    mutating func fire(at t: Double, gap: Double) -> Bool {
        guard t - last >= gap else { return false }
        last = t
        return true
    }
}

/// True only on the frame a condition turns on.
struct Edge {
    private var was = false
    mutating func rose(_ now: Bool) -> Bool { defer { was = now }; return now && !was }
}

/// True once per continuous hold of `d` seconds; must be released before it can fire again.
struct Dwell {
    private var since: Double?
    private var fired = false
    mutating func held(_ on: Bool, at t: Double, for d: Double) -> Bool {
        guard on else { since = nil; fired = false; return false }
        let s = since ?? t
        since = s
        guard !fired, t - s >= d else { return false }
        fired = true
        return true
    }
}

/// Whole volume steps moved up (+) or down (-) since `anchor`, one per `step` of vertical travel.
/// y grows downward, so moving the hand up lowers y. Clamped so a tracking glitch can't blast the volume.
func volumeSteps(anchor: CGFloat, y: CGFloat, step: CGFloat = 0.05, maxSteps: Int = 4) -> Int {
    max(-maxSteps, min(maxSteps, Int(((anchor - y) / step).rounded(.towardZero))))
}

/// Lower third of the face rect: where the mouth is.
func mouthZone(_ face: CGRect) -> CGRect {
    CGRect(x: face.minX, y: face.minY + face.height * 2 / 3, width: face.width, height: face.height / 3)
}

/// Hands rarely reach the edges of the camera, so the middle 80% of the view spans the whole screen.
func inkMap(_ p: CGPoint) -> CGPoint {
    func m(_ v: CGFloat) -> CGFloat { min(1, max(0, (v - 0.1) / 0.8)) }
    return CGPoint(x: m(p.x), y: m(p.y))
}

enum FeatureChecks {
    /// Runs inside `swift run Wave --selftest`. Returns true when everything passes.
    static func run() -> Bool {
        var failed = 0
        func check(_ name: String, _ ok: Bool) {
            print(ok ? "PASS" : "FAIL", name)
            if !ok { failed += 1 }
        }

        var c = Cooldown()
        check("cooldown first fire", c.fire(at: 10, gap: 1))
        check("cooldown blocks inside gap", !c.fire(at: 10.5, gap: 1))
        check("cooldown reopens after gap", c.fire(at: 11, gap: 1))

        var e = Edge()
        check("edge rises once", e.rose(true) && !e.rose(true))
        check("edge needs release", !e.rose(false) && e.rose(true))

        var d = Dwell()
        check("dwell not yet", !d.held(true, at: 0, for: 0.5) && !d.held(true, at: 0.4, for: 0.5))
        check("dwell fires at 0.5s", d.held(true, at: 0.5, for: 0.5))
        check("dwell fires once per hold", !d.held(true, at: 3, for: 0.5))
        check("dwell rearms after release", !d.held(false, at: 4, for: 0.5) && !d.held(true, at: 5, for: 0.5) && d.held(true, at: 5.6, for: 0.5))

        check("volume: no move", volumeSteps(anchor: 0.5, y: 0.5) == 0)
        check("volume: under one step", volumeSteps(anchor: 0.5, y: 0.47) == 0)
        check("volume: up 2 steps", volumeSteps(anchor: 0.5, y: 0.39) == 2)
        check("volume: down 1 step", volumeSteps(anchor: 0.5, y: 0.56) == -1)
        check("volume: clamped", volumeSteps(anchor: 0.9, y: 0.1) == 4)

        let face = CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.3)
        check("mouth zone inside", mouthZone(face).contains(CGPoint(x: 0.5, y: 0.55)))
        check("mouth zone excludes eyes", !mouthZone(face).contains(CGPoint(x: 0.5, y: 0.35)))
        check("mouth zone excludes outside", !mouthZone(face).contains(CGPoint(x: 0.7, y: 0.55)))
        check("face contains point", face.contains(CGPoint(x: 0.5, y: 0.45)) && !face.contains(CGPoint(x: 0.1, y: 0.1)))

        check("ink map centre", inkMap(CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 0.5, y: 0.5))
        check("ink map clamps", inkMap(CGPoint(x: 0, y: 1)) == CGPoint(x: 0, y: 1))
        check("face threshold floor", FacePrint.threshold(intraMax: 0) == FacePrint.floor)
        check("face threshold scales", FacePrint.threshold(intraMax: 10) == 15)

        print(failed == 0 ? "ALL PASS" : "\(failed) FAILED")
        return failed == 0
    }
}

import AppKit
import Foundation
import Observation

/// What a sign does. Stored in UserDefaults as `stored` ("copy", "shortcut:My Shortcut", ...).
enum SignAction: Hashable {
    case none, copy, paste, playPause, volumeUp, volumeDown, nextTrack, previousTrack, missionControl, screenshot
    case shortcut(String)

    static let basic: [SignAction] = [.none, .copy, .paste, .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown,
                                      .missionControl, .screenshot]

    var title: String {
        switch self {
        case .none: "Nothing"
        case .copy: "Copy"
        case .paste: "Paste"
        case .playPause: "Play / Pause"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .missionControl: "Mission Control"
        case .screenshot: "Screenshot"
        case .shortcut(let name): name
        }
    }

    var stored: String {
        if case .shortcut(let n) = self { return "shortcut:" + n }
        return "\(self)"
    }

    init(stored s: String) {
        if s.hasPrefix("shortcut:") { self = .shortcut(String(s.dropFirst(9))) }
        else { self = Self.basic.first { $0.stored == s } ?? .none }
    }

    func run() {
        switch self {
        case .none: break
        case .shortcut(let name): Output.runShortcut(name)
        case .playPause: Output.mediaKey(Output.NX_KEYTYPE_PLAY)
        case .volumeUp: Output.mediaKey(Output.NX_KEYTYPE_SOUND_UP)
        case .volumeDown: Output.mediaKey(Output.NX_KEYTYPE_SOUND_DOWN)
        case .nextTrack: Output.mediaKey(Output.NX_KEYTYPE_NEXT)
        case .previousTrack: Output.mediaKey(Output.NX_KEYTYPE_PREVIOUS)
        case .copy: Output.copy()
        case .paste: Output.paste()
        // Opening the app works regardless of the user's Ctrl+Up setting and needs no Accessibility.
        case .missionControl: NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        case .screenshot: Output.key(21, flags: [.maskCommand, .maskShift])   // Cmd+Shift+4
        }
    }
}

extension Sign {
    var defaultAction: SignAction {
        switch self {
        case .thumbsUp: .playPause
        case .rock: .nextTrack
        case .callMe: .missionControl
        case .peace: .screenshot
        case .ok: .copy
        case .l: .paste
        }
    }
}

/// Hold timer, pure so it can be tested without a camera. Feed it one sign (or nil) per frame.
struct Hold {
    // shortcut: 0.8 s hold, 0.5 s re-arm, 0.15 s dropout grace are guesses; tune on hardware.
    static let hold = 0.8, rearm = 0.5, grace = 0.15

    private(set) var sign: Sign?
    private var since = 0.0, lastSeen = 0.0, done = false

    /// `fire` is set on the one frame the hold completes; `progress` is 0..<1 while a hold is filling.
    mutating func step(t: Double, sign s: Sign?, off: Bool = false) -> (fire: Sign?, progress: Double?) {
        if off { self = Hold(); return (nil, nil) }
        // Gone long enough: forget the sign. After a fire this is the cooldown (the hand must leave first).
        if sign != nil, t - lastSeen >= (done ? Self.rearm : Self.grace) - 1e-9 { self = Hold() }
        guard let s else { return (nil, sign == nil || done ? nil : (t - since) / Self.hold) }
        // A different sign restarts the clock and re-arms, so a sign passed through on the way never fires.
        if s != sign { sign = s; since = t; done = false }
        lastSeen = t
        if done { return (nil, nil) }
        if t - since >= Self.hold - 1e-9 { done = true; return (s, nil) }
        return (nil, (t - since) / Self.hold)
    }
}

@Observable
final class HandSigns {
    static let shared = HandSigns()

    /// The sign the hand is making right now (for the menu highlight).
    private(set) var held: Sign?
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "signs.enabled") }
    }
    var actions: [Sign: SignAction] {
        didSet { for (s, a) in actions { UserDefaults.standard.set(a.stored, forKey: "sign.\(s.rawValue)") } }
    }

    @ObservationIgnored private var hold = Hold()
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private var ringShown = false
    @ObservationIgnored private var askedAccessibility = false

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "signs.enabled") as? Bool ?? true
        actions = Dictionary(uniqueKeysWithValues: Sign.allCases.map { s in
            (s, d.string(forKey: "sign.\(s.rawValue)").map(SignAction.init(stored:)) ?? s.defaultAction)
        })
    }

    func start() {
        guard listener == nil else { return }
        listener = HandTracker.shared.onFrame { [weak self] f, _ in self?.handle(f) }
    }

    private func handle(_ f: HandFrame) {
        // Cursor mode owns the hand (its peace sign is scroll); the master switch also lands here.
        let off = !enabled || HandTracker.shared.cursorActive
        let s = off ? nil : f.hands.first.flatMap(sign)
        if held != s {
            held = s
            SessionLog.log("sign \(s.map { "\($0.emoji) \($0.rawValue)" } ?? "none")")
        }
        let r = hold.step(t: f.time, sign: s, off: off)
        if let fired = r.fire {
            let a = actions[fired] ?? SignAction.none
            setRing(nil)
            guard a != .none else { return }
            if !askedAccessibility { askedAccessibility = true; Output.ensureAccessibility() }
            a.run()
            NotchHUD.shared.flash("\(fired.emoji) \(a.title)")
        } else if let cur = hold.sign, (actions[cur] ?? SignAction.none) != .none {
            setRing(r.progress)
        } else {
            setRing(nil)
        }
    }

    // Only touch the HUD ring when we own it, so we never clear another feature's progress.
    private func setRing(_ p: Double?) {
        if let p { NotchHUD.shared.progress = p; ringShown = true }
        else if ringShown { NotchHUD.shared.progress = nil; ringShown = false }
    }
}

// MARK: - Self check

extension HandSigns {
    /// Same wrist/palm layout as SelfTest.hand (wrist (0.5,0.8), palm 0.2); `fingers` = [index, middle, ring, little].
    private static func hand(thumb: CGPoint, _ fingers: [Bool]) -> Hand {
        var p: [Joint: CGPoint] = [
            .wrist: CGPoint(x: 0.5, y: 0.8), .thumbCMC: CGPoint(x: 0.42, y: 0.75),
            .thumbMP: CGPoint(x: 0.38, y: 0.7), .thumbIP: CGPoint(x: 0.35, y: 0.66), .thumbTip: thumb,
        ]
        let chains: [(CGFloat, Joint, Joint, Joint, Joint)] = [
            (0.44, .indexMCP, .indexPIP, .indexDIP, .indexTip), (0.50, .middleMCP, .middlePIP, .middleDIP, .middleTip),
            (0.56, .ringMCP, .ringPIP, .ringDIP, .ringTip), (0.62, .littleMCP, .littlePIP, .littleDIP, .littleTip),
        ]
        for (i, c) in chains.enumerated() {
            let up = fingers[i]
            p[c.1] = CGPoint(x: c.0, y: 0.6)
            p[c.2] = CGPoint(x: c.0, y: up ? 0.5 : 0.52)
            p[c.3] = CGPoint(x: c.0, y: up ? 0.45 : 0.6)
            p[c.4] = CGPoint(x: c.0, y: up ? 0.4 : 0.66) // curled tip folds back toward the wrist
        }
        return Hand(points: p, chirality: .right)
    }

    private static let tucked = CGPoint(x: 0.5, y: 0.56), out = CGPoint(x: 0.3, y: 0.62), up = CGPoint(x: 0.4, y: 0.4)
    private static let onIndexTip = CGPoint(x: 0.45, y: 0.41) // index tip is (0.44, 0.4) when the finger is up

    static func okHand() -> Hand { hand(thumb: onIndexTip, [true, true, true, true]) }

    /// Returns false (and prints which check) on failure.
    static func selfCheck() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { if !c { print("FAIL hand signs:", name); ok = false } }

        // Detection.
        let cases: [(Sign, Hand)] = [
            (.rock, hand(thumb: tucked, [true, false, false, true])),
            (.rock, hand(thumb: out, [true, false, false, true])),
            (.callMe, hand(thumb: out, [false, false, false, true])),
            (.ok, okHand()),
            (.l, hand(thumb: out, [true, false, false, false])),
            (.thumbsUp, hand(thumb: up, [false, false, false, false])),
            (.peace, hand(thumb: tucked, [true, true, false, false])),
        ]
        for (want, h) in cases { check("sign \(want)", sign(h) == want) }
        check("all six signs covered", Set(cases.map { $0.0 }) == Set(Sign.allCases))
        check("plain pinch is no sign", sign(hand(thumb: onIndexTip, [true, false, false, false])) == nil)
        check("open palm is no sign", sign(hand(thumb: out, [true, true, true, true])) == nil)
        check("fist is no sign", sign(hand(thumb: tucked, [false, false, false, false])) == nil)
        check("point is no sign", sign(hand(thumb: tucked, [true, false, false, false])) == nil)
        check("thumb sideways on a fist is no thumbs up", sign(hand(thumb: out, [false, false, false, false])) == nil)
        check("thumb parallel to index is no L", sign(hand(thumb: CGPoint(x: 0.36, y: 0.4), [true, false, false, false])) == nil)
        var missing = hand(thumb: tucked, [true, true, false, false])
        missing.points[.ringPIP] = nil
        check("missing joint is no sign", sign(missing) == nil)

        // Hold timing. Frames every 0.1 s (a real camera gives ~0.033 s); `feed` returns the signs fired.
        func feed(_ h: inout Hold, _ from: Double, _ to: Double, _ s: Sign?, off: Bool = false) -> [Sign] {
            stride(from: from, through: to + 1e-9, by: 0.1).compactMap { h.step(t: $0, sign: s, off: off).fire }
        }
        var h = Hold()
        check("no fire before 0.8", feed(&h, 0, 0.7, .peace).isEmpty)
        check("fire at 0.8", feed(&h, 0.8, 0.8, .peace) == [.peace])
        check("no repeat while held", feed(&h, 0.9, 5, .peace).isEmpty)
        check("nothing during cooldown", feed(&h, 5.1, 5.3, nil).isEmpty)
        check("re-pose within 0.5s does not re-arm", feed(&h, 5.4, 8, .peace).isEmpty)
        check("fire again after release + 0.5s", feed(&h, 8.1, 8.6, nil).isEmpty && feed(&h, 8.7, 9.5, .peace) == [.peace])
        check("progress fills", { var g = Hold(); _ = feed(&g, 0, 0.3, .ok); return g.step(t: 0.4, sign: .ok).progress == 0.5 }())

        var g = Hold()
        _ = feed(&g, 0, 0, .rock); _ = g.step(t: 0.05, sign: nil)
        check("brief dropout keeps the hold", feed(&g, 0.1, 0.7, .rock).isEmpty && feed(&g, 0.8, 0.8, .rock) == [.rock])
        g = Hold()
        _ = feed(&g, 0, 0, .rock); _ = g.step(t: 0.2, sign: nil)
        check("long dropout restarts the hold", feed(&g, 0.3, 1.0, .rock).isEmpty && feed(&g, 1.1, 1.1, .rock) == [.rock])
        g = Hold()
        _ = feed(&g, 0, 0.7, .rock)
        check("switching sign restarts the hold", feed(&g, 0.8, 1.4, .peace).isEmpty && feed(&g, 1.5, 1.6, .peace) == [.peace])
        g = Hold()
        check("nothing while cursor mode is on", feed(&g, 0, 3, .peace, off: true).isEmpty)

        // Storage round trip and defaults.
        check("action storage", (SignAction.basic + [.shortcut("A b")]).allSatisfy { SignAction(stored: $0.stored) == $0 })
        check("defaults", Sign.thumbsUp.defaultAction == .playPause && Sign.l.defaultAction == .paste && Sign.ok.defaultAction == .copy)
        return ok
    }

    /// Plain pinch and OK both have the thumb on the index tip. classify() checks pinch first, so today this is false;
    /// it turns true once classify() only returns .pinch when middle/ring/little are not all extended.
    static func okIsNotPinch() -> Bool { classify(okHand()) != .pinch }
}

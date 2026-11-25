import CoreGraphics
import Foundation

/// What cursor mode wants done. `move` points are normalised 0–1 over the main screen, origin top-left.
enum CursorEvent: Equatable {
    case move(CGPoint)
    case leftDown, leftUp
    case leftClick(Int) // 2 = second click of a double click
    case rightClick
    case scroll(dx: Double, dy: Double) // whole pixels in the direction of travel: +dx right, +dy down
    case scrollMode(Bool)
    case enter, exit
    case progress(Double?)
}

/// Cursor mode as a pure state machine: hands + time in, events out. No side effects, so `selfCheck` can drive it.
struct CursorCore {
    // Pinch distances are thumb tip to fingertip divided by palm size (wrist to middle MCP).
    // shortcut: 0.25 close / 0.40 open hysteresis guessed from Vision jitter, tune on hardware if taps miss or misfire.
    static let closeAt: CGFloat = 0.25, openAt: CGFloat = 0.40
    static let armHold = 0.6
    // shortcut: knuckle may drift 4% of the frame while arming, raise if arming keeps restarting.
    static let armSteady: CGFloat = 0.04
    static let tapMin = 0.05, tapMax = 0.3 // shorter than tapMin is a one-frame flicker, not a tap
    static let doubleGap = 0.4
    static let doubleSlop: CGFloat = 0.02 // a double click must land on (nearly) the same spot
    // shortcut: 0.1s rewind on pinch close undoes the nudge of closing fingers, tune if clicks land early/late.
    static let freezeLookback = 0.1
    static let exitHold = 2.0
    static let pauseAfter = 1.5, quitAfter = 20.0
    // shortcut: central 60% of the camera maps to the screen, widen or shift if edges are hard to reach.
    // Trackpad-style pointer: hand *motion* in palm-widths moves the cursor, with acceleration, so small moves go far
    // and distance from the camera doesn't matter. Gain is screen-widths per palm-width at a given hand speed.
    // shortcut: slow ≈ ⅓ screen per palm (~6 px per mm), a quick flick up to 2 screens per palm; tune on hardware (Speed slider scales it).
    static let gainSlow: CGFloat = 0.35, gainPerSpeed: CGFloat = 0.5, gainMax: CGFloat = 2.0
    static let stillSpeed: CGFloat = 0.06 // palm-widths/s; slower than this is tracking noise, not intent
    static let minMove: CGFloat = 0.0005 // ~1px; a still hand must not fight a real trackpad
    static let scrollIn = 0.15, scrollOut = 0.25
    // shortcut: dead zone 0.3 palm, then 2500·excess^1.5 px/s capped at 4000, tune by feel.
    static let scrollDead: CGFloat = 0.3, scrollGain: CGFloat = 2500, scrollMax: CGFloat = 4000

    private enum Finger { case index, middle }

    private(set) var active = false
    private var waitRelease = false // a pinch already closed (arming, exit, resume) must open before it does anything
    private var armStart: (t: TimeInterval, at: CGPoint)?
    private var exitStart: TimeInterval?
    private var lostSince: TimeInterval?
    private var paused = false
    private var pinch: (finger: Finger, t: TimeInterval)?
    private var dragging = false
    private var lastClick: (t: TimeInterval, at: CGPoint, count: Int)?
    private var filter = OneEuro()
    private var cursor: CGPoint?
    private var history: [(t: TimeInterval, p: CGPoint)] = []
    private var peaceSince: TimeInterval?, notPeaceSince: TimeInterval?
    private var scrollOrigin: CGPoint?
    private var scrollCarry = CGPoint.zero
    private var lastT: TimeInterval?
    private var lastKnuckle: CGPoint? // filtered, square units
    /// Speed multiplier from the Cursor page (1 = default).
    var sensitivity: CGFloat = 1
    /// Screen width ÷ height, so a hand move is the same distance in pixels horizontally and vertically.
    var aspect: CGFloat = 1.6

    /// Starts the cursor where the real pointer is (normalised screen coordinates).
    mutating func place(_ p: CGPoint) { cursor = p }

    /// The pose that starts arming: a close thumb+index pinch that is not the OK sign. Arbiter uses it to hand the hand to cursor mode.
    static func armPose(_ h: Hand) -> Bool {
        Geo(h).map { !$0.threeUp && $0.index < closeAt } ?? false
    }

    mutating func step(t: TimeInterval, hands: [Hand]) -> [CursorEvent] {
        defer { lastT = t }
        return active ? stepActive(t, hands) : stepIdle(t, hands)
    }

    // MARK: idle: only arming can happen

    private mutating func stepIdle(_ t: TimeInterval, _ hands: [Hand]) -> [CursorEvent] {
        guard let g = hands.first.flatMap(Geo.init) else { return cancelArm() }
        // Two pinching hands is the exit pose, never an arm.
        if hands.count > 1, let g2 = Geo(hands[1]), g2.index < Self.openAt { return cancelArm() }
        if waitRelease { waitRelease = g.index <= Self.openAt; return cancelArm() }
        // 👌 (thumb on index, other three fingers up) is a hand sign, not an arm. Only arming is gated: once active, taps are distance-only.
        guard !g.threeUp, g.index < (armStart == nil ? Self.closeAt : Self.openAt) else { return cancelArm() }
        if let s = armStart, hypot(g.knuckle.x - s.at.x, g.knuckle.y - s.at.y) <= Self.armSteady {
            let p = (t - s.t) / Self.armHold
            guard p >= 1 else { return [.progress(p)] }
            self = CursorCore()
            active = true
            waitRelease = true
            return [.progress(nil), .enter]
        }
        armStart = (t, g.knuckle)
        return [.progress(0)]
    }

    private mutating func cancelArm() -> [CursorEvent] {
        defer { armStart = nil }
        return armStart == nil ? [] : [.progress(nil)]
    }

    // MARK: active

    private mutating func stepActive(_ t: TimeInterval, _ hands: [Hand]) -> [CursorEvent] {
        // Missing key joints count as lost: a pinch often hides the thumb tip, and a drag must still release.
        guard let h = hands.first, let g = Geo(h) else {
            let since = lostSince ?? t
            lostSince = since
            // The hand may come back somewhere else: start motion fresh so the cursor doesn't jump.
            filter = OneEuro(); lastKnuckle = nil
            if t - since > Self.quitAfter { return exit() }
            guard t - since > Self.pauseAfter, !paused else { return [] }
            paused = true
            return letGo() + clearExit()
        }
        lostSince = nil
        if paused { paused = false; waitRelease = true }
        var out: [CursorEvent] = []

        // Exit: both hands pinching, side by side and roughly level, held for exitHold.
        if hands.count > 1, let g2 = Geo(hands[1]), g.index < Self.openAt, g2.index < Self.openAt {
            out += letGo()
            waitRelease = true
            // shortcut: "level" = >10% of the frame apart sideways and <15% apart vertically, tune on hardware.
            guard abs(g2.pinchPoint.x - g.pinchPoint.x) > 0.1, abs(g2.pinchPoint.y - g.pinchPoint.y) < 0.15 else {
                return out + clearExit()
            }
            let s = exitStart ?? t
            exitStart = s
            let p = (t - s) / Self.exitHold
            return out + (p >= 1 ? exit() : [.progress(p)])
        }
        out += clearExit()
        if waitRelease, g.index > Self.openAt, g.middle > Self.openAt { waitRelease = false }

        // Scroll: peace held briefly; speed comes from the knuckle's offset since scroll began.
        let peace = classify(h) == .peace
        if peace { peaceSince = peaceSince ?? t; notPeaceSince = nil } else { peaceSince = nil }
        if scrollOrigin == nil, pinch == nil, !waitRelease, let s = peaceSince, t - s >= Self.scrollIn {
            scrollOrigin = g.knuckle
            scrollCarry = .zero
            out.append(.scrollMode(true))
        }
        if let o = scrollOrigin {
            if peace { return out + scroll(from: o, g, dt: min(0.1, t - (lastT ?? t))) }
            let s = notPeaceSince ?? t
            notPeaceSince = s
            guard t - s >= Self.scrollOut else { return out } // pose flicker mid-scroll: hold still
            scrollOrigin = nil
            notPeaceSince = nil
            filter = OneEuro(); lastKnuckle = nil
            out.append(.scrollMode(false))
        }

        // Clicks and drag.
        if !waitRelease {
            if let p = pinch {
                let held = t - p.t
                let tap = held >= Self.tapMin && held <= Self.tapMax
                let opened = (p.finger == .index ? g.index : g.middle) > Self.openAt
                switch (p.finger, opened) {
                case (.index, true):
                    if dragging { out.append(.leftUp) } else if tap { out.append(click(t)) }
                    pinch = nil
                    dragging = false
                case (.index, false):
                    if !dragging, held > Self.tapMax { dragging = true; out.append(.leftDown) }
                case (.middle, true):
                    if tap { out.append(.rightClick) }
                    pinch = nil
                case (.middle, false): break
                }
            } else if !peace, g.index < Self.closeAt, g.index <= g.middle {
                pinch = (.index, t)
                out += freeze(t)
            } else if !peace, g.middle < Self.closeAt, g.index > Self.openAt {
                pinch = (.middle, t)
                out += freeze(t)
            }
        }

        // Move: anchored on the index knuckle, which barely moves when the fingertips pinch.
        guard !peace else { lastKnuckle = nil; return out }
        let k = filter(CGPoint(x: g.knuckle.x * 16 / 9, y: g.knuckle.y), t) // square units: the frame is 16:9
        defer { lastKnuckle = k }
        guard let prev = lastKnuckle, let t0 = lastT, t > t0 else { return out }
        let d = CGPoint(x: (k.x - prev.x) / g.palm, y: (k.y - prev.y) / g.palm) // palm-widths
        let speed = hypot(d.x, d.y) / CGFloat(t - t0)
        guard speed > Self.stillSpeed else { return out }
        let gain = min(Self.gainMax, Self.gainSlow + Self.gainPerSpeed * speed) * sensitivity
        let c = cursor ?? CGPoint(x: 0.5, y: 0.5)
        let p = CGPoint(x: min(1, max(0, c.x + d.x * gain)), y: min(1, max(0, c.y + d.y * gain * aspect)))
        history.append((t, p))
        history.removeAll { $0.t < t - 0.3 }
        if pinch == nil || dragging { out += emit(p) } // a closing pinch must not drag the aim away
        return out
    }

    private mutating func emit(_ p: CGPoint) -> [CursorEvent] {
        if let c = cursor, hypot(p.x - c.x, p.y - c.y) < Self.minMove { return [] }
        cursor = p
        return [.move(p)]
    }

    /// Pins the cursor to where it was just before the fingers began closing, so the click lands where you aimed.
    private mutating func freeze(_ t: TimeInterval) -> [CursorEvent] {
        guard let p = (history.last { $0.t <= t - Self.freezeLookback } ?? history.first)?.p else { return [] }
        return emit(p)
    }

    private mutating func click(_ t: TimeInterval) -> CursorEvent {
        let at = cursor ?? .zero
        var n = 1
        if let c = lastClick, c.count == 1, t - c.t <= Self.doubleGap,
           hypot(at.x - c.at.x, at.y - c.at.y) <= Self.doubleSlop { n = 2 }
        lastClick = (t, at, n)
        return .leftClick(n)
    }

    private mutating func scroll(from o: CGPoint, _ g: Geo, dt: TimeInterval) -> [CursorEvent] {
        func speed(_ d: CGFloat) -> CGFloat {
            let e = abs(d) / g.palm - Self.scrollDead
            return e <= 0 ? 0 : (d < 0 ? -1 : 1) * min(Self.scrollMax, Self.scrollGain * pow(e, 1.5))
        }
        // Carry sub-pixel remainders so slow scrolls still move.
        scrollCarry.x += speed(g.knuckle.x - o.x) * CGFloat(dt)
        scrollCarry.y += speed(g.knuckle.y - o.y) * CGFloat(dt)
        let dx = scrollCarry.x.rounded(.towardZero), dy = scrollCarry.y.rounded(.towardZero)
        scrollCarry.x -= dx
        scrollCarry.y -= dy
        return dx == 0 && dy == 0 ? [] : [.scroll(dx: Double(dx), dy: Double(dy))]
    }

    /// Releases anything held: no stuck drag, no half-finished tap, no scroll.
    private mutating func letGo() -> [CursorEvent] {
        var out: [CursorEvent] = dragging ? [.leftUp] : []
        if scrollOrigin != nil { out.append(.scrollMode(false)) }
        dragging = false
        pinch = nil
        scrollOrigin = nil
        peaceSince = nil
        notPeaceSince = nil
        filter = OneEuro(); lastKnuckle = nil
        return out
    }

    private mutating func clearExit() -> [CursorEvent] {
        defer { exitStart = nil }
        return exitStart == nil ? [] : [.progress(nil)]
    }

    private mutating func exit() -> [CursorEvent] {
        let out = letGo() + clearExit()
        self = CursorCore()
        waitRelease = true // the exit pinches are still closed; don't let them re-arm
        return out + [.exit]
    }

    // MARK: helpers

    private struct Geo {
        let palm: CGFloat, index: CGFloat, middle: CGFloat // index/middle = thumb-tip distance ÷ palm
        let threeUp: Bool // middle, ring and little all extended: what separates 👌 from a pinch (same rule as classify)
        let knuckle: CGPoint, pinchPoint: CGPoint

        init?(_ h: Hand) {
            let p = h.points
            guard let w = p[.wrist], let m = p[.middleMCP], let k = p[.indexMCP], let th = p[.thumbTip],
                  let it = p[.indexTip], let mt = p[.middleTip] else { return nil }
            let palm = hypot(w.x - m.x, w.y - m.y)
            guard palm > 0 else { return nil }
            self.palm = palm
            let e = extendedFingers(h)
            threeUp = e[2] && e[3] && e[4]
            index = hypot(th.x - it.x, th.y - it.y) / palm
            middle = hypot(th.x - mt.x, th.y - mt.y) / palm
            knuckle = k
            pinchPoint = CGPoint(x: (th.x + it.x) / 2, y: (th.y + it.y) / 2)
        }
    }

    /// One Euro filter (Casiez et al. 2012): heavy smoothing at rest, little lag when moving fast.
    private struct OneEuro {
        // shortcut: beta 15 per screen-width/s ≈ 0.01 per px on a 1500px screen, tune on hardware.
        static let minCutoff = 0.6, beta = 15.0, dCutoff = 1.0 // lower minCutoff = steadier at rest
        private var x: CGPoint?, dx = CGPoint.zero, t: TimeInterval = 0

        mutating func callAsFunction(_ p: CGPoint, _ now: TimeInterval) -> CGPoint {
            guard let prev = x else { x = p; t = now; return p }
            let dt = now - t
            guard dt > 0 else { return prev }
            t = now
            func alpha(_ cutoff: Double) -> CGFloat { let r = 2 * .pi * cutoff * dt; return CGFloat(r / (r + 1)) }
            let ad = alpha(Self.dCutoff)
            dx.x += ad * ((p.x - prev.x) / CGFloat(dt) - dx.x)
            dx.y += ad * ((p.y - prev.y) / CGFloat(dt) - dx.y)
            let a = alpha(Self.minCutoff + Self.beta * Double(hypot(dx.x, dx.y)))
            let out = CGPoint(x: prev.x + a * (p.x - prev.x), y: prev.y + a * (p.y - prev.y))
            x = out
            return out
        }
    }

    // MARK: self-check

    private enum Pose { case open, pinch, ok, middle, peace }

    /// Same geometry as SelfTest.hand: wrist (0.5, 0.8), middle MCP (0.5, 0.6), palm 0.2; shifted by dx/dy.
    private static func testHand(_ pose: Pose, dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1) -> Hand {
        // .pinch curls the other three fingers (so it is not 👌); .ok keeps them up.
        let up = switch pose {
        case .peace: [true, true, false, false]
        case .pinch: [true, false, false, false]
        default: [true, true, true, true]
        }
        var p: [Joint: CGPoint] = [
            .wrist: CGPoint(x: 0.5, y: 0.8),
            .thumbTip: pose == .peace ? CGPoint(x: 0.5, y: 0.56) : CGPoint(x: 0.3, y: 0.62),
        ]
        let chains: [(x: CGFloat, mcp: Joint, pip: Joint, tip: Joint)] = [
            (0.44, .indexMCP, .indexPIP, .indexTip), (0.50, .middleMCP, .middlePIP, .middleTip),
            (0.56, .ringMCP, .ringPIP, .ringTip), (0.62, .littleMCP, .littlePIP, .littleTip),
        ]
        for (i, c) in chains.enumerated() {
            p[c.mcp] = CGPoint(x: c.x, y: 0.6)
            p[c.pip] = CGPoint(x: c.x, y: up[i] ? 0.5 : 0.52)
            p[c.tip] = CGPoint(x: c.x, y: up[i] ? 0.4 : 0.66)
        }
        if pose == .pinch || pose == .ok { p[.indexTip] = CGPoint(x: 0.31, y: 0.61) }
        if pose == .middle { p[.middleTip] = CGPoint(x: 0.31, y: 0.61) }
        // scale < 1 = a hand further from the camera (shrunk around the wrist).
        return Hand(points: p.mapValues { CGPoint(x: 0.5 + ($0.x - 0.5) * scale + dx, y: 0.8 + ($0.y - 0.8) * scale + dy) },
                    chirality: .right)
    }

    /// Drives `step` with synthetic hands at 30 fps of fake time. Prints each failure.
    static func selfCheck() -> Bool {
        var c = CursorCore(), t = 0.0, ok = true
        func feed(_ hands: [Hand], _ secs: Double) -> [CursorEvent] {
            var out: [CursorEvent] = []
            for _ in 0..<Int((secs * 30).rounded()) { t += 1.0 / 30; out += c.step(t: t, hands: hands) }
            return out
        }
        func check(_ name: String, _ pass: Bool) { if !pass { print("FAIL cursor:", name); ok = false } }
        // Everything but progress and moves: the events a misfire would show up in.
        func acts(_ e: [CursorEvent]) -> [CursorEvent] {
            e.filter { if case .progress = $0 { return false }; if case .move = $0 { return false }; return true }
        }
        let open = testHand(.open), pinch = testHand(.pinch), mid = testHand(.middle), peace = testHand(.peace)
        let pinchL = testHand(.pinch, dx: -0.25), pinchR = testHand(.pinch, dx: 0.25)
        let openL = testHand(.open, dx: -0.25), openR = testHand(.open, dx: 0.25)
        var nearMid = pinch // index pinch with the middle tip also near the thumb
        nearMid.points[.middleTip] = CGPoint(x: 0.36, y: 0.58)

        var e = feed([open], 0.3) + feed([pinch], 0.2) + feed([open], 0.2) + feed([mid], 0.1) + feed([open], 0.2)
            + feed([peace], 0.6) + feed([pinch], 0.5) + feed([], 0.5) + feed([pinchL, pinchR], 1.0) + feed([open], 0.2)
        check("nothing before arming", acts(e).isEmpty && !e.contains { if case .move = $0 { return true }; return false } && !c.active)

        check("ok pose never arms", !feed([testHand(.ok)], 1.5).contains(.enter) && !c.active)
        _ = feed([open], 0.2)
        check("arbiter sees pinch, not ok", armPose(pinch) && !armPose(testHand(.ok)) && !armPose(open))

        e = feed([pinch], 0.5)
        check("not armed at 0.5s", !e.contains(.enter) && e.contains(.progress(0)))
        e = feed([pinch], 0.2)
        check("armed by 0.7s", e.contains(.enter) && c.active)
        e = feed([pinch], 0.5) + feed([open], 0.3)
        check("arming pinch release does nothing", acts(e).isEmpty)

        check("tap = one click", acts(feed([pinch], 0.1) + feed([open], 0.5)) == [.leftClick(1)])
        e = feed([pinch], 0.1) + feed([open], 0.1) + feed([pinch], 0.1) + feed([open], 0.5)
        check("two quick taps = click then double click", acts(e) == [.leftClick(1), .leftClick(2)])
        check("one-frame flicker = nothing", acts(feed([pinch], 1.0 / 30) + feed([open], 0.5)).isEmpty)
        check("index pinch with middle nearby = left click", acts(feed([nearMid], 0.1) + feed([open], 0.5)) == [.leftClick(1)])
        check("middle tap = right click", acts(feed([mid], 0.1) + feed([open], 0.5)) == [.rightClick])

        // Trackpad-style motion. Δx = how far the cursor went (screen widths) for a hand slide of `dist` over `secs`.
        func slide(_ dist: CGFloat, _ secs: Double, scale: CGFloat = 1) -> CGFloat {
            _ = feed([], 0.1) // brief loss resets motion, so jumping to the start position moves nothing
            c.place(CGPoint(x: 0.1, y: 0.5))
            let n = Int((secs * 30).rounded())
            var e: [CursorEvent] = []
            for i in 1...n { t += 1.0 / 30; e += c.step(t: t, hands: [testHand(.open, dx: dist * CGFloat(i) / CGFloat(n), scale: scale)]) }
            e += feed([testHand(.open, dx: dist, scale: scale)], 0.5) // let the filter settle
            let xs = e.compactMap { if case let .move(p) = $0 { return p.x }; return nil }
            return (xs.last ?? 0.1) - 0.1
        }
        _ = feed([open], 0.5)
        check("still hand: cursor doesn't drift", !feed([open], 1.0).contains { if case .move = $0 { return true }; return false })
        let slow = slide(0.05, 1.0), fast = slide(0.05, 0.15), farSlow = slide(0.025, 1.0, scale: 0.5)
        print(String(format: "info cursor: a ½-palm (~4 cm) slide moves %.2f screen slow, %.2f fast, %.2f from twice as far away", slow, fast, farSlow))
        check("slow slide moves the cursor (\(slow))", slow > 0.08)
        check("same slide done fast goes ≥2× further (\(fast) vs \(slow))", fast > 2 * slow)
        check("distance from camera doesn't change speed (\(farSlow) vs \(slow))", abs(farSlow - slow) < 0.25 * slow)
        _ = feed([open], 0.3)

        e = feed([pinch], 0.4) + feed([testHand(.pinch, dx: 0.1)], 0.3) + feed([open], 0.3)
        let down = e.firstIndex(of: .leftDown) ?? -1, up = e.firstIndex(of: .leftUp) ?? -1
        check("hold = drag, no click", acts(e) == [.leftDown, .leftUp]
            && e[max(0, down)..<max(0, up)].contains { if case .move = $0 { return true }; return false })

        e = feed([peace], 0.5)
        check("peace enters scroll", e.contains(.scrollMode(true)))
        e += feed([testHand(.peace, dy: 0.02)], 0.3)
        check("scroll dead zone", !e.contains { if case .scroll = $0 { return true }; return false })
        e += feed([testHand(.peace, dy: 0.15)], 0.3)
        let scrolls = e.compactMap { if case let .scroll(dx, dy) = $0 { return (dx, dy) }; return nil }
        check("hand down scrolls down", !scrolls.isEmpty && scrolls.allSatisfy { $0.0 == 0 && $0.1 > 0 })
        check("cursor still while scrolling", !e.contains { if case .move = $0 { return true }; return false })
        check("scroll ends", feed([open], 0.5).contains(.scrollMode(false)))

        e = feed([pinchL, pinchR], 1.0) + feed([openL, openR], 0.3)
        check("early two-hand release cancels", !e.contains(.exit) && e.contains(.progress(nil)) && acts(e).isEmpty && c.active)
        e = feed([pinchL, openR], 0.2) + feed([pinchL, pinchR], 1.9)
        check("no exit before 2s, no click from staggered pinch", !e.contains(.exit) && acts(e).isEmpty)
        check("exit after 2s", feed([pinchL, pinchR], 0.2).contains(.exit) && !c.active)
        check("held exit pose does not re-arm", !feed([pinchL, pinchR], 1.0).contains(.enter) && !c.active)

        _ = feed([open], 0.2) + feed([pinch], 0.7) + feed([open], 0.2)
        check("re-armed", c.active)
        check("drag starts", feed([pinch], 0.5).contains(.leftDown))
        check("short loss keeps drag", !feed([], 1.4).contains(.leftUp))
        check("lost hand releases drag", feed([], 0.3) == [.leftUp])
        check("returning pinch must reopen first", acts(feed([pinch], 0.5)).isEmpty)
        var noThumb = pinch
        noThumb.points[.thumbTip] = nil
        _ = feed([open], 0.2)
        check("drag starts again", feed([pinch], 0.5).contains(.leftDown))
        check("hidden thumb mid-drag releases", feed([noThumb], 1.6) == [.leftUp])
        check("lost 20s exits", feed([], 21).contains(.exit) && !c.active)
        check("nothing after exit", acts(feed([open], 0.2) + feed([pinch], 0.1) + feed([open], 0.3)).isEmpty)
        return ok
    }
}

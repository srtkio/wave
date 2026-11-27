import CoreGraphics

/// The one place that decides who may act on the hand, so features never cross-fire.
///
/// Rule, in order:
///  1. Face check failing -> nobody.
///  2. Cursor mode active, or a cursor-arming pinch held -> only cursor mode.
///  3. A bound hand sign pose -> only hand signs, unless a feature gesture is already mid-stroke (air ink drawing),
///     which keeps the hand until it lets go.
///  4. Otherwise -> features. Inside that lane the face decides: finger on the lips = meeting mute, hand resting on
///     the face = face-touch alert, anywhere else = media / air ink. Those three zones never overlap.
/// Features get blank frames while they are not in charge, so held poses end and dwell timers reset.
enum Arbiter {
    enum Lane: String { case cursor, sign, feature }
    enum System: String, CaseIterable { case cursor, sign, media, ink, meeting, touch }
    enum Zone { case none, lips, onFace }

    /// Set by a feature that holds the hand across frames (air ink while drawing). Main thread only.
    static var featureHeld = false
    private static var lastLog = ""

    static var faceOK: Bool { HandTracker.shared.gesturesAllowed }

    /// Pure: the rule above. nil = nobody acts.
    static func lane(armOrActive cursor: Bool, signPose: Bool, faceOK: Bool, featureHeld: Bool) -> Lane? {
        guard faceOK else { return nil }
        if cursor { return .cursor }
        return signPose && !featureHeld ? .sign : .feature
    }

    /// Live version for the frame callbacks. Logs each change of lane with the reason.
    static func lane(_ f: HandFrame) -> Lane? {
        let t = HandTracker.shared, signs = HandSigns.shared
        let hand = f.hands.first
        let s = signs.enabled ? signs.currentSign(f) : nil
        let bound = s.map { signs.actions[$0].map { $0 != SignAction.none } ?? false } ?? false
        let arming = !t.cursorActive && (hand.map(CursorCore.armPose) ?? false)
        let l = lane(armOrActive: t.cursorActive || arming, signPose: bound, faceOK: t.gesturesAllowed, featureHeld: featureHeld)
        let why = l == nil ? "face check failing"
            : l == .cursor ? (t.cursorActive ? "cursor active" : "pinch arming")
            : l == .sign ? "sign \(s?.rawValue ?? "?")"
            : bound ? "sign \(s?.rawValue ?? "?") suppressed, feature mid-stroke" : "free"
        let line = "\(l?.rawValue ?? "none") (\(why))"
        if line != lastLog { lastLog = line; SessionLog.log("arbiter lane \(line)") }
        return l
    }

    /// Where the hand is relative to the face. A pointing finger on the mouth beats "hand on face".
    // shortcut: "on face" = 3+ joints inside the face box (the old FaceTouch rule); lips = index extended with its tip in the lower third.
    static func zone(_ f: HandFrame) -> Zone {
        guard let face = f.face else { return .none }
        let mouth = mouthZone(face)
        if f.hands.contains(where: { extendedFingers($0)[1] && ($0.points[.indexTip].map(mouth.contains) ?? false) }) { return .lips }
        let inside = f.hands.reduce(0) { $0 + $1.points.values.filter(face.contains).count }
        return inside >= 3 ? .onFace : .none
    }

    /// Which systems would act on this frame. Mirrors the live triggers so `selfCheck` can prove at most one does.
    static func acting(_ f: HandFrame, cursorActive: Bool = false, featureHeld: Bool = false, faceOK: Bool = true) -> Set<System> {
        let h = f.hands.first
        let arming = !cursorActive && (h.map(CursorCore.armPose) ?? false)
        guard let l = lane(armOrActive: cursorActive || arming, signPose: h.flatMap(sign) != nil, faceOK: faceOK, featureHeld: featureHeld)
        else { return [] }
        switch l {
        case .cursor: return [.cursor]
        case .sign: return [.sign]
        case .feature:
            switch zone(f) {
            case .lips: return [.meeting]
            case .onFace: return [.touch]
            case .none:
                guard let h else { return [] }
                switch classify(h) {
                case .fist: return [.media]
                case .point, .open: return [.ink] // point draws, open palm clears
                default: return []
                }
            }
        }
    }

    // MARK: self-check

    private enum Thumb { case tucked, out, up }

    /// Copy of SelfTest.hand (wrist (0.5, 0.8), palm 0.2); `tipOnThumb` puts the index tip on the thumb tip.
    private static func hand(_ thumb: Thumb, _ fingers: [Bool], tipOnThumb: Bool = false) -> Hand {
        var p: [Joint: CGPoint] = [
            .wrist: CGPoint(x: 0.5, y: 0.8), .thumbCMC: CGPoint(x: 0.42, y: 0.75),
            .thumbMP: CGPoint(x: 0.38, y: 0.7), .thumbIP: CGPoint(x: 0.35, y: 0.66),
        ]
        p[.thumbTip] = switch thumb {
        case .tucked: CGPoint(x: 0.5, y: 0.56)
        case .out: CGPoint(x: 0.3, y: 0.62)
        case .up: CGPoint(x: 0.4, y: 0.4)
        }
        let chains: [(x: CGFloat, mcp: Joint, pip: Joint, dip: Joint, tip: Joint)] = [
            (0.44, .indexMCP, .indexPIP, .indexDIP, .indexTip), (0.50, .middleMCP, .middlePIP, .middleDIP, .middleTip),
            (0.56, .ringMCP, .ringPIP, .ringDIP, .ringTip), (0.62, .littleMCP, .littlePIP, .littleDIP, .littleTip),
        ]
        for (i, c) in chains.enumerated() {
            let up = fingers[i]
            p[c.mcp] = CGPoint(x: c.x, y: 0.6)
            p[c.pip] = CGPoint(x: c.x, y: up ? 0.5 : 0.52)
            p[c.dip] = CGPoint(x: c.x, y: up ? 0.45 : 0.6)
            p[c.tip] = CGPoint(x: c.x, y: up ? 0.4 : 0.66)
        }
        if tipOnThumb { p[.indexTip] = CGPoint(x: 0.31, y: 0.61) }
        return Hand(points: p, chirality: .right)
    }

    private static let poses: [(name: String, hand: Hand)] = {
        let t = true, f = false
        return [
            ("open", hand(.out, [t, t, t, t])), ("fist", hand(.tucked, [f, f, f, f])),
            ("pinch", hand(.out, [t, f, f, f], tipOnThumb: true)), ("ok", hand(.out, [t, t, t, t], tipOnThumb: true)),
            ("rock", hand(.tucked, [t, f, f, t])), ("callMe", hand(.out, [f, f, f, t])), ("l", hand(.out, [t, f, f, f])),
            ("thumbsUp", hand(.up, [f, f, f, f])), ("peace", hand(.tucked, [t, t, f, f])), ("point", hand(.tucked, [t, f, f, f])),
        ]
    }()

    /// What each pose does with every toggle on and nothing active.
    private static let idle: [String: System] = [
        "open": .ink, "fist": .media, "pinch": .cursor, "ok": .sign, "rock": .sign, "callMe": .sign, "l": .sign,
        "thumbsUp": .sign, "peace": .sign, "point": .ink,
    ]

    /// pose x state -> who acts. States: idle, media on (a held fist has no state of its own, same lane as idle),
    /// air ink drawing (featureHeld), cursor active, face check failing. All toggles are on, the worst case.
    static func matrix() -> [(pose: String, state: String, acts: Set<System>, expected: Set<System>)] {
        let states: [(String, Bool, Bool, Bool)] = [("idle", false, false, true), ("media on", false, false, true),
                                                    ("air ink on", false, true, true), ("cursor active", true, false, true),
                                                    ("face failing", false, false, false)]
        var out: [(String, String, Set<System>, Set<System>)] = []
        for (name, h) in poses {
            for (state, cursor, held, face) in states {
                let want: Set<System>
                if !face { want = [] }
                else if cursor { want = [.cursor] }
                // The stroke keeps its hand. L is a pointing finger, so ink carries on. Any other sign pose means the
                // stroke has ended: ink clears featureHeld on that very frame, so nobody acts for one frame, then the sign owns it.
                else if state == "air ink on", idle[name] == .sign { want = name == "l" ? [.ink] : [] }
                else { want = [idle[name]!] }
                out.append((name, state, acting(HandFrame(hands: [h]), cursorActive: cursor, featureHeld: held, faceOK: face), want))
            }
        }
        return out
    }

    /// Crossfire matrix: for every pose x state at most one system acts, and it is the right one. Prints each failure.
    static func selfCheck() -> Bool {
        var ok = true
        func check(_ name: String, _ pass: Bool) { if !pass { print("FAIL arbiter:", name); ok = false } }

        for r in matrix() {
            check("\(r.pose) / \(r.state): got \(r.acts.map(\.rawValue).sorted()), want \(r.expected.map(\.rawValue).sorted())",
                  r.acts.count <= 1 && r.acts == r.expected)
        }

        // Face context: a face placed so the index tip is on the lips, and one covering the whole hand.
        for (name, h) in poses {
            let tip = h.points[.indexTip]!
            let lips = CGRect(x: tip.x - 0.1, y: tip.y - 0.25, width: 0.2, height: 0.3) // mouth zone is y in [tip.y - 0.05, tip.y + 0.05]
            let xs = h.points.values.map(\.x), ys = h.points.values.map(\.y)
            let cover = CGRect(x: xs.min()! - 0.05, y: ys.min()! - 0.05, width: xs.max()! - xs.min()! + 0.1, height: ys.max()! - ys.min()! + 0.1)
            let signPose = sign(h) != nil, arm = CursorCore.armPose(h)
            let a = acting(HandFrame(hands: [h], face: lips)), b = acting(HandFrame(hands: [h], face: cover))
            check("\(name) at lips: at most one, got \(a.map(\.rawValue))", a.count <= 1)
            check("\(name) on face: at most one, got \(b.map(\.rawValue))", b.count <= 1)
            if name == "point" { check("point at lips = meeting mute only", a == [.meeting]) }
            if signPose { check("\(name) sign beats the face zones", a == [.sign] && b == [.sign]) }
            if arm { check("\(name) pinch beats the face zones", a == [.cursor] && b == [.cursor]) }
            if name == "fist" || name == "open" { check("\(name) resting on the face = touch alert only", b == [.touch]) }
        }
        return ok
    }
}

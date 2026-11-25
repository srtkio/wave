import CoreGraphics

/// Named hand signs that can be bound to an action. Held, not flicked: see `HandSigns`.
enum Sign: String, CaseIterable {
    case rock, callMe, ok, l, thumbsUp, peace

    var emoji: String {
        switch self {
        case .rock: "🤘"
        case .callMe: "🤙"
        case .ok: "👌"
        case .l: "🇱"
        case .thumbsUp: "👍"
        case .peace: "✌️"
        }
    }

    var title: String {
        switch self {
        case .rock: "Rock"
        case .callMe: "Call me"
        case .ok: "OK"
        case .l: "L"
        case .thumbsUp: "Thumbs up"
        case .peace: "Peace"
        }
    }
}

private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

private let needed: [Joint] = [.wrist, .middleMCP, .indexMCP, .thumbTip, .indexTip, .indexPIP, .middleTip, .middlePIP,
                               .ringTip, .ringPIP, .littleTip, .littlePIP]

/// The sign this hand is making, or nil when it is anything else. Distances are relative to palm size
/// (wrist to middle knuckle), like `classify`. Finger up/curled comes from `extendedFingers`.
func sign(_ h: Hand) -> Sign? {
    let p = h.points
    // A missing joint reads as "curled" in extendedFingers, which would fake a sign, so bail out.
    guard needed.allSatisfy({ p[$0] != nil }) else { return nil }
    let wrist = p[.wrist]!, thumbTip = p[.thumbTip]!, indexMCP = p[.indexMCP]!, indexTip = p[.indexTip]!
    let palm = dist(wrist, p[.middleMCP]!)
    guard palm > 0 else { return nil }

    let e = extendedFingers(h)
    // Thumb touching the index tip: OK only when the other three fingers are up, otherwise a plain pinch, which is no sign.
    // (classify() calls both .pinch; the engine uses sign() alone.)
    if dist(thumbTip, indexTip) < 0.3 * palm { return e[2] && e[3] && e[4] ? .ok : nil }

    switch (e[0], e[1], e[2], e[3], e[4]) {
    case (_, true, false, false, true): return .rock
    case (true, false, false, false, true): return .callMe
    case (true, true, false, false, false):
        // shortcut: |cos| < 0.6 (about 53-127 degrees) between thumb and index, measured from the index knuckle; tune on hardware.
        let a = CGPoint(x: thumbTip.x - indexMCP.x, y: thumbTip.y - indexMCP.y)
        let b = CGPoint(x: indexTip.x - indexMCP.x, y: indexTip.y - indexMCP.y)
        let len = hypot(a.x, a.y) * hypot(b.x, b.y)
        return len > 0 && abs((a.x * b.x + a.y * b.y) / len) < 0.6 ? .l : nil
    case (true, false, false, false, false):
        // Tip must be clearly above the knuckle (0.3 palm), so a sideways thumb on a fist is not a thumbs up.
        return thumbTip.y < indexMCP.y - 0.3 * palm ? .thumbsUp : nil
    case (false, true, true, false, false): return .peace
    default: return nil
    }
}

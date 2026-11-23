import CoreGraphics

enum Gesture: String, CaseIterable {
    case none, open, fist, pinch, peace, point, thumbsUp
}

private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

private let fingerJoints: [(tip: Joint, pip: Joint)] = [
    (.indexTip, .indexPIP), (.middleTip, .middlePIP), (.ringTip, .ringPIP), (.littleTip, .littlePIP),
]
private let keyJoints: [Joint] = [.wrist, .middleMCP, .indexMCP, .thumbTip] + fingerJoints.flatMap { [$0.tip, $0.pip] }

/// [thumb, index, middle, ring, little]. Missing joints count as not extended.
func extendedFingers(_ h: Hand) -> [Bool] {
    let p = h.points
    guard let wrist = p[.wrist], let middleMCP = p[.middleMCP] else { return Array(repeating: false, count: 5) }
    let palm = dist(wrist, middleMCP)
    var thumb = false
    if let tip = p[.thumbTip], let indexMCP = p[.indexMCP] { thumb = dist(tip, indexMCP) > 0.5 * palm }
    let fingers = fingerJoints.map { j -> Bool in
        guard let tip = p[j.tip], let pip = p[j.pip] else { return false }
        return dist(tip, wrist) > 1.1 * dist(pip, wrist)
    }
    return [thumb] + fingers
}

func fingerCount(_ h: Hand) -> Int { extendedFingers(h).filter { $0 }.count }

func classify(_ h: Hand) -> Gesture {
    let p = h.points
    guard keyJoints.allSatisfy({ p[$0] != nil }) else { return .none }
    let palm = dist(p[.wrist]!, p[.middleMCP]!)
    guard palm > 0 else { return .none }
    if dist(p[.thumbTip]!, p[.indexTip]!) < 0.3 * palm { return .pinch }
    let e = extendedFingers(h)
    switch Array(e[1...]) {
    case [true, true, true, true]: return .open
    case [false, false, false, false]: return e[0] && p[.thumbTip]!.y < p[.indexMCP]!.y ? .thumbsUp : .fist
    case [true, false, false, false]: return .point
    case [true, true, false, false]: return .peace
    default: return .none
    }
}

/// Only switches to a new gesture after it has been seen 3 frames in a row.
struct GestureStabilizer {
    private(set) var stable: Gesture = .none
    private var candidate: Gesture = .none
    private var count = 0

    mutating func update(_ g: Gesture) -> Gesture {
        if g == candidate { count += 1 } else { candidate = g; count = 1 }
        if count >= 3 { stable = g }
        return stable
    }
}

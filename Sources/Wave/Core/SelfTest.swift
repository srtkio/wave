import CoreGraphics
import Foundation

/// `swift run Wave --selftest`: synthetic hands in top-left, mirrored space (y grows downward).
enum SelfTest {
    enum Thumb { case tucked, out, up }

    /// Wrist (0.5, 0.8), middle MCP (0.5, 0.6): palm = 0.2.
    static func hand(_ thumb: Thumb, _ fingers: [Bool]) -> Hand {
        var p: [Joint: CGPoint] = [
            .wrist: CGPoint(x: 0.5, y: 0.8),
            .thumbCMC: CGPoint(x: 0.42, y: 0.75),
            .thumbMP: CGPoint(x: 0.38, y: 0.7),
            .thumbIP: CGPoint(x: 0.35, y: 0.66),
        ]
        p[.thumbTip] = switch thumb {
        case .tucked: CGPoint(x: 0.5, y: 0.56) // across the palm, near index MCP
        case .out: CGPoint(x: 0.3, y: 0.62)    // sideways
        case .up: CGPoint(x: 0.4, y: 0.4)      // above index MCP
        }
        let chains: [(x: CGFloat, mcp: Joint, pip: Joint, dip: Joint, tip: Joint)] = [
            (0.44, .indexMCP, .indexPIP, .indexDIP, .indexTip),
            (0.50, .middleMCP, .middlePIP, .middleDIP, .middleTip),
            (0.56, .ringMCP, .ringPIP, .ringDIP, .ringTip),
            (0.62, .littleMCP, .littlePIP, .littleDIP, .littleTip),
        ]
        for (i, c) in chains.enumerated() {
            let up = fingers[i]
            p[c.mcp] = CGPoint(x: c.x, y: 0.6)
            p[c.pip] = CGPoint(x: c.x, y: up ? 0.5 : 0.52)
            p[c.dip] = CGPoint(x: c.x, y: up ? 0.45 : 0.6)
            p[c.tip] = CGPoint(x: c.x, y: up ? 0.4 : 0.66) // curled tip folds back toward the wrist
        }
        return Hand(points: p, chirality: .right)
    }

    static func run() -> Never {
        var failed = 0
        func check(_ name: String, _ ok: Bool) {
            print(ok ? "PASS" : "FAIL", name)
            if !ok { failed += 1 }
        }

        let all = [true, true, true, true], none = [false, false, false, false]
        var pinch = hand(.out, all)
        pinch.points[.indexTip] = CGPoint(x: 0.31, y: 0.61)
        var missing = hand(.out, all)
        missing.points[.wrist] = nil

        check("open palm", classify(hand(.out, all)) == .open)
        check("fist", classify(hand(.tucked, none)) == .fist)
        check("fist with thumb out sideways", classify(hand(.out, none)) == .fist)
        check("pinch", classify(pinch) == .pinch)
        check("peace", classify(hand(.tucked, [true, true, false, false])) == .peace)
        check("point", classify(hand(.tucked, [true, false, false, false])) == .point)
        check("thumbs up", classify(hand(.up, none)) == .thumbsUp)
        check("missing wrist -> none", classify(missing) == .none)

        for n in 0...4 {
            let h = hand(.tucked, (0..<4).map { $0 < n })
            check("finger count \(n)", fingerCount(h) == n)
        }
        check("finger count 5", fingerCount(hand(.out, all)) == 5)
        check("extendedFingers peace", extendedFingers(hand(.tucked, [true, true, false, false])) == [false, true, true, false, false])

        var s = GestureStabilizer()
        check("stabilizer frame 1 holds", s.update(.fist) == .none)
        check("stabilizer frame 2 holds", s.update(.fist) == .none)
        check("stabilizer frame 3 switches", s.update(.fist) == .fist)
        _ = s.update(.open); _ = s.update(.open); _ = s.update(.pinch)
        check("stabilizer A,A,B,A does not switch", s.update(.open) == .fist)

        check("viewPoint centre", viewPoint(CGPoint(x: 0.5, y: 0.5), in: CGSize(width: 800, height: 600)) == CGPoint(x: 400, y: 300))
        check("viewPoint corner in 16:9 view", viewPoint(.zero, in: CGSize(width: 1600, height: 900)) == .zero)

        ShortcutEngine.selfCheck()  // asserts; traps on failure in debug builds
        print("PASS shortcut engine state machine")
        check("feature checks", FeatureChecks.run())
        check("playground math", PlaygroundMath.selfCheck())

        print(failed == 0 ? "ALL PASS" : "\(failed) FAILED")
        exit(failed == 0 ? 0 : 1)
    }
}

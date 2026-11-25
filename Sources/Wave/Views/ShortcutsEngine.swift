import AppKit
import Observation

/// Background gesture shortcuts: grab & drop, finger macros, clipboard history.
/// Runs off HandTracker.onFrame so it works on every tab. `step` is pure apart from `perform`, so selfCheck drives it with fake time.
@Observable
final class ShortcutEngine {
    static let shared = ShortcutEngine()

    enum Grab { case ready, grabbed, dropped }
    enum Act: Equatable { case copy, paste, run(String), setClip(String) }

    static let grabKey = "sc.grab", macrosKey = "sc.macros", clipKey = "sc.clip"
    static func macroKey(_ n: Int) -> String { "sc.macro.\(n)" }
    static let fistHold = 0.5, dropWindow = 3.0, macroHold = 0.8, pinchHold = 0.6, pinchStep = 0.07

    // Observed by the UI.
    private(set) var grab = Grab.ready
    private(set) var heldCount = 0
    private(set) var progress = 0.0   // 0...1 of macroHold for heldCount
    private(set) var fired = false    // macro already ran: cooldown until the count changes
    private(set) var historyOpen = false
    private(set) var selected = 0
    var items: [String] = [] // memory only, never persisted; settable so --snapshot can show sample items

    @ObservationIgnored var perform: (Act) -> Void = ShortcutEngine.realAct
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var changeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var fistSince: TimeInterval?
    @ObservationIgnored private var grabAt: TimeInterval = 0
    @ObservationIgnored private var countSince: TimeInterval = 0
    @ObservationIgnored private var pinchSince: TimeInterval?
    @ObservationIgnored private var anchorX: CGFloat = 0

    init() {
        UserDefaults.standard.register(defaults: [Self.grabKey: false, Self.macrosKey: false, Self.clipKey: false]) // off until hand signs replace them
    }

    /// Safe to call repeatedly (app launch and ShortcutsView both do).
    func start() {
        guard listener == nil else { return }
        listener = HandTracker.shared.onFrame { [weak self] f, g in
            guard let self, !HandTracker.shared.cursorActive else { return }
            let t = Date.timeIntervalSinceReferenceDate
            guard let hand = f.hands.first else { return self.step(t: t, gesture: .none, fingers: 0, x: nil) }
            self.step(t: t, gesture: g, fingers: fingerCount(hand),
                      x: (hand.points[.wrist] ?? hand.points.values.first)?.x)
        }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.pollClipboard() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func on(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    func step(t: TimeInterval, gesture: Gesture, fingers: Int, x: CGFloat?) {
        // Grab & drop
        if on(Self.grabKey) {
            fistSince = gesture == .fist ? (fistSince ?? t) : nil
            switch grab {
            case .ready:
                if let s = fistSince, t - s >= Self.fistHold { perform(.copy); grab = .grabbed; grabAt = t; fistSince = nil }
            case .grabbed:
                if gesture == .open { perform(.paste); grab = .dropped; grabAt = t }
                else if t - grabAt > Self.dropWindow { grab = .ready }
            case .dropped:
                if t - grabAt > 1.5 { grab = .ready }
            }
        } else if grab != .ready { grab = .ready }

        // Clipboard history
        if on(Self.clipKey), gesture == .pinch {
            pinchSince = pinchSince ?? t
            if !historyOpen, t - pinchSince! >= Self.pinchHold, let x, !items.isEmpty {
                historyOpen = true; anchorX = x; selected = items.count / 2
            } else if historyOpen, let x {
                let s = items.count / 2 + Int(((x - anchorX) / Self.pinchStep).rounded())
                selected = min(max(s, 0), items.count - 1)
            }
        } else {
            pinchSince = nil
            if historyOpen {
                historyOpen = false
                if items.indices.contains(selected) { perform(.setClip(items[selected])); perform(.paste) }
            }
        }

        // Finger macros: held steady, then fire once until the count changes.
        let busy = grab == .grabbed || historyOpen || gesture == .pinch
        let count = (on(Self.macrosKey) && !busy && (1...5).contains(fingers)) ? fingers : 0
        if count != heldCount { heldCount = count; countSince = t; fired = false; progress = 0 }
        guard count > 0, !fired else { return }
        let p = min((t - countSince) / Self.macroHold, 1)
        if abs(p - progress) > 0.02 || p == 1 { progress = p }
        if p >= 1 {
            fired = true
            let name = UserDefaults.standard.string(forKey: Self.macroKey(count)) ?? ""
            if !name.isEmpty { perform(.run(name)) }
        }
    }

    private func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount
        guard on(Self.clipKey) else { return }
        // Password managers tag secrets with these nspasteboard.org markers; never keep them.
        let secret = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
        if pb.types?.contains(where: { secret.contains($0.rawValue) }) == true { return }
        guard let s = pb.string(forType: .string), !s.isEmpty else { return }
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > 5 { items.removeLast() }
    }

    private static func realAct(_ a: Act) {
        switch a {
        case .copy: Output.copy()
        case .paste: Output.paste()
        case .run(let n): Output.runShortcut(n)
        case .setClip(let s):
            let pb = NSPasteboard.general
            pb.clearContents(); pb.setString(s, forType: .string)
            shared.changeCount = pb.changeCount // our own write is not a new item
        }
    }

    /// Run by `--selftest`. Traps via assert in debug builds.
    @discardableResult static func selfCheck() -> Bool {
        let d = UserDefaults.standard
        let saved = (1...5).map { d.string(forKey: macroKey($0)) }
        let toggles = [grabKey, macrosKey, clipKey]
        let savedToggles = toggles.map { d.object(forKey: $0) }
        defer {
            for (i, v) in saved.enumerated() { d.set(v, forKey: macroKey(i + 1)) }
            for (k, v) in zip(toggles, savedToggles) { d.set(v, forKey: k) }
        }
        d.set("Focus", forKey: macroKey(2))
        for k in toggles { d.set(true, forKey: k) }
        let e = ShortcutEngine()
        var log: [Act] = []
        e.perform = { log.append($0) }

        // fist: not before 0.5 s, then copies once; open inside the window pastes
        for t in stride(from: 0.0, to: 0.45, by: 0.05) { e.step(t: t, gesture: .fist, fingers: 0, x: 0.5) }
        assert(log.isEmpty && e.grab == .ready, "fist too early")
        e.step(t: 0.5, gesture: .fist, fingers: 0, x: 0.5)
        assert(log == [.copy] && e.grab == .grabbed, "grab at 0.5s")
        e.step(t: 0.6, gesture: .fist, fingers: 0, x: 0.5)
        assert(log == [.copy], "no second copy")
        e.step(t: 1.0, gesture: .open, fingers: 5, x: 0.5)
        assert(log == [.copy, .paste] && e.grab == .dropped, "drop")
        e.step(t: 3.0, gesture: .none, fingers: 0, x: nil)
        assert(e.grab == .ready, "back to ready")
        // grabbed expires after 3 s
        e.step(t: 10, gesture: .fist, fingers: 0, x: 0.5); e.step(t: 10.5, gesture: .fist, fingers: 0, x: 0.5)
        e.step(t: 13.6, gesture: .none, fingers: 0, x: nil)
        assert(e.grab == .ready, "grab expires")

        // macro: 2 fingers fires at 0.8 s once, cooldown until the count changes
        log = []
        e.step(t: 20, gesture: .peace, fingers: 2, x: 0.5)
        e.step(t: 20.7, gesture: .peace, fingers: 2, x: 0.5)
        assert(log.isEmpty, "macro too early")
        e.step(t: 20.8, gesture: .peace, fingers: 2, x: 0.5)
        assert(log == [.run("Focus")] && e.fired, "macro fires")
        e.step(t: 22, gesture: .peace, fingers: 2, x: 0.5)
        assert(log.count == 1, "cooldown")
        e.step(t: 22.1, gesture: .point, fingers: 1, x: 0.5)
        e.step(t: 22.2, gesture: .peace, fingers: 2, x: 0.5)
        e.step(t: 23.0, gesture: .peace, fingers: 2, x: 0.5)
        assert(log.count == 2, "fires again after the hand changed")

        // clipboard: pinch 0.6 s opens, moving right selects higher, release pastes it
        log = []; e.items = ["a", "b", "c"]
        e.step(t: 30, gesture: .pinch, fingers: 2, x: 0.5)
        e.step(t: 30.5, gesture: .pinch, fingers: 2, x: 0.5)
        assert(!e.historyOpen, "pinch too early")
        e.step(t: 30.6, gesture: .pinch, fingers: 2, x: 0.5)
        assert(e.historyOpen && e.selected == 1, "history opens at middle")
        e.step(t: 30.7, gesture: .pinch, fingers: 2, x: 0.65)
        assert(e.selected == 2, "right selects next")
        e.step(t: 30.8, gesture: .open, fingers: 5, x: 0.65)
        assert(log == [.setClip("c"), .paste] && !e.historyOpen, "release pastes selection")
        return true
    }
}

import AppKit
import ApplicationServices

/// Controls the Mac cursor with your hand. Hold a thumb+index pinch 0.6s to start; pinch both hands side by side 2s to stop.
/// The logic lives in `CursorCore`; this class only turns its events into CGEvents and notch updates.
final class CursorMode {
    static let shared = CursorMode()

    private var core = CursorCore()
    private var listener: UUID?
    private var lastTick: TimeInterval = 0
    private var trusted = false, trustCheckedAt: TimeInterval = 0
    private var buttonDown = false

    static func selfCheck() -> Bool { CursorCore.selfCheck() }

    func start() {
        guard listener == nil else { return }
        let tracker = HandTracker.shared
        // onAnyFrame, not onFrame: while gestures are blocked we still feed "no hand" so a held drag gets released.
        listener = tracker.onAnyFrame { [weak self] frame, _ in
            self?.tick(Arbiter.faceOK ? frame.hands : [])
        }
        // Turning Wave off stops frames entirely; keep time moving so held buttons release and the mode times out.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, ProcessInfo.processInfo.systemUptime - self.lastTick > 0.4 else { return }
            self.tick([])
        }
    }

    /// Wave was switched off: end cursor mode now instead of waiting for the lost-hand timeout.
    func stop() {
        if buttonDown { post(.leftUp) }
        let wasActive = HandTracker.shared.cursorActive
        core = CursorCore()
        HandTracker.shared.cursorActive = false
        NotchHUD.shared.progress = nil
        NotchHUD.shared.setSticky(nil)
        if wasActive { NotchHUD.shared.flash("Cursor off", symbol: "cursorarrow.slash") }
    }

    private func tick(_ hands: [Hand]) {
        lastTick = ProcessInfo.processInfo.systemUptime
        for e in core.step(t: lastTick, hands: hands) { apply(e) }
    }

    private func apply(_ e: CursorEvent) {
        switch e {
        case .move, .progress: break
        default: SessionLog.log("cursor \(e)")
        }
        let hud = NotchHUD.shared
        switch e {
        case .enter:
            HandTracker.shared.cursorActive = true
            trusted = Output.ensureAccessibility()
            trustCheckedAt = lastTick
            hud.setSticky("Cursor", symbol: "cursorarrow.motionlines")
            if trusted { hud.flash("Cursor on", symbol: "cursorarrow.motionlines") }
            else { hud.flash("Allow Accessibility", symbol: "lock.shield") }
        case .exit:
            HandTracker.shared.cursorActive = false
            hud.progress = nil
            hud.setSticky(nil)
            hud.flash("Cursor off", symbol: "cursorarrow.slash")
        case .progress(let p):
            hud.progress = p
        case .scrollMode(let on):
            if on { hud.flash("Scroll", symbol: "scroll") }
        default:
            post(e)
        }
    }

    private func post(_ e: CursorEvent) {
        if !trusted { // re-check once a second so granting Accessibility mid-session starts working
            guard lastTick - trustCheckedAt > 1 else { return }
            trustCheckedAt = lastTick
            trusted = AXIsProcessTrusted()
            guard trusted else { return }
        }
        let here = CGEvent(source: nil)?.location ?? .zero
        func mouse(_ type: CGEventType, _ at: CGPoint, _ button: CGMouseButton = .left, clicks: Int = 1) {
            let m = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: at, mouseButton: button)
            m?.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
            m?.post(tap: .cghidEventTap)
        }
        switch e {
        case .move(let p):
            let b = CGDisplayBounds(CGMainDisplayID())
            let at = CGPoint(x: b.minX + p.x * (b.width - 1), y: b.minY + p.y * (b.height - 1))
            mouse(buttonDown ? .leftMouseDragged : .mouseMoved, at)
        case .leftDown:
            buttonDown = true
            mouse(.leftMouseDown, here)
        case .leftUp:
            buttonDown = false
            mouse(.leftMouseUp, here)
        case .leftClick(let n):
            mouse(.leftMouseDown, here, clicks: n)
            mouse(.leftMouseUp, here, clicks: n)
        case .rightClick:
            mouse(.rightMouseDown, here, .right)
            mouse(.rightMouseUp, here, .right)
        case let .scroll(dx, dy):
            // shortcut: wheel sign assumes posted events skip natural-scroll inversion; flip both minus signs if backwards.
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                    wheel1: Int32(-dy), wheel2: Int32(-dx), wheel3: 0)?.post(tap: .cghidEventTap)
        default:
            break
        }
    }
}

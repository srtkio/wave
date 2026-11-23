import AppKit
import SwiftUI

struct InkPoint { var p: CGPoint; var t: Double } // p normalised 0–1 over the screen

@Observable
final class InkModel {
    var strokes: [[InkPoint]] = []
    static let life = 5.0, fade = 1.0

    func add(_ p: CGPoint, newStroke: Bool, now: Double) {
        if newStroke || strokes.isEmpty { strokes.append([]) }
        // Smooth the jittery fingertip so the line looks drawn, not tracked.
        let q = strokes[strokes.count - 1].last.map { CGPoint(x: $0.p.x + (p.x - $0.p.x) * 0.5, y: $0.p.y + (p.y - $0.p.y) * 0.5) } ?? p
        strokes[strokes.count - 1].append(InkPoint(p: q, t: now))
    }

    func prune(now: Double) {
        guard !strokes.isEmpty else { return }
        strokes = strokes.map { $0.filter { now - $0.t < Self.life } }.filter { !$0.isEmpty }
    }
}

private struct InkCanvas: View {
    var model: InkModel

    var body: some View {
        TimelineView(.animation(paused: model.strokes.isEmpty)) { tl in
            // Read here, not inside the Canvas closure, so Observation tracks it.
            let strokes = model.strokes
            let now = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                var segs: [(Path, Color, Double)] = []
                for s in strokes {
                    for (a, b) in zip(s, s.dropFirst()) {
                        let alpha = min(1, (InkModel.life - (now - b.t)) / InkModel.fade)
                        guard alpha > 0 else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: a.p.x * size.width, y: a.p.y * size.height))
                        path.addLine(to: CGPoint(x: b.p.x * size.width, y: b.p.y * size.height))
                        segs.append((path, Theme.accent.mix(with: Theme.accent2, by: b.p.x), alpha))
                    }
                }
                func draw(_ c: GraphicsContext, _ width: CGFloat, _ opacity: Double, white: Bool = false) {
                    for (path, color, alpha) in segs {
                        c.stroke(path, with: .color((white ? .white : color).opacity(alpha * opacity)),
                                 style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }
                }
                ctx.drawLayer { l in l.addFilter(.blur(radius: 10)); draw(l, 18, 0.8) } // glow
                draw(ctx, 6, 1)
                draw(ctx, 2, 0.8, white: true)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Pinch to draw glowing ink on a click-through overlay above every app; open palm wipes it.
final class AirInk: FeatureBase {
    private let model = InkModel()
    private var window: NSWindow?
    private var pinching = false

    init() {
        super.init(key: "feature.ink", symbol: "scribble.variable", name: "Air ink",
                   blurb: "Pinch to draw on your screen. Open palm clears.")
    }

    override func begin() {
        pinching = false
        // shortcut: covers the main screen only, add one window per NSScreen for multi-monitor.
        let w = NSWindow(contentRect: NSScreen.main?.frame ?? .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: InkCanvas(model: model))
        w.orderFrontRegardless()
        window = w
        listen { [weak self] f, g in self?.tick(f, g) }
    }

    override func end() {
        window?.orderOut(nil)
        window = nil
        model.strokes = []
    }

    private func tick(_ f: HandFrame, _ g: Gesture) {
        let now = Date().timeIntervalSinceReferenceDate
        if g == .open { model.strokes = [] }
        if g == .pinch, let tip = f.hands.first?.points[.indexTip] {
            model.add(inkMap(tip), newStroke: !pinching, now: now)
            pinching = true
        } else {
            pinching = false
        }
        model.prune(now: now)
    }
}

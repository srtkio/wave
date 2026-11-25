import SwiftUI

/// Cursor mode doesn't publish "arming", so read it off a held pinch plus the notch ring (a plain pinch is never a hand sign).
func cursorArming() -> Double? {
    let t = HandTracker.shared
    guard !t.cursorActive, t.gesture == .pinch else { return nil }
    return NotchHUD.shared.progress
}

func cursorStateTitle() -> String {
    if HandTracker.shared.cursorActive { return "On" }
    return cursorArming() == nil ? "Off" : "Starting…"
}

private func secs(_ s: Double) -> String { String(format: "%g s", s) }

private struct HowTo: Identifiable {
    let symbol: String, title: String, how: String, timing: String
    var id: String { title }
}

// Timings come from CursorCore so this page stays right when the thresholds are retuned.
private let steps: [HowTo] = {
    typealias C = CursorCore
    let tap = "\(String(format: "%g", C.tapMin))–\(secs(C.tapMax))"
    return [
        HowTo(symbol: "hand.pinch", title: "Start", how: "Pinch thumb and index and hold your hand still. A ring fills in the notch.", timing: secs(C.armHold)),
        HowTo(symbol: "cursorarrow.motionlines", title: "Move", how: "Move your hand. The index knuckle steers, so pinching doesn't nudge the cursor.", timing: "Live"),
        HowTo(symbol: "cursorarrow.click", title: "Click", how: "A quick pinch and release of thumb and index.", timing: tap),
        HowTo(symbol: "cursorarrow.click.2", title: "Double-click", how: "Two quick pinches in the same spot.", timing: "Within \(secs(C.doubleGap))"),
        HowTo(symbol: "contextualmenu.and.cursorarrow", title: "Right-click", how: "A quick pinch of thumb and middle finger.", timing: tap),
        HowTo(symbol: "hand.draw", title: "Drag", how: "Pinch and keep holding, then move. Open your fingers to drop.", timing: "Over \(secs(C.tapMax))"),
        HowTo(symbol: "scroll", title: "Scroll", how: "Make a peace sign, then move away from where you started. Further is faster.", timing: secs(C.scrollIn)),
        HowTo(symbol: "xmark.circle", title: "Exit", how: "Pinch with both hands, side by side.", timing: secs(C.exitHold)),
    ]
}()

struct CursorView: View {
    var body: some View {
        let t = HandTracker.shared
        let arming = cursorArming()
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: t.cursorActive ? "cursorarrow.motionlines" : "cursorarrow")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(t.cursorActive ? Theme.accent : Color.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cursor mode: \(cursorStateTitle())").font(.headline)
                        Text(t.cursorActive ? "Your hand moves the pointer. Hand signs and features are paused."
                             : "Hold a pinch to start. Hand signs and features pause while it's on.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let arming {
                        ProgressView(value: arming).frame(width: 120)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("How to") {
                ForEach(steps) { s in
                    HStack(spacing: 12) {
                        Image(systemName: s.symbol)
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title)
                            Text(s.how).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text(s.timing).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section {
                Text("Only the central part of the camera maps to the screen, so you never need to reach the edges. After \(secs(CursorCore.pauseAfter)) without a hand, cursor mode pauses; after \(String(format: "%g", CursorCore.quitAfter)) s it ends.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

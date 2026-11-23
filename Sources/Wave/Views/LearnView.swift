import SwiftUI

private struct Move: Identifiable {
    let id: String, emoji: String, name: String, how: String
    let gesture: Gesture?   // nil means a finger count
    let count: Int
}

private func named(_ g: Gesture, _ emoji: String, _ how: String) -> Move {
    Move(id: g.rawValue, emoji: emoji, name: g.title, how: how, gesture: g, count: 0)
}

// 1, 2 and 5 fingers are Point, Peace and Open palm, so those counts live on the named cards
// instead of lighting a second card for the same hand.
private let moves: [Move] = [
    named(.open, "👋", "Spread all five fingers, palm to the camera. Counts as 5."),
    named(.fist, "✊", "Curl every finger into your palm."),
    named(.pinch, "🤏", "Touch your thumb tip to your index tip."),
    named(.peace, "✌️", "Raise index and middle, fold the rest. Counts as 2."),
    named(.point, "☝️", "Raise only your index finger. Counts as 1."),
    named(.thumbsUp, "👍", "Fist with your thumb pointing up."),
    Move(id: "n3", emoji: "3️⃣", name: "3 fingers", how: "Raise index, middle and ring.", gesture: nil, count: 3),
    Move(id: "n4", emoji: "4️⃣", name: "4 fingers", how: "Thumb and three fingers up, little finger down.", gesture: nil, count: 4),
]

/// Cards lit for this hand. A count card only lights when no named gesture claims the hand.
func litMoves(_ g: Gesture, fingers: Int) -> Set<String> {
    Set(moves.filter { m in m.gesture.map { $0 == g } ?? (g == .none && fingers == m.count) }.map(\.id))
}

struct LearnView: View {
    @AppStorage("learn.tried") private var triedRaw = ""
    @Binding var tab: Tab
    @Environment(\.snapshot) private var snapshot

    /// Ignores ids saved by older versions so progress can't pass the total.
    private var tried: Set<String> { Set(triedRaw.split(separator: ",").map(String.init)).intersection(moves.map(\.id)) }

    var body: some View {
        let t = HandTracker.shared
        let active = litMoves(t.gesture, fingers: t.fingers)
        let done = tried

        Panel(symbol: "hand.raised", title: "Learn the moves",
              caption: "Show each gesture to the camera. Its card lights up when Wave sees it.") {
            HStack {
                progress(done.count)
                Spacer()
                Button("Reset") { withAnimation(Theme.spring) { triedRaw = "" } }
                    .buttonStyle(GlassButtonStyle())
                    .opacity(done.isEmpty ? 0 : 1)
                    .accessibilityHint("Clears your progress")
            }
            if done.count >= moves.count { celebration }
            VStack(spacing: 10) {
                ForEach(moves) { m in
                    MoveCard(move: m, lit: active.contains(m.id), tried: done.contains(m.id))
                }
            }
            .panelScroll()
        }
        .stageColumn()
        .onChange(of: active) { _, now in
            guard !snapshot else { return }
            let merged = done.union(now)
            if merged != done { withAnimation(Theme.spring) { triedRaw = merged.sorted().joined(separator: ",") } }
        }
    }

    private func progress(_ n: Int) -> some View {
        Text("\(n) / \(moves.count) tried")
            .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(Theme.gradient)
                            .frame(width: g.size.width * CGFloat(n) / CGFloat(moves.count))
                    }
                }
            }
            .clipShape(Capsule())
            .animation(Theme.spring, value: n)
            .accessibilityLabel("\(n) of \(moves.count) gestures tried")
    }

    private var celebration: some View {
        Button { withAnimation(Theme.spring) { tab = .playground } } label: {
            Text("🎉 You're a natural. Try the Playground →").frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle(prominent: true))
        .phaseAnimator([1.0, 1.03]) { v, s in v.scaleEffect(s) } animation: { _ in .easeInOut(duration: 1.2) }
        .transition(.scale.combined(with: .opacity))
    }
}

private struct MoveCard: View {
    let move: Move, lit: Bool, tried: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            Text(move.emoji).font(.system(size: 32)).frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Theme.heading(move.name)
                Theme.caption(move.how).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if tried {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18))
                    .foregroundStyle(Theme.success).transition(.scale.combined(with: .opacity))
            }
        }
        .card(highlighted: lit)
        .scaleEffect(lit ? 1.03 : hover ? 1.01 : 1)
        .animation(Theme.spring, value: lit)
        .animation(Theme.spring, value: hover)
        .animation(Theme.spring, value: tried)
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(move.name). \(move.how)\(tried ? " Tried." : "")\(lit ? " Detected now." : "")")
    }
}

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
    @Binding var page: Page?
    @Environment(\.snapshot) private var snapshot

    /// Ignores ids saved by older versions so progress can't pass the total.
    private var tried: Set<String> { Set(triedRaw.split(separator: ",").map(String.init)).intersection(moves.map(\.id)) }

    var body: some View {
        let t = HandTracker.shared
        let active = litMoves(t.gesture, fingers: t.fingers)
        let done = tried

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    CameraCard(width: 360)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Learn the moves").font(.title2.weight(.semibold))
                        Text("Show each gesture to the camera. Its card lights up when Wave sees it.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ProgressView(value: Double(done.count), total: Double(moves.count)) {
                            Text("\(done.count) of \(moves.count) tried").monospacedDigit()
                        }
                        .frame(maxWidth: 260)
                        HStack {
                            if done.count >= moves.count {
                                Button("Try the Playground") { page = .playground }.buttonStyle(.borderedProminent)
                            }
                            if !done.isEmpty {
                                Button("Reset") { withAnimation(Theme.spring) { triedRaw = "" } }
                                    .accessibilityHint("Clears your progress")
                            }
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(moves) { m in
                        MoveCard(move: m, lit: active.contains(m.id), tried: done.contains(m.id))
                    }
                }
            }
            .padding(20)
        }
        .onChange(of: active) { _, now in
            guard !snapshot else { return }
            let merged = done.union(now)
            if merged != done { withAnimation(Theme.spring) { triedRaw = merged.sorted().joined(separator: ",") } }
        }
    }
}

private struct MoveCard: View {
    let move: Move, lit: Bool, tried: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(move.emoji).font(.system(size: 28)).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(move.name).font(.headline)
                Text(move.how).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if tried {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card(highlighted: lit)
        .animation(Theme.spring, value: lit)
        .animation(Theme.spring, value: tried)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(move.name). \(move.how)\(tried ? " Tried." : "")\(lit ? " Detected now." : "")")
    }
}

import SwiftUI

private struct Move: Identifiable {
    let id: String, emoji: String, name: String, how: String
    let gesture: Gesture?   // nil means a finger count
    let count: Int
}

private let moves: [Move] = [
    Move(id: "open", emoji: "👋", name: "Open palm", how: "Spread all five fingers, palm to the camera.", gesture: .open, count: 0),
    Move(id: "fist", emoji: "✊", name: "Fist", how: "Curl every finger into your palm.", gesture: .fist, count: 0),
    Move(id: "pinch", emoji: "🤏", name: "Pinch", how: "Touch your thumb tip to your index tip.", gesture: .pinch, count: 0),
    Move(id: "peace", emoji: "✌️", name: "Peace", how: "Raise index and middle, fold the rest.", gesture: .peace, count: 0),
    Move(id: "point", emoji: "☝️", name: "Point", how: "Raise only your index finger.", gesture: .point, count: 0),
    Move(id: "thumbsUp", emoji: "👍", name: "Thumbs up", how: "Fist with your thumb pointing up.", gesture: .thumbsUp, count: 0),
] + (1...5).map {
    Move(id: "n\($0)", emoji: "\($0)️⃣", name: $0 == 1 ? "One finger" : "\($0) fingers",
         how: "Hold up exactly \($0) finger\($0 == 1 ? "" : "s"), thumb included.", gesture: nil, count: $0)
}

struct LearnView: View {
    @AppStorage("learn.tried") private var triedRaw = ""

    private var tried: Set<String> { Set(triedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        let t = HandTracker.shared
        // fingers > 0 implies a hand is present; a fist has 0 fingers so it never lights a count card.
        let active = Set(moves.filter { m in m.gesture.map { $0 == t.gesture } ?? (t.fingers == m.count) }.map(\.id))
        let done = tried

        CameraStage { size in
            // Right sidebar only: the centre of the camera stays clear for the hand.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                panel(active: active, done: done)
                    .frame(width: 340)
                    .frame(maxHeight: max(size.height - 2 * Theme.pad, 0))
                    .padding(Theme.pad)
            }
        }
        .onChange(of: active) { _, now in
            let merged = done.union(now)
            if merged != done { withAnimation(Theme.spring) { triedRaw = merged.sorted().joined(separator: ",") } }
        }
    }

    private func panel(active: Set<String>, done: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Theme.title("Learn the moves")
                Theme.caption("Show each gesture to the camera. Cards light up when Wave sees it.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                progress(done.count)
                Spacer()
                Button("Reset") { withAnimation(Theme.spring) { triedRaw = "" } }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6)).opacity(done.isEmpty ? 0 : 1)
                    .accessibilityHint("Clears your progress")
            }
            if done.count >= moves.count { celebration }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(moves) { m in
                        MoveCard(move: m, lit: active.contains(m.id), tried: done.contains(m.id))
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(Theme.pad)
        .glass(corner: 28)
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
        Text("🎉 You're a natural. Try the Playground →")
            .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            .padding(12).frame(maxWidth: .infinity)
            .glass(corner: 16, highlighted: true)
            .phaseAnimator([1.0, 1.03]) { v, s in v.scaleEffect(s) } animation: { _ in .easeInOut(duration: 1.2) }
            .transition(.scale.combined(with: .opacity))
    }
}

private struct MoveCard: View {
    let move: Move, lit: Bool, tried: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            Text(move.emoji).font(.system(size: 40)).frame(width: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(move.name).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Theme.caption(move.how).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if tried {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                    .foregroundStyle(Theme.success).transition(.scale.combined(with: .opacity))
            }
        }
        .padding(12)
        .glass(corner: 18, highlighted: lit)
        .scaleEffect(lit ? 1.04 : hover ? 1.015 : 1)
        .animation(Theme.spring, value: lit)
        .animation(Theme.spring, value: hover)
        .animation(Theme.spring, value: tried)
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(move.name). \(move.how)\(tried ? " Tried." : "")\(lit ? " Detected now." : "")")
    }
}

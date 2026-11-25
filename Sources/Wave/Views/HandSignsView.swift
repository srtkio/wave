import SwiftUI

extension Sign {
    var how: String {
        switch self {
        case .thumbsUp: "A fist with the thumb pointing up."
        case .rock: "Index and little finger up, the others curled."
        case .callMe: "Thumb and little finger out, the others curled."
        case .peace: "Index and middle finger up."
        case .ok: "Thumb touches the index tip, other fingers up."
        case .l: "Thumb and index at a right angle."
        }
    }
}

/// A sign's emoji. L has no emoji (🇱 renders as a boxed placeholder), so it is drawn as a letter tile.
struct SignGlyph: View {
    let sign: Sign
    var size: CGFloat = 24

    var body: some View {
        if sign == .l {
            Text("L")
                .font(.system(size: size * 0.62, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size * 0.95, height: size * 0.95)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .accessibilityLabel("L")
        } else {
            Text(sign.emoji).font(.system(size: size))
        }
    }
}

struct HandSignsView: View {
    @Bindable private var signs = HandSigns.shared
    @State private var shortcuts: [String] = []
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $signs.enabled) {
                    Text("Hand signs")
                    Text("Hold a sign for \(String(format: "%g", Hold.hold)) s to run its action. A ring fills in the notch while you hold.")
                }
                .toggleStyle(.switch)
            }
            Section("Signs") {
                ForEach(Sign.allCases, id: \.self) { row($0) }
            }
            .disabled(!signs.enabled)
            Section {
                Text("Signs are paused while cursor mode is on. Actions that press keys need Accessibility.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // `shortcuts list` can take a second, so it's loaded once off the main thread.
        .task { if shortcuts.isEmpty, !snapshot { shortcuts = await Task.detached { Output.listShortcuts() }.value } }
    }

    private func row(_ sign: Sign) -> some View {
        let lit = signs.enabled && HandTracker.shared.handVisible && signs.held == sign
        let current = signs.actions[sign] ?? SignAction.none
        let binding = Binding(get: { current }, set: { signs.actions[sign] = $0 })
        // Keep the current shortcut selectable even before the list has loaded or if it was deleted.
        var names = shortcuts
        if case .shortcut(let n) = current, !names.contains(n) { names.insert(n, at: 0) }
        return HStack(spacing: 12) {
            SignGlyph(sign: sign).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(sign.title)
                    if lit {
                        Text("Seen now")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Theme.accent, in: Capsule())
                            .transition(.opacity)
                    }
                }
                Text(sign.how).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(sign.title, selection: binding) {
                ForEach(SignAction.basic, id: \.self) { Text($0.title).tag($0) }
                if !names.isEmpty {
                    Divider()
                    Section("Apple Shortcut") { ForEach(names, id: \.self) { Text($0).tag(SignAction.shortcut($0)) } }
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 2)
        .animation(.easeOut(duration: 0.15), value: lit)
        .accessibilityElement(children: .contain)
    }
}

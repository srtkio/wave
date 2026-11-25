import SwiftUI

/// Menu-bar dropdown section: master switch plus one action picker per sign. ~300 pt wide.
struct HandSignsMenu: View {
    @Bindable private var signs = HandSigns.shared
    private let tracker = HandTracker.shared
    @State private var shortcuts: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hand signs").font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Toggle("Hand signs", isOn: $signs.enabled)
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            ForEach(Sign.allCases, id: \.self) { row($0) }
            Text("Hold a sign for a moment to run its action.")
                .font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 300)
        .environment(\.colorScheme, .dark)
        .opacity(signs.enabled ? 1 : 0.6)
        // Loaded once off the main thread; `shortcuts list` can take a second.
        .task { if shortcuts.isEmpty { shortcuts = await Task.detached { Output.listShortcuts() }.value } }
    }

    private func row(_ sign: Sign) -> some View {
        let lit = signs.enabled && tracker.handVisible && signs.held == sign
        let current = signs.actions[sign] ?? SignAction.none
        let binding = Binding(get: { current }, set: { signs.actions[sign] = $0 })
        // Keep the current shortcut selectable even before the list has loaded or if it was deleted.
        var names = shortcuts
        if case .shortcut(let n) = current, !names.contains(n) { names.insert(n, at: 0) }
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 10) {
            Text(sign.emoji).font(.system(size: 26)).frame(width: 36)
            Text(sign.title).font(.system(size: 13, weight: .medium, design: .rounded))
            Spacer(minLength: 4)
            Picker(sign.title, selection: binding) {
                ForEach(SignAction.basic, id: \.self) { Text($0.title).tag($0) }
                if !names.isEmpty {
                    Divider()
                    Section("Apple Shortcut") { ForEach(names, id: \.self) { Text($0).tag(SignAction.shortcut($0)) } }
                }
            }
            .labelsHidden().pickerStyle(.menu).frame(width: 140)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(lit ? Theme.accent.opacity(0.18) : .white.opacity(0.06), in: shape)
        .overlay(shape.strokeBorder(lit ? Theme.accent : .clear, lineWidth: 1.5))
        .animation(.easeOut(duration: 0.12), value: lit)
        .accessibilityElement(children: .contain)
    }
}

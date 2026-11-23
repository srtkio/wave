import ApplicationServices
import Combine
import SwiftUI

struct ShortcutsView: View {
    var body: some View {
        Panel(symbol: "bolt.fill", title: "Shortcuts", caption: "Gestures that work in any app, on every tab.") {
            VStack(spacing: 10) {
                AccessibilityBanner()
                GrabCard()
                MacroList()
                ClipList()
            }
            .panelScroll()
        }
        .stageColumn()
    }
}

private struct AccessibilityBanner: View {
    @State private var trusted = AXIsProcessTrusted()
    @Environment(\.snapshot) private var snapshot
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !trusted {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 20)).foregroundStyle(Theme.gradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Theme.heading("Accessibility is off")
                        Theme.caption("Wave needs it to press keys.")
                    }
                    Spacer(minLength: 0)
                    Button("Allow") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    .help("Open Privacy & Security › Accessibility")
                    .buttonStyle(GlassButtonStyle(prominent: true))
                }
                .card()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: trusted)
        .onAppear { if !snapshot { Output.ensureAccessibility() }; trusted = AXIsProcessTrusted() }
        .onReceive(tick) { _ in trusted = AXIsProcessTrusted() }
    }
}

private struct GrabCard: View {
    @AppStorage(ShortcutEngine.grabKey) private var on = true

    var body: some View {
        let g = ShortcutEngine.shared.grab
        let (emoji, label, hint): (String, String, String) = switch g {
        case .ready: ("✋", "Ready", "Hold a fist for half a second to copy")
        case .grabbed: ("✊", "Grabbed", "Open your palm to paste")
        case .dropped: ("✓", "Dropped", "Pasted")
        }
        HStack(spacing: 14) {
            Text(emoji).font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(Circle().fill(g == .dropped ? Theme.success.opacity(0.35) : Theme.accent.opacity(g == .grabbed ? 0.35 : 0.12)))
                .scaleEffect(g == .grabbed ? 1.12 : 1)
                .id(g) // fresh view per state so the transition springs
                .transition(.scale.combined(with: .opacity))
            VStack(alignment: .leading, spacing: 2) {
                Theme.caption("Grab & drop")
                Text(on ? label : "Off").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Theme.caption(on ? hint : "Switched off").fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle("Grab and drop", isOn: $on).labelsHidden()
        }
        .card(highlighted: on && g != .ready)
        .animation(Theme.spring, value: g)
    }
}

private struct MacroList: View {
    @AppStorage(ShortcutEngine.macrosKey) private var on = true
    @State private var names: [String] = []
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Theme.heading("Finger macros")
                    Theme.caption("Hold up fingers to run a Shortcut")
                }
                Spacer()
                Toggle("Finger macros", isOn: $on).labelsHidden()
            }
            ForEach(1...5, id: \.self) { MacroRow(n: $0, names: names, enabled: on) }
        }
        .card()
        .task { if !snapshot { names = await Task.detached { Output.listShortcuts() }.value } }
    }
}

private struct MacroRow: View {
    let n: Int
    let names: [String]
    let enabled: Bool
    @AppStorage private var name: String

    init(n: Int, names: [String], enabled: Bool) {
        self.n = n; self.names = names; self.enabled = enabled
        _name = AppStorage(wrappedValue: "", ShortcutEngine.macroKey(n))
    }

    var body: some View {
        let e = ShortcutEngine.shared
        let active = enabled && e.heldCount == n
        let ring = active ? e.progress : 0
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                Circle().trim(from: 0, to: ring)
                    .stroke(e.fired && active ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Theme.gradient),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: ring)
                Text("\(n)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            HStack(spacing: 1) { ForEach(0..<n, id: \.self) { _ in Image(systemName: "hand.point.up.fill").font(.system(size: 10)) } }
                .foregroundStyle(active ? Theme.accent : .white.opacity(0.5)).frame(width: 56, alignment: .leading)
                .accessibilityHidden(true)
            Picker("Shortcut for \(n) finger\(n == 1 ? "" : "s")", selection: $name) {
                Text("None").tag("")
                ForEach(name.isEmpty || names.contains(name) ? names : [name] + names, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().disabled(!enabled)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(active ? 0.22 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.gradient, lineWidth: active ? 1.5 : 0))
        .scaleEffect(active ? 1.02 : 1)
        .animation(Theme.spring, value: active)
    }
}

/// One line per item, newest first. Moving the pinched hand right selects further down the list.
private struct ClipList: View {
    @AppStorage(ShortcutEngine.clipKey) private var on = true

    var body: some View {
        let e = ShortcutEngine.shared
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Theme.heading("Clipboard history")
                    Theme.caption(e.historyOpen ? "Move left or right, release to paste" : "Pinch and hold, then move your hand")
                }
                Spacer()
                Toggle("Clipboard history", isOn: $on).labelsHidden()
            }
            if e.items.isEmpty {
                Theme.caption("Copy some text and it shows up here. Kept in memory only.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(e.items.enumerated()), id: \.offset) { i, s in
                    let sel = e.historyOpen && e.selected == i
                    Text(oneLine(s))
                        .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(sel ? AnyShapeStyle(Theme.accent.opacity(0.25)) : AnyShapeStyle(.white.opacity(0.06))))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.gradient, lineWidth: sel ? 1.5 : 0))
                        .scaleEffect(sel ? 1.03 : 1)
                        .zIndex(sel ? 1 : 0)
                }
                .animation(Theme.spring, value: e.selected)
                .animation(Theme.spring, value: e.historyOpen)
            }
        }
        .card()
        .opacity(on ? 1 : 0.6)
    }

    private func oneLine(_ s: String) -> String {
        let flat = s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > 40 ? flat.prefix(40).trimmingCharacters(in: .whitespaces) + "…" : flat
    }
}

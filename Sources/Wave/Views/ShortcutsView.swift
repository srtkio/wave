import ApplicationServices
import Combine
import SwiftUI

struct ShortcutsView: View {
    var body: some View {
        CameraStage { _ in
            VStack(alignment: .leading, spacing: 14) {
                AccessibilityBanner()
                GrabCard()
                MacroList()
                Spacer(minLength: 0)
                ClipStrip()
            }
            .padding(.top, 52).padding([.horizontal, .bottom], Theme.pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { ShortcutEngine.shared.start() }
    }
}

private struct AccessibilityBanner: View {
    @State private var trusted = AXIsProcessTrusted()
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !trusted {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(Theme.accent2)
                    Theme.caption("Wave needs Accessibility to press keys.")
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }.buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glass(corner: 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: trusted)
        .onAppear { Output.ensureAccessibility(); trusted = AXIsProcessTrusted() }
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
        HStack(spacing: 16) {
            Text(emoji).font(.system(size: 40))
                .frame(width: 64, height: 64)
                .background(Circle().fill(g == .dropped ? Theme.success.opacity(0.35) : Theme.accent.opacity(g == .grabbed ? 0.35 : 0.12)))
                .scaleEffect(g == .grabbed ? 1.12 : 1)
                .id(g) // fresh view per state so the transition springs
                .transition(.scale.combined(with: .opacity))
            VStack(alignment: .leading, spacing: 3) {
                Text("Grab & drop").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                Text(on ? label : "Off").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Theme.caption(on ? hint : "Switched off")
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $on).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
        }
        .padding(14).frame(width: 380)
        .glass(highlighted: on && g != .ready)
        .animation(Theme.spring, value: g)
    }
}

private struct MacroList: View {
    @AppStorage(ShortcutEngine.macrosKey) private var on = true
    @State private var names: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Finger macros").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                Toggle("", isOn: $on).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
            }
            ForEach(1...5, id: \.self) { MacroRow(n: $0, names: names, enabled: on) }
        }
        .padding(14).frame(width: 380).glass()
        .task { names = await Task.detached { Output.listShortcuts() }.value }
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
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                Circle().trim(from: 0, to: ring)
                    .stroke(e.fired && active ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Theme.gradient),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: ring)
                Text("\(n)").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            HStack(spacing: 2) { ForEach(0..<n, id: \.self) { _ in Image(systemName: "hand.point.up.fill").font(.system(size: 10)) } }
                .foregroundStyle(active ? Theme.accent : .white.opacity(0.4)).frame(width: 60, alignment: .leading)
            Picker("", selection: $name) {
                Text("None").tag("")
                ForEach(name.isEmpty || names.contains(name) ? names : [name] + names, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().disabled(!enabled)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent.opacity(active ? 0.22 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.gradient, lineWidth: active ? 1.5 : 0))
        .scaleEffect(active ? 1.02 : 1)
        .animation(Theme.spring, value: active)
    }
}

private struct ClipStrip: View {
    @AppStorage(ShortcutEngine.clipKey) private var on = true

    var body: some View {
        let e = ShortcutEngine.shared
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Clipboard history").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Theme.caption(e.historyOpen ? "Move left or right, release to paste" : "Pinch and hold, then move your hand")
                Spacer()
                Toggle("", isOn: $on).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
            }
            if e.items.isEmpty {
                Theme.caption("Copy some text and it shows up here. Kept in memory only.")
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(e.items.enumerated()), id: \.offset) { i, s in
                        let sel = e.historyOpen && e.selected == i
                        Text(s.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white)
                            .lineLimit(2).frame(width: 150, height: 44, alignment: .leading)
                            .padding(10)
                            .glass(corner: 16, highlighted: sel)
                            .shadow(color: sel ? Theme.accent.opacity(0.8) : .clear, radius: 16)
                            .scaleEffect(sel ? 1.12 : 1)
                            .zIndex(sel ? 1 : 0)
                    }
                }
                .animation(Theme.spring, value: e.selected)
                .animation(Theme.spring, value: e.historyOpen)
            }
        }
        .padding(14).glass().opacity(on ? 1 : 0.6)
    }
}

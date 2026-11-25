import ApplicationServices
import AVFoundation
import SwiftUI

/// Two columns when there is room (camera left, everything else right), one column in a narrow window.
struct HomeView: View {
    @Binding var page: Page?
    let onFullscreen: () -> Void
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 20) { camera(width: 480) }.frame(width: 506)
                    VStack(spacing: 20) { power; Permissions(); activity }.frame(minWidth: 320, maxWidth: 520)
                }
                VStack(spacing: 20) { power; camera(width: nil); Permissions(); activity }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .task { if !snapshot { await ActivityFeed.shared.follow() } }
    }

    private var power: some View {
        let t = HandTracker.shared
        return HStack(spacing: 12) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(t.running ? Theme.accent : Color.secondary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(t.running ? "Wave is on" : "Wave is off").font(.title3.weight(.semibold))
                Text(waveStatus(t)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Wave", isOn: Binding(get: { t.running }, set: { $0 ? t.start() : t.stop() }))
                .toggleStyle(.switch).controlSize(.large).labelsHidden()
        }
        .card()
    }

    private func camera(width: CGFloat?) -> some View {
        Box("Camera") {
            CameraCard(width: width, onFullscreen: onFullscreen).frame(maxWidth: 480)
            WhatWaveSees()
        }
    }

    private var activity: some View {
        let recent = ActivityFeed.shared.recent(6)
        return Box("Recent activity", trailing: Button("Show Log") { page = .log }.buttonStyle(.link)) {
            if recent.isEmpty {
                Text("Nothing yet. What Wave does with your hands shows up here.").foregroundStyle(.secondary)
            }
            ForEach(Array(recent.enumerated()), id: \.offset) { i, e in
                if i > 0 { Divider() }
                HStack(spacing: 12) {
                    Text(e.time).monospacedDigit().foregroundStyle(.secondary)
                    Text(e.text).lineLimit(1)
                }
            }
        }
    }
}

extension Box where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, trailing: EmptyView(), content: content)
    }
}

/// A titled platter, the same look as a grouped-form section.
private struct Box<Content: View, Trailing: View>: View {
    let title: String
    let trailing: Trailing
    @ViewBuilder let content: Content

    init(_ title: String, trailing: Trailing, @ViewBuilder content: () -> Content) {
        self.title = title; self.trailing = trailing; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                trailing
            }
            .padding(.horizontal, 10)
            VStack(alignment: .leading, spacing: 10) { content }.card()
        }
    }
}

private struct WhatWaveSees: View {
    var body: some View {
        let t = HandTracker.shared
        let counts = ActivityFeed.shared.handCounts
        VStack(alignment: .leading, spacing: 8) {
            Text("What Wave sees").font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Gesture").foregroundStyle(.secondary)
                    if t.handVisible { Label(t.gesture.title, systemImage: t.gesture.symbol) } else { Text("No hand") }
                }
                GridRow {
                    Text("Hands").foregroundStyle(.secondary)
                    Text(!t.running ? "–" : counts.map { "\($0.kept) in use, \($0.ignored) ignored as too far away" } ?? "\(t.frame.hands.count) in use")
                        .monospacedDigit()
                }
                GridRow {
                    Text("Hand sign").foregroundStyle(.secondary)
                    if let s = HandSigns.shared.held { HStack(spacing: 6) { SignGlyph(sign: s, size: 15); Text(s.title) } } else { Text("None") }
                }
                GridRow {
                    Text("Cursor").foregroundStyle(.secondary)
                    Text(cursorStateTitle())
                }
            }
        }
        .padding(.top, 4)
    }
}

/// Camera and Accessibility, each with a tick or a way to fix it. Checked every 2 s while shown; never prompts.
private struct Permissions: View {
    @State private var camera = false
    @State private var accessibility = false

    var body: some View {
        Box("Permissions") {
            row("Camera", "Sees your hands. Video stays on this Mac.", ok: camera, pane: "Privacy_Camera")
            Divider()
            row("Accessibility", "Lets Wave move the pointer and press keys.", ok: accessibility, pane: "Privacy_Accessibility")
        }
        .task {
            while !Task.isCancelled {
                camera = HandTracker.shared.authorized == true || AVCaptureDevice.authorizationStatus(for: .video) == .authorized
                accessibility = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func row(_ title: String, _ detail: String, ok: Bool, pane: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if ok {
                Text("Allowed").foregroundStyle(.secondary)
            } else {
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

import AVFoundation
import SwiftUI

struct CameraPreview: NSViewRepresentable {
    /// Passed in so a change re-runs updateNSView: the layer's connection only exists once the session is configured.
    var authorized: Bool?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: HandTracker.shared.session)
        layer.videoGravity = .resizeAspectFill
        layer.masksToBounds = true
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let c = (view.layer as? AVCaptureVideoPreviewLayer)?.connection, c.isVideoMirroringSupported else { return }
        c.automaticallyAdjustsVideoMirroring = false
        c.isVideoMirrored = true
    }
}

private let bones: [[Joint]] = [
    [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
    [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
    [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
    [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
    [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
]

struct HandOverlay: View {
    var body: some View {
        // Read outside the Canvas closure so Observation tracks it.
        let hands = HandTracker.shared.frame.hands
        Canvas { ctx, size in
            for hand in hands {
                for chain in bones {
                    var path = Path()
                    path.addLines(chain.compactMap { hand.points[$0] }.map { viewPoint($0, in: size) })
                    ctx.stroke(path, with: .color(.white.opacity(0.65)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                for p in hand.points.values {
                    let v = viewPoint(p, in: size)
                    ctx.fill(Path(ellipseIn: CGRect(x: v.x - 6, y: v.y - 6, width: 12, height: 12)), with: .color(Theme.accent.opacity(0.35)))
                    ctx.fill(Path(ellipseIn: CGRect(x: v.x - 3.5, y: v.y - 3.5, width: 7, height: 7)), with: .color(.white))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

extension EnvironmentValues {
    /// True while `--snapshot` renders: no camera, no system prompts, no clipboard reads.
    @Entry var snapshot = false
}

/// The shared stage behind every tab: camera, hand skeleton, gesture badge, hints and the camera-denied card.
struct CameraStage<Content: View>: View {
    let content: (CGSize) -> Content
    @Environment(\.snapshot) private var snapshot

    init(@ViewBuilder _ content: @escaping (CGSize) -> Content) {
        self.content = content
    }

    var body: some View {
        let authorized = HandTracker.shared.authorized
        GeometryReader { geo in
            ZStack {
                if snapshot { Backdrop() } else { Color.black; CameraPreview(authorized: authorized) }
                HandOverlay()
                Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) // no title bar, so drag the camera
                if authorized == false {
                    CameraDeniedCard()
                } else {
                    content(geo.size)
                    if authorized == true { NoHandHint() }
                }
            }
            .overlay(alignment: .topLeading) {
                if authorized != false { GestureBadge().padding(.top, Theme.insets.top).padding(.leading, Theme.insets.leading) }
            }
        }
        .clipped()
    }
}

/// Dark stand-in for the camera in `--snapshot`: a dim room with a warm lamp and a cool window.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.55, green: 0.38, blue: 0.22).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.18, y: 0.3), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(red: 0.25, green: 0.4, blue: 0.6).opacity(0.5), .clear],
                           center: UnitPoint(x: 0.85, y: 0.15), startRadius: 0, endRadius: 600)
        }
    }
}

extension Gesture {
    var title: String {
        switch self {
        case .none: "Hand"
        case .open: "Open palm"
        case .fist: "Fist"
        case .pinch: "Pinch"
        case .peace: "Peace"
        case .point: "Point"
        case .thumbsUp: "Thumbs up"
        }
    }
    var symbol: String {
        switch self {
        case .open: "hand.raised.fingers.spread.fill"
        case .pinch: "hand.pinch.fill"
        case .point: "hand.point.up.fill"
        case .thumbsUp: "hand.thumbsup.fill"
        case .none, .fist, .peace: "hand.raised.fill" // SF Symbols has no fist or peace hand
        }
    }
}

/// Separate view so gesture changes don't re-evaluate the tab's content.
private struct GestureBadge: View {
    var body: some View {
        let t = HandTracker.shared
        let seen = t.handVisible
        HStack(spacing: 8) {
            Image(systemName: seen ? t.gesture.symbol : "hand.raised.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(seen ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.white.opacity(0.5)))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18)
            Text(seen ? t.gesture.title : "No hand")
                .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            if seen {
                Text("· \(t.fingers) finger\(t.fingers == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glass(corner: 17)
        .animation(Theme.spring, value: t.gesture)
        .animation(Theme.spring, value: t.fingers)
        .animation(Theme.spring, value: seen)
        .accessibilityElement(children: .combine)
    }
}

/// "Raise a hand" after two seconds without one, breathing gently until a hand shows up.
private struct NoHandHint: View {
    @State private var show = false

    var body: some View {
        let seen = HandTracker.shared.handVisible
        ZStack {
            if show {
                Text("Raise a hand ✋")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .glass(corner: 20)
                    .phaseAnimator([1.0, 0.6]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 1.6) }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, Theme.insets.bottom)
        .allowsHitTesting(false)
        .task(id: seen) {
            if seen { withAnimation(.easeOut(duration: 0.3)) { show = false }; return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.6)) { show = true } }
        }
    }
}

private struct CameraDeniedCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(Theme.gradient, in: Circle())
                .shadow(color: Theme.accent.opacity(0.5), radius: 16)
            Theme.title("Wave needs your camera")
            Text("Wave watches your hands to turn gestures into actions. Everything runs on this Mac. Video is never recorded or uploaded.")
                .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button("Open Camera Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
            .padding(.top, 4)
            Theme.caption("Turn on Wave there, then reopen the app.")
        }
        .padding(32)
        .frame(width: 440)
        .glass()
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

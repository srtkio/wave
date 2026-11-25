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

/// Hand skeleton and face landmark dots, drawn over the camera.
struct HandOverlay: View {
    var body: some View {
        // Read outside the Canvas closure so Observation tracks it.
        let frame = HandTracker.shared.frame
        Canvas { ctx, size in
            let r: CGFloat = size.width > 700 ? 4 : 3
            for p in frame.faceLandmarks {
                let v = viewPoint(p, in: size)
                ctx.fill(Path(ellipseIn: CGRect(x: v.x - 1.5, y: v.y - 1.5, width: 3, height: 3)), with: .color(.white.opacity(0.7)))
            }
            for hand in frame.hands {
                for chain in bones {
                    var path = Path()
                    path.addLines(chain.compactMap { hand.points[$0] }.map { viewPoint($0, in: size) })
                    ctx.stroke(path, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                for p in hand.points.values {
                    let v = viewPoint(p, in: size)
                    ctx.fill(Path(ellipseIn: CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)), with: .color(.white))
                    ctx.fill(Path(ellipseIn: CGRect(x: v.x - r + 1, y: v.y - r + 1, width: 2 * r - 2, height: 2 * r - 2)), with: .color(Theme.accent))
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

/// The live camera with the hand skeleton, plus a quiet message when Wave is off or the camera is blocked.
/// Fills whatever frame it is given; use `CameraCard` for the usual small 16:9 version.
struct CameraStage<Content: View>: View {
    let content: (CGSize) -> Content
    @Environment(\.snapshot) private var snapshot

    init(@ViewBuilder _ content: @escaping (CGSize) -> Content) {
        self.content = content
    }

    var body: some View {
        let t = HandTracker.shared
        GeometryReader { geo in
            ZStack {
                if snapshot {
                    // Neutral stand-in for the camera; dark in both themes because a camera feed isn't themed.
                    LinearGradient(colors: [Color(white: 0.32), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
                } else {
                    Color.black
                    CameraPreview(authorized: t.authorized)
                }
                if !t.running {
                    CameraMessage(symbol: "video.slash", title: "Camera off", detail: "Turn Wave on to start the camera.")
                } else if t.authorized == false {
                    CameraMessage(symbol: "video.slash", title: "No camera access", detail: "Allow Wave under Privacy & Security → Camera.")
                } else {
                    HandOverlay()
                    content(geo.size)
                }
            }
        }
        .clipped()
        // Face dots should show whenever the camera is on screen, not only while a face feature is on.
        .onAppear { t.visibleCameras += 1 }
        .onDisappear { t.visibleCameras -= 1 }
    }
}

private struct CameraMessage: View {
    let symbol: String, title: String, detail: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding()
    }
}

/// The camera at a modest 16:9 size with rounded corners, and an optional fullscreen button.
struct CameraCard<Overlay: View>: View {
    var width: CGFloat? = nil
    var onFullscreen: (() -> Void)? = nil
    @ViewBuilder var overlay: Overlay

    var body: some View {
        CameraStage { _ in overlay }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .overlay(alignment: .topTrailing) {
                if let onFullscreen {
                    Button(action: onFullscreen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Full screen")
                    .accessibilityLabel("Full screen camera")
                }
            }
    }
}

extension CameraCard where Overlay == EmptyView {
    init(width: CGFloat? = nil, onFullscreen: (() -> Void)? = nil) {
        self.init(width: width, onFullscreen: onFullscreen) { EmptyView() }
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

/// What the camera sees, as a small dark capsule for the large camera views.
struct GestureBadge: View {
    var body: some View {
        let t = HandTracker.shared
        let seen = t.handVisible
        Label(seen ? t.gesture.title : "No hand", systemImage: seen ? t.gesture.symbol : "hand.raised.slash")
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.5), in: Capsule())
            .contentTransition(.symbolEffect(.replace))
            .animation(Theme.spring, value: t.gesture)
            .accessibilityElement(children: .combine)
    }
}

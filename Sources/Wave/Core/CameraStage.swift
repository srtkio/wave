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
                    ctx.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 2)
                }
                for p in hand.points.values {
                    let v = viewPoint(p, in: size)
                    ctx.fill(Path(ellipseIn: CGRect(x: v.x - 4, y: v.y - 4, width: 8, height: 8)), with: .color(.green))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct CameraStage<Content: View>: View {
    let content: (CGSize) -> Content

    init(@ViewBuilder _ content: @escaping (CGSize) -> Content) {
        self.content = content
    }

    var body: some View {
        let authorized = HandTracker.shared.authorized
        GeometryReader { geo in
            ZStack {
                Color.black
                CameraPreview(authorized: authorized)
                HandOverlay()
                content(geo.size)
                if authorized == false {
                    Text("Wave needs the camera to see your hands.\nAllow it in System Settings → Privacy & Security → Camera, then reopen Wave.")
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .overlay(alignment: .topLeading) { GestureBadge().padding(12) }
        }
        .clipped()
    }
}

/// Separate view so gesture changes don't re-evaluate the tab's content.
private struct GestureBadge: View {
    var body: some View {
        let t = HandTracker.shared
        Text("\(t.gesture.rawValue) · \(t.fingers) fingers")
            .font(.callout.monospaced())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

import CoreGraphics
import CoreVideo
import Vision

typealias Joint = VNHumanHandPoseObservation.JointName

/// One detected hand. Points are normalised 0–1, origin top-left, mirrored like a selfie.
/// Only joints with confidence > 0.3 are present.
struct Hand {
    var points: [Joint: CGPoint]
    var chirality: VNChirality
}

struct HandFrame {
    var hands: [Hand] = []
    /// First detected face, same coordinate space as `Hand.points`. Only set while `HandTracker.detectFaces` is true.
    var face: CGRect? = nil
    /// Raw sensor image: NOT mirrored, Vision space (bottom-left origin). Convert a rect `f` back with
    /// `CGRect(x: 1 - f.maxX, y: 1 - f.maxY, width: f.width, height: f.height)` (its own inverse).
    var pixelBuffer: CVPixelBuffer? = nil
    var time: TimeInterval = 0
}

/// Maps a normalised point into a view of `size` showing the 16:9 camera with resizeAspectFill.
func viewPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
    let scale = max(size.width / 16, size.height / 9)
    let w = 16 * scale, h = 9 * scale
    return CGPoint(x: p.x * w - (w - size.width) / 2, y: p.y * h - (h - size.height) / 2)
}

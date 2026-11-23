import AVFoundation
import Observation
import Vision

@Observable
final class HandTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = HandTracker()

    // Main-thread state.
    var frame = HandFrame()
    /// Stable gesture of the first hand.
    var gesture: Gesture = .none
    /// Extended finger count of the first hand.
    var fingers = 0
    /// At least one hand in the latest frame. Changes far less often than `frame`, so cheap to observe.
    var handVisible = false
    /// nil until `start()` has asked; true once the session is configured.
    var authorized: Bool?
    var detectFaces = false
    var gesturesAllowed = true

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.srtkio.wave.camera")
    @ObservationIgnored private let handRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    @ObservationIgnored private let faceRequest = VNDetectFaceRectanglesRequest()
    @ObservationIgnored private var stabilizer = GestureStabilizer() // camera queue only
    @ObservationIgnored private var configured = false // camera queue only
    @ObservationIgnored private var listeners: [UUID: (HandFrame, Gesture) -> Void] = [:]
    @ObservationIgnored private var anyListeners: [UUID: (HandFrame, Gesture) -> Void] = [:]

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else {
                DispatchQueue.main.async { self.authorized = false }
                return
            }
            self.queue.async {
                self.configure()
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.authorized = true }
            }
        }
    }

    /// Called on main every frame while `gesturesAllowed` is true.
    @discardableResult func onFrame(_ f: @escaping (HandFrame, Gesture) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = f
        return id
    }

    /// Called on main every frame, even while gestures are blocked.
    @discardableResult func onAnyFrame(_ f: @escaping (HandFrame, Gesture) -> Void) -> UUID {
        let id = UUID()
        anyListeners[id] = f
        return id
    }

    func removeListener(_ id: UUID) {
        listeners[id] = nil
        anyListeners[id] = nil
    }

    private func configure() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let wantFaces = detectFaces
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform(wantFaces ? [handRequest, faceRequest] : [handRequest])

        let hands = (handRequest.results ?? []).map { obs -> Hand in
            var points: [Joint: CGPoint] = [:]
            for (joint, p) in (try? obs.recognizedPoints(.all)) ?? [:] where p.confidence > 0.3 {
                points[joint] = CGPoint(x: 1 - p.location.x, y: 1 - p.location.y)
            }
            return Hand(points: points, chirality: obs.chirality)
        }
        var face: CGRect?
        if wantFaces, let b = faceRequest.results?.first?.boundingBox {
            face = CGRect(x: 1 - b.maxX, y: 1 - b.maxY, width: b.width, height: b.height)
        }
        let frame = HandFrame(hands: hands, face: face, pixelBuffer: pixelBuffer,
                              time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
        // Feed .none when no hand so the stable gesture clears and features see the release.
        let gesture = stabilizer.update(hands.first.map(classify) ?? .none)
        let fingers = hands.first.map(fingerCount) ?? 0

        DispatchQueue.main.async {
            self.frame = frame
            // Only write on change so views reading these don't re-render every frame.
            if self.gesture != gesture { self.gesture = gesture }
            if self.fingers != fingers { self.fingers = fingers }
            if self.handVisible == hands.isEmpty { self.handVisible = !hands.isEmpty }
            for l in self.anyListeners.values { l(frame, gesture) }
            if self.gesturesAllowed { for l in self.listeners.values { l(frame, gesture) } }
        }
    }
}

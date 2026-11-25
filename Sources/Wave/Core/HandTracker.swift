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
    /// Wave is on: the camera runs and gestures are read. Toggled from the menu bar.
    var running = false
    /// Cursor mode owns the hand while true; hand signs and other gesture actions stay quiet.
    var cursorActive = false
    var detectFaces = false
    /// Camera views on screen; while any are, faces are detected too so the overlay can draw face dots.
    @ObservationIgnored var visibleCameras = 0
    var gesturesAllowed = true

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.srtkio.wave.camera")
    @ObservationIgnored private let handRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    // Landmarks request also detects the face, so one request gives rect, landmarks and roll.
    @ObservationIgnored private let faceRequest = VNDetectFaceLandmarksRequest()
    @ObservationIgnored private var faceInfo = FaceInfo() // camera queue only
    @ObservationIgnored private var faceTime = -1.0
    @ObservationIgnored private var stabilizer = GestureStabilizer() // camera queue only
    @ObservationIgnored private var configured = false // camera queue only
    @ObservationIgnored private var listeners: [UUID: (HandFrame, Gesture) -> Void] = [:]
    @ObservationIgnored private var seenCount = 0 // main only, for the session log
    @ObservationIgnored private var keptCount = 0
    @ObservationIgnored private var anyListeners: [UUID: (HandFrame, Gesture) -> Void] = [:]

    func start() {
        guard !running else { return }
        running = true
        SessionLog.begin()
        NotchHUD.shared.flash("Wave on")
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

    /// Turns the camera off and clears what was seen.
    func stop() {
        guard running else { return }
        running = false
        SessionLog.log("Wave off")
        CursorMode.shared.stop()
        queue.async {
            self.session.stopRunning()
            self.stabilizer = GestureStabilizer()
            self.faceInfo = FaceInfo(); self.faceTime = -1
        }
        frame = HandFrame(); gesture = .none; fingers = 0; handVisible = false
        NotchHUD.shared.flash("Wave off", symbol: "hand.raised.slash")
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
        let wantFaces = detectFaces || visibleCameras > 0
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        // shortcut: faces at 10 Hz; landmarks are the costly request and the face barely moves in 0.1 s.
        let readFace = wantFaces && (t - faceTime >= 0.1 || t < faceTime)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform(readFace ? [handRequest, faceRequest] : [handRequest])
        if readFace {
            faceTime = t
            faceInfo = Self.readFace(faceRequest.results,
                                     CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)))
        } else if !wantFaces { faceInfo = FaceInfo() }

        let all = (handRequest.results ?? []).map { obs -> Hand in
            var points: [Joint: CGPoint] = [:]
            for (joint, p) in (try? obs.recognizedPoints(.all)) ?? [:] where p.confidence > 0.3 {
                points[joint] = CGPoint(x: 1 - p.location.x, y: 1 - p.location.y)
            }
            return Hand(points: points, chirality: obs.chirality)
        }
        let hands = primaryHands(all)
        let fi = faceInfo
        let frame = HandFrame(hands: hands, face: fi.rect, faceLandmarks: fi.landmarks, faceCount: fi.count, faceRoll: fi.roll,
                              pixelBuffer: pixelBuffer, time: t)
        // Feed .none when no hand so the stable gesture clears and features see the release.
        let gesture = stabilizer.update(hands.first.map(classify) ?? .none)
        let fingers = hands.first.map(fingerCount) ?? 0

        DispatchQueue.main.async {
            self.frame = frame
            // Only write on change so views reading these don't re-render every frame.
            guard self.running else { return } // a frame that was in flight when stop() ran
            if all.count != self.seenCount || hands.count != self.keptCount {
                self.seenCount = all.count; self.keptCount = hands.count
                let palms = all.map { String(format: "%.3f", palmSize($0)) }.joined(separator: ",")
                SessionLog.log("hands seen=\(all.count) kept=\(hands.count) palms=[\(palms)] (min \(minPalmSize))")
            }
            if self.gesture != gesture {
                self.gesture = gesture
                SessionLog.log("gesture \(gesture.rawValue) fingers=\(fingers)\(hands.first.map { String(format: " palm=%.3f", palmSize($0)) } ?? "")")
            }
            if self.fingers != fingers { self.fingers = fingers }
            if self.handVisible == hands.isEmpty { self.handVisible = !hands.isEmpty }
            for l in self.anyListeners.values { l(frame, gesture) }
            if self.gesturesAllowed { for l in self.listeners.values { l(frame, gesture) } }
        }
    }
}

struct FaceInfo {
    var rect: CGRect?
    var landmarks: [CGPoint] = []
    var count = 0
    var roll: CGFloat = 0
}

extension HandTracker {
    /// Largest face wins (people behind you are smaller). Landmarks are normalised to the face box, so map them through it.
    fileprivate static func readFace(_ results: [VNFaceObservation]?, _ px: CGSize) -> FaceInfo {
        guard let faces = results,
              let best = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
        else { return FaceInfo() }
        let b = best.boundingBox
        var info = FaceInfo(rect: CGRect(x: 1 - b.maxX, y: 1 - b.maxY, width: b.width, height: b.height), count: faces.count)
        guard let lm = best.landmarks else { return info }
        func toImage(_ p: CGPoint) -> CGPoint { CGPoint(x: b.minX + p.x * b.width, y: b.minY + p.y * b.height) } // Vision space
        func centre(_ ps: [CGPoint]) -> CGPoint {
            let n = CGFloat(ps.count)
            return toImage(CGPoint(x: ps.reduce(0) { $0 + $1.x } / n, y: ps.reduce(0) { $0 + $1.y } / n))
        }
        info.landmarks = (lm.allPoints?.normalizedPoints ?? []).map { let p = toImage($0); return CGPoint(x: 1 - p.x, y: 1 - p.y) }
        if let l = lm.leftEye?.normalizedPoints, let r = lm.rightEye?.normalizedPoints, !l.isEmpty, !r.isEmpty {
            info.roll = FacePrint.eyeRoll(centre(l), centre(r), pixels: px)
        }
        return info
    }
}

/// Wrist to middle knuckle, in normalised frame units. Bigger = closer to the camera.
func palmSize(_ h: Hand) -> CGFloat {
    guard let w = h.points[.wrist], let m = h.points[.middleMCP] else { return 0 }
    return hypot(w.x - m.x, w.y - m.y)
}

// shortcut: fixed size cut-off from geometry (~0.15 at laptop distance, ~0.05 two metres back); tune on hardware.
let minPalmSize: CGFloat = 0.08

/// Drops far-away hands (people behind you) and puts the closest hand first.
func primaryHands(_ hands: [Hand]) -> [Hand] {
    hands.filter { palmSize($0) >= minPalmSize }.sorted { palmSize($0) > palmSize($1) }
}


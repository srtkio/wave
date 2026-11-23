import CoreImage
import Vision

// This is a convenience check, not security: Vision feature prints are a general image
// fingerprint, so a photo or a lookalike can pass. It only stops gestures firing for the wrong person.

/// Face crop + feature print helpers. Plain functions so they can run off the main thread.
enum FacePrint {
    /// shortcut: not calibrated against real faces, so it's a guess; the live "distance/limit" in the status
    /// line shows the real numbers, tune `floor` and the 1.5 factor from those.
    static let floor: Float = 0.5
    static func threshold(intraMax: Float) -> Float { max(intraMax * 1.5, floor) }

    private static let ci = CIContext()

    /// Padded face crop from the unmirrored sensor image. Needs the mirrored->Vision rect conversion from CORE_API.md.
    static func crop(_ pb: CVPixelBuffer?, _ face: CGRect) -> CGImage? {
        guard let pb else { return nil }
        let v = CGRect(x: 1 - face.maxX, y: 1 - face.maxY, width: face.width, height: face.height)
            .insetBy(dx: -face.width * 0.15, dy: -face.height * 0.15)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let w = CGFloat(CVPixelBufferGetWidth(pb)), h = CGFloat(CVPixelBufferGetHeight(pb))
        let r = CGRect(x: v.minX * w, y: v.minY * h, width: v.width * w, height: v.height * h)
        guard !r.isEmpty else { return nil }
        // Rendered now so nothing keeps the camera buffer alive after the callback returns.
        return ci.createCGImage(CIImage(cvPixelBuffer: pb), from: r)
    }

    static func makePrint(_ cg: CGImage) -> VNFeaturePrintObservation? {
        let r = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([r])
        return r.results?.first
    }

    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var d: Float = 0
        return (try? a.computeDistance(&d, to: b)) == nil ? nil : d
    }

    /// Smallest distance from this crop to any registered print.
    static func nearest(_ cg: CGImage, _ known: [VNFeaturePrintObservation]) -> Float? {
        guard let p = makePrint(cg) else { return nil }
        return known.compactMap { distance(p, $0) }.min()
    }

    static func intraMax(_ ps: [VNFeaturePrintObservation]) -> Float {
        var m: Float = 0
        for i in ps.indices { for j in ps.indices where j > i { m = max(m, distance(ps[i], ps[j]) ?? 0) } }
        return m
    }

    static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Wave")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "face.prints")
    }

    static func save(_ ps: [VNFeaturePrintObservation]) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: ps, requiringSecureCoding: true) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func load() -> [VNFeaturePrintObservation] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: VNFeaturePrintObservation.self, from: data)) ?? []
    }
}

/// Gestures only work while the registered face is in front of the camera.
final class FaceCheck: FeatureBase {
    private var prints: [VNFeaturePrintObservation] = []
    private var limit: Float = 0
    private var shots: [CGImage] = []
    private var lastShot = 0.0, lastCheck = 0.0
    private var registering = false, checking = false
    private var countdown: Task<Void, Never>?

    init() {
        super.init(key: "feature.face", symbol: "faceid", name: "Face verification",
                   blurb: "Gestures only work when it's you in front of the camera.")
    }

    override func begin() {
        prints = FacePrint.load()
        limit = FacePrint.threshold(intraMax: FacePrint.intraMax(prints))
        idle = prints.isEmpty ? "Register your face to start" : "Checking…"
        live = false
        action = prints.isEmpty ? "Register my face" : "Re-register"
        lastCheck = 0
        listen(always: true) { [weak self] f, _ in self?.tick(f) }
    }

    override func end() {
        countdown?.cancel()
        registering = false; shots = []
        HandTracker.shared.gesturesAllowed = true
    }

    override func act() {
        guard running, !busy else { return }
        busy = true
        HandTracker.shared.gesturesAllowed = true // never lock the user out mid-registration
        live = false
        status = "Look at the camera, turn a little between shots"
        countdown = Task {
            for n in (1...3).reversed() {
                banner = "\(n)"
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            shots = []; lastShot = 0
            banner = "0/5"
            registering = true
        }
    }

    private func tick(_ f: HandFrame) {
        if registering { return capture(f) }
        guard !busy, !checking, !prints.isEmpty, f.time - lastCheck >= 1 else { return }
        lastCheck = f.time
        guard let face = f.face, let cg = FacePrint.crop(f.pixelBuffer, face) else { return block("No face in view") }
        checking = true
        let known = prints
        Task {
            let d = await Task.detached { FacePrint.nearest(cg, known) }.value
            checking = false
            guard running, !busy else { return }
            guard let d else { return block("Couldn't read your face") }
            let ok = d <= limit
            HandTracker.shared.gesturesAllowed = ok
            live = ok
            status = (ok ? "Matched ✓" : "Not you, gestures paused") + String(format: " · %.2f / %.2f", d, limit)
        }
    }

    private func block(_ why: String) {
        HandTracker.shared.gesturesAllowed = false
        live = false
        status = why
    }

    private func capture(_ f: HandFrame) {
        guard f.time - lastShot >= 0.6, let face = f.face, let cg = FacePrint.crop(f.pixelBuffer, face) else { return }
        lastShot = f.time
        shots.append(cg)
        banner = "\(shots.count)/5"
        guard shots.count == 5 else { return }
        registering = false
        let imgs = shots
        shots = []
        status = "Saving…"
        Task {
            let ps = await Task.detached { imgs.compactMap(FacePrint.makePrint) }.value
            banner = nil
            busy = false
            guard running else { return }
            if ps.count >= 3 {
                prints = ps
                limit = FacePrint.threshold(intraMax: FacePrint.intraMax(ps))
                FacePrint.save(ps)
                idle = "Checking…"
                action = "Re-register"
                lastCheck = 0
                flash("Registered ✓")
            } else {
                flash("Couldn't read your face, try again")
            }
        }
    }
}

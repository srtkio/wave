import CoreImage
import Vision

// HONEST LIMITS. This is a convenience check, not security or identity recognition.
// VNGenerateImageFeaturePrintRequest is a general image embedding (it was trained to tell scenes and objects apart),
// not a face-identity embedding: it responds to pose, lighting and background at least as much as to who the face is.
// What we do to help: align the crop (landmark box, roll levelled), grayscale, standardise brightness, and set the
// threshold from the user's own spread, so it adapts to this camera and room. A photo, a lookalike or a very different
// room can still pass or fail. Real recognition needs a face-embedding Core ML model (ArcFace / MobileFaceNet /
// FaceNet style, 112-160 px aligned input, cosine distance), a threshold tuned on pairs of same/different people,
// and liveness (blink / depth) if anyone should not be able to hold up a photo.

/// Face crop + feature print helpers. Plain functions so they can run off the main thread.
enum FacePrint {
    static let size = 224
    // shortcut: all of these are guesses until measured on a real camera; the log line `face check: nearest=… threshold=…` shows the numbers.
    static let margin: CGFloat = 1.3   // landmark box grown by 30% to include forehead and ears
    static let spread: Float = 1.3     // threshold = your own widest sample distance x this …
    static let floor: Float = 0.1      // … plus this, so near-identical samples don't make it impossibly tight

    static func threshold(intraMax: Float) -> Float { intraMax * spread + floor }

    /// Largest distance between any two of `n` samples (the user's own spread). `d` may fail for a pair.
    static func calibrate(count n: Int, _ d: (Int, Int) -> Float?) -> Float {
        var m: Float = 0
        for i in 0..<n { for j in (i + 1)..<max(n, i + 1) { m = max(m, d(i, j) ?? 0) } }
        return m
    }

    /// Angle of the eye line, in the space the points are in (raw image, y up). Eyes are ordered by x so the sign is stable.
    static func eyeRoll(_ a: CGPoint, _ b: CGPoint, pixels: CGSize) -> CGFloat {
        let (l, r) = a.x <= b.x ? (a, b) : (b, a)
        return atan2((r.y - l.y) * pixels.height, (r.x - l.x) * pixels.width)
    }

    /// Square around the landmarks' bounding box, in pixels of the raw image. `pts` are mirrored top-left normalised.
    static func square(_ pts: [CGPoint], pixels: CGSize) -> (center: CGPoint, side: CGFloat)? {
        guard pts.count >= 10, let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(),
              let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return nil }
        let side = max((x1 - x0) * pixels.width, (y1 - y0) * pixels.height) * margin
        guard side > 8 else { return nil }
        return (CGPoint(x: (1 - (x0 + x1) / 2) * pixels.width, y: (1 - (y0 + y1) / 2) * pixels.height), side)
    }

    private static let ci = CIContext()

    /// 224x224 upright crop of the face: square landmark box, rotated by -roll about its centre, grayscale.
    /// Rendered now so nothing keeps the camera buffer alive after the callback returns.
    static func crop(_ pb: CVPixelBuffer?, landmarks: [CGPoint], roll: CGFloat) -> CGImage? {
        guard let pb else { return nil }
        let px = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        guard let sq = square(landmarks, pixels: px) else { return nil }
        let k = CGFloat(size) / sq.side
        let t = CGAffineTransform(translationX: -sq.center.x, y: -sq.center.y)
            .concatenating(CGAffineTransform(rotationAngle: -roll))
            .concatenating(CGAffineTransform(translationX: sq.side / 2, y: sq.side / 2))
            .concatenating(CGAffineTransform(scaleX: k, y: k))
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let img = CIImage(cvPixelBuffer: pb).clampedToExtent().transformed(by: t).cropped(to: rect)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        return ci.createCGImage(img, from: rect)
    }

    /// Rescales gray values to mean 128, spread 48, so lighting and exposure matter less. A flat image becomes mid-gray.
    static func standardise(_ px: inout [UInt8]) {
        guard !px.isEmpty else { return }
        let n = Float(px.count)
        let mean = px.reduce(Float(0)) { $0 + Float($1) } / n
        let sd = (px.reduce(Float(0)) { $0 + (Float($1) - mean) * (Float($1) - mean) } / n).squareRoot()
        for i in px.indices { px[i] = sd < 1 ? 128 : UInt8(max(0, min(255, (Float(px[i]) - mean) * 48 / sd + 128))) }
    }

    /// Gray, 224x224, standardised: what the feature print sees.
    static func normalise(_ cg: CGImage) -> CGImage? {
        let n = size
        var px = [UInt8](repeating: 0, count: n * n)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard ok else { return nil }
        standardise(&px)
        return px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
    }

    static func makePrint(_ cg: CGImage) -> VNFeaturePrintObservation? {
        guard let g = normalise(cg) else { return nil }
        let r = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(cgImage: g).perform([r])
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

    // New name: prints made before the aligned crops are not comparable, so they are simply never loaded.
    static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Wave")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "face2.prints")
    }

    static func save(_ ps: [VNFeaturePrintObservation], threshold: Float) {
        let root: NSDictionary = ["prints": ps as NSArray, "threshold": NSNumber(value: threshold)]
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: root, requiringSecureCoding: true) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func load() -> (prints: [VNFeaturePrintObservation], threshold: Float)? {
        guard let data = try? Data(contentsOf: file),
              let root = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSDictionary.self, NSArray.self, NSNumber.self, NSString.self, VNFeaturePrintObservation.self], from: data) as? NSDictionary,
              let ps = root["prints"] as? [VNFeaturePrintObservation], let t = (root["threshold"] as? NSNumber)?.floatValue, !ps.isEmpty
        else { return nil }
        return (ps, t)
    }
}

/// Unlocks on the first match, locks again after 2 misses in a row. One lucky or unlucky frame never flips it back and forth.
struct FaceLock {
    private(set) var open = false
    private var misses = 0
    @discardableResult mutating func update(match: Bool) -> Bool {
        if match { open = true; misses = 0 } else { misses += 1; if misses >= 2 { open = false } }
        return open
    }
}

/// Gestures only work while the registered face is in front of the camera.
@Observable
final class FaceCheck: FeatureBase {
    /// What the user is asked to do while registering ("Turn your head slightly left"); nil when not registering.
    var registrationPrompt: String?
    /// Nearest-sample distance of the latest check (nil = no face / unreadable), and the calibrated limit it is compared to.
    var lastDistance: Float?
    var threshold: Float = 0
    /// Gestures are unlocked (after hysteresis), not the raw single-check result.
    var matched = false

    @ObservationIgnored private var prints: [VNFeaturePrintObservation] = []
    @ObservationIgnored private var shots: [CGImage] = []
    @ObservationIgnored private var lastShot = 0.0
    @ObservationIgnored private var lastCheck = 0.0
    @ObservationIgnored private var registering = false
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var lock = FaceLock()
    @ObservationIgnored private var countdown: Task<Void, Never>?

    // shortcut: 8 samples, 1 s apart so there is time to turn; checks every 0.5 s so a miss locks within ~1 s.
    private static let prompts = ["Look straight at the camera", "Look straight at the camera", "Turn your head slightly left",
                                  "Turn your head slightly left", "Turn your head slightly right", "Turn your head slightly right",
                                  "Tilt your head slightly up", "Look straight at the camera"]
    private static let checkEvery = 0.5, shotEvery = 1.0

    init() {
        super.init(key: "feature.face", symbol: "faceid", name: "Face verification",
                   blurb: "Gestures only work when it's you in front of the camera.")
    }

    override func begin() {
        let saved = FacePrint.load()
        prints = saved?.prints ?? []
        threshold = saved?.threshold ?? 0
        lock = FaceLock(); matched = false; lastDistance = nil
        // Nothing registered = nothing to check against = don't block. Otherwise stay locked until the first match.
        HandTracker.shared.gesturesAllowed = prints.isEmpty
        idle = prints.isEmpty ? "Register your face to start" : "Checking…"
        live = false
        action = prints.isEmpty ? "Register my face" : "Re-register"
        lastCheck = 0
        SessionLog.log("face check on: \(prints.count) prints, threshold=\(String(format: "%.2f", threshold))")
        listen(always: true) { [weak self] f, _ in self?.tick(f) }
    }

    override func end() {
        countdown?.cancel()
        registering = false; shots = []; registrationPrompt = nil; matched = false
        HandTracker.shared.gesturesAllowed = true
    }

    override func act() {
        guard running, !busy else { return }
        busy = true
        HandTracker.shared.gesturesAllowed = true // never lock the user out mid-registration
        live = false
        status = "Look at the camera"
        countdown = Task {
            for n in (1...3).reversed() {
                banner = "\(n)"
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            shots = []; lastShot = 0
            banner = "0/\(Self.prompts.count)"
            registrationPrompt = Self.prompts[0]
            registering = true
        }
    }

    private func tick(_ f: HandFrame) {
        if registering { return capture(f) }
        guard !busy, !checking, !prints.isEmpty, f.time - lastCheck >= Self.checkEvery else { return }
        lastCheck = f.time
        guard f.faceCount > 0 else {
            SessionLog.log("face check: no face found (faces=0)")
            return verdict(nil, why: "No face in view")
        }
        if f.faceCount > 1 { SessionLog.log("face check: faces=\(f.faceCount), using the largest") }
        guard let cg = FacePrint.crop(f.pixelBuffer, landmarks: f.faceLandmarks, roll: f.faceRoll) else {
            SessionLog.log("face check: no usable landmarks (\(f.faceLandmarks.count) points)")
            return verdict(nil, why: "Couldn't read your face")
        }
        checking = true
        let known = prints
        Task {
            let d = await Task.detached { FacePrint.nearest(cg, known) }.value
            checking = false
            guard running, !busy else { return }
            verdict(d, why: "Couldn't read your face")
        }
    }

    /// One check's result -> hysteresis -> gestures allowed or not.
    private func verdict(_ d: Float?, why: String) {
        lastDistance = d
        let hit = d.map { $0 < threshold } ?? false
        if let d {
            SessionLog.log(String(format: "face check: nearest=%.2f threshold=%.2f -> %@", d, threshold, hit ? "match" : "no match"))
        }
        let was = lock.open
        let open = lock.update(match: hit)
        if open != was { SessionLog.log("face check: \(open ? "unlocked" : "locked")") }
        matched = open
        HandTracker.shared.gesturesAllowed = open
        live = open
        if let d { status = (open ? "Matched ✓" : "Not you, gestures paused") + String(format: " · %.2f / %.2f", d, threshold) }
        else { status = why }
    }

    private func capture(_ f: HandFrame) {
        guard f.time - lastShot >= Self.shotEvery else { return }
        // Exactly one real-sized face: never enrol someone standing behind you or a speck in the background.
        guard f.faceCount == 1, (f.face?.width ?? 0) > 0.1 else {
            registrationPrompt = f.faceCount > 1 ? "Only you should be in view" : "Move closer so your face is in view"
            return
        }
        guard let cg = FacePrint.crop(f.pixelBuffer, landmarks: f.faceLandmarks, roll: f.faceRoll) else { return }
        lastShot = f.time
        shots.append(cg)
        let n = Self.prompts.count
        banner = "\(shots.count)/\(n)"
        if shots.count < n { registrationPrompt = Self.prompts[shots.count]; return }
        registering = false
        registrationPrompt = nil
        let imgs = shots
        shots = []
        status = "Saving…"
        Task {
            let ps = await Task.detached { imgs.compactMap(FacePrint.makePrint) }.value
            banner = nil
            busy = false
            guard running else { return }
            if ps.count >= n - 2 {
                let spread = FacePrint.calibrate(count: ps.count) { FacePrint.distance(ps[$0], ps[$1]) }
                prints = ps
                threshold = FacePrint.threshold(intraMax: spread)
                FacePrint.save(ps, threshold: threshold)
                SessionLog.log(String(format: "face check: registered %d prints, own spread=%.2f threshold=%.2f", ps.count, spread, threshold))
                lock = FaceLock(); lastCheck = 0
                idle = "Checking…"
                action = "Re-register"
                flash("Registered ✓")
            } else {
                SessionLog.log("face check: registration failed, only \(ps.count) of \(n) prints")
                flash("Couldn't read your face, try again")
            }
        }
    }

    // MARK: self-check

    /// Threshold maths, hysteresis, crop geometry and the crop/normalise pipeline. Prints each failure.
    nonisolated static func selfCheck() -> Bool {
        var ok = true
        func check(_ name: String, _ pass: Bool) { if !pass { print("FAIL face check:", name); ok = false } }
        func near(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 1e-4 }

        check("threshold of nothing = floor", near(FacePrint.threshold(intraMax: 0), FacePrint.floor))
        check("threshold = max x 1.3 + floor", near(FacePrint.threshold(intraMax: 0.5), 0.5 * 1.3 + FacePrint.floor))
        let dm: [[Float]] = [[0, 0.2, 0.5], [0.2, 0, 0.3], [0.5, 0.3, 0]]
        check("calibrate = widest pair", near(FacePrint.calibrate(count: 3) { dm[$0][$1] }, 0.5))
        check("calibrate ignores failed pairs", near(FacePrint.calibrate(count: 3) { $0 == 0 && $1 == 2 ? nil : dm[$0][$1] }, 0.3))
        check("calibrate of one sample = 0", FacePrint.calibrate(count: 1) { _, _ in 9 } == 0)

        var l = FaceLock()
        check("starts locked", !l.open)
        check("miss while locked stays locked", !l.update(match: false))
        check("first match unlocks at once", l.update(match: true))
        check("one miss keeps it open", l.update(match: false))
        check("a match clears the miss streak", l.update(match: true) && l.update(match: false))
        check("two misses in a row lock", !l.update(match: false))
        check("and a match reopens", l.update(match: true))

        let px = CGSize(width: 640, height: 360)
        let box = [CGPoint](repeating: CGPoint(x: 0.4, y: 0.3), count: 9) + [CGPoint(x: 0.6, y: 0.5)]
        if let sq = FacePrint.square(box, pixels: px) {
            check("square side = longest box edge x margin", abs(sq.side - 0.2 * 640 * FacePrint.margin) < 0.01)
            check("square centre in raw (unmirrored, y up) pixels", abs(sq.center.x - 320) < 0.01 && abs(sq.center.y - 0.6 * 360) < 0.01)
        } else { check("square exists", false) }
        check("too few landmarks = no crop", FacePrint.square([CGPoint(x: 0.5, y: 0.5)], pixels: px) == nil)
        check("eye roll level = 0", FacePrint.eyeRoll(CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.6, y: 0.5), pixels: px) == 0)
        let tilt = FacePrint.eyeRoll(CGPoint(x: 0.6, y: 0.5 + 0.2 * 640 / 360), CGPoint(x: 0.4, y: 0.5), pixels: px)
        check("eye roll 45 degrees, eye order does not matter", abs(tilt - .pi / 4) < 1e-6)

        var flat = [UInt8](repeating: 77, count: 100)
        FacePrint.standardise(&flat)
        check("flat image -> mid gray", flat.allSatisfy { $0 == 128 })
        var ramp = (0..<1000).map { UInt8($0 % 256) }
        FacePrint.standardise(&ramp)
        let mean = ramp.reduce(0.0) { $0 + Double($1) } / Double(ramp.count)
        check("standardise recentres on 128", abs(mean - 128) < 3)

        // Pipeline: two bright dots on a tilted eye line must come out level, and the crop must be 224x224.
        // Dots at raw (y-up) pixels (280,180) and (380,230); buffer rows run top-down, so row = height - y.
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let pb else { print("FAIL face check: no pixel buffer"); return false }
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(pb)
        for y in 0..<360 { for x in 0..<640 { for c in 0..<4 { base[y * stride + x * 4 + c] = c == 3 ? 255 : 0 } } }
        for (cx, cy) in [(280, 180), (380, 230)] {
            for dy in -8...8 { for dx in -8...8 { for c in 0..<3 { base[(360 - (cy + dy)) * stride + (cx + dx) * 4 + c] = 255 } } }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        let roll = atan2(50.0, 100.0)
        // Landmark box around the dots, as mirrored top-left points: x' = 1 - x/640, y' = 1 - y/360 (y raw is up).
        func m(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 1 - x / 640, y: 1 - y / 360) }
        let pts = [CGPoint](repeating: m(250, 150), count: 9) + [m(410, 260)]
        if let out = FacePrint.crop(pb, landmarks: pts, roll: roll) {
            check("crop is 224x224", out.width == 224 && out.height == 224)
            var g = [UInt8](repeating: 0, count: 224 * 224)
            g.withUnsafeMutableBytes { buf in
                CGContext(data: buf.baseAddress, width: 224, height: 224, bitsPerComponent: 8, bytesPerRow: 224,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?
                    .draw(out, in: CGRect(x: 0, y: 0, width: 224, height: 224))
            }
            func meanY(_ left: Bool) -> Double? {
                var sy = 0.0, n = 0.0
                for y in 0..<224 { for x in (left ? 0 : 112)..<(left ? 112 : 224) where g[y * 224 + x] > 128 { sy += Double(y); n += 1 } }
                return n > 20 ? sy / n : nil
            }
            if let a = meanY(true), let b = meanY(false) { check("tilted eye line comes out level (dy=\(b - a))", abs(a - b) < 3) }
            else { check("both dots visible in the crop", false) }
            check("feature print runs on the crop", FacePrint.makePrint(out) != nil)
        } else { check("crop renders", false) }
        return ok
    }
}

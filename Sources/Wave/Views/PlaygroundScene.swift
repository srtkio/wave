import SceneKit
import SwiftUI

/// Pure math for the playground, free of SceneKit state so `selfCheck()` can verify it.
enum PlaygroundMath {
    static let cameraZ: Float = 10
    static let fovDegrees: Float = 40 // vertical

    struct Sample { var p: SIMD3<Float>; var t: Double }

    /// Half width and height of the z = 0 plane the camera sees edge to edge.
    static func halfExtents(_ size: CGSize) -> SIMD2<Float> {
        let h = cameraZ * tan(fovDegrees / 2 * .pi / 180)
        return [h * Float(size.width / max(size.height, 1)), h]
    }

    /// View point (top-left origin, points, as from `viewPoint`) to the world point on z = 0 under it.
    static func world(_ p: CGPoint, in size: CGSize) -> SIMD3<Float> {
        guard size.width > 0, size.height > 0 else { return .zero }
        let e = halfExtents(size)
        return [(Float(p.x / size.width) * 2 - 1) * e.x, (1 - Float(p.y / size.height) * 2) * e.y, 0]
    }

    /// Velocity over the newest `window` seconds of samples, capped so a tracking glitch can't fire a rocket.
    static func throwVelocity(_ s: ArraySlice<Sample>, window: Double = 0.12, maxSpeed: Float = 22) -> SIMD3<Float> {
        guard let last = s.last, let first = s.first(where: { $0.t >= last.t - window }), last.t > first.t else { return .zero }
        let v = (last.p - first.p) / Float(last.t - first.t)
        let speed = simd_length(v)
        return speed > maxSpeed ? v * (maxSpeed / speed) : v
    }

    /// Run by `--selftest`.
    static func selfCheck() -> Bool {
        func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool { simd_length(a - b) < 1e-3 }
        let size = CGSize(width: 1600, height: 900)
        let e = halfExtents(size)
        let line = [Sample(p: .zero, t: 0), Sample(p: [0.5, 0.25, 0], t: 0.05), Sample(p: [1, 0.5, 0], t: 0.1)]
        let stale = [Sample(p: [50, 0, 0], t: 0), Sample(p: .zero, t: 1), Sample(p: [1, 0, 0], t: 1.1)]
        let glitch = [Sample(p: .zero, t: 0), Sample(p: [100, 0, 0], t: 0.1)]
        return abs(e.y - 3.6397) < 1e-3 && abs(e.x - e.y * 16 / 9) < 1e-3
            && near(world(CGPoint(x: 800, y: 450), in: size), .zero)
            && near(world(.zero, in: size), [-e.x, e.y, 0])                       // top-left of view is up-left in world
            && near(world(CGPoint(x: 1600, y: 900), in: size), [e.x, -e.y, 0])
            && near(throwVelocity(line[...]), [10, 5, 0])
            && near(throwVelocity(stale[...]), [10, 0, 0])                       // samples outside the window are ignored
            && abs(simd_length(throwVelocity(glitch[...])) - 22) < 1e-3
            && throwVelocity(line[0..<1]) == .zero
    }
}

private let tipJoints: [Joint] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]

/// Owns the SceneKit scene and all playground state. Only `holdProgress` is observed by SwiftUI.
@Observable
final class PlaygroundWorld {
    /// 0...1 while an open palm is held, drives the HUD ring.
    var holdProgress: Double = 0

    @ObservationIgnored let scene = SCNScene()
    @ObservationIgnored private var size = CGSize.zero
    @ObservationIgnored private var bodies: [SCNNode] = []
    @ObservationIgnored private var radii: [Float] = []
    @ObservationIgnored private var floating: [Bool] = []
    @ObservationIgnored private var walls: [SCNNode] = []
    @ObservationIgnored private var tips: [SCNNode] = []
    @ObservationIgnored private var trails: [SCNParticleSystem] = []
    @ObservationIgnored private var tipVisible = [Bool](repeating: false, count: 10)
    @ObservationIgnored private var rings: [SCNNode] = []
    @ObservationIgnored private let burst = SCNParticleSystem()
    @ObservationIgnored private var slots = [Slot(), Slot()]
    @ObservationIgnored private var lastBlast = -Double.infinity
    @ObservationIgnored private var openSince: Double?
    @ObservationIgnored private var didReset = false

    private struct Slot {
        var pinching = false
        var grabbed: Int?
        var samples: [PlaygroundMath.Sample] = { var a = [PlaygroundMath.Sample](); a.reserveCapacity(8); return a }()
    }

    private static let trailRate: CGFloat = 220
    private static let dot: NSImage = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { r in
        NSGradient(colors: [.white, .white.withAlphaComponent(0)])?.draw(in: NSBezierPath(ovalIn: r), relativeCenterPosition: .zero)
        return true
    }

    init() {
        let a = NSColor(Theme.accent), b = NSColor(Theme.accent2), g = NSColor(Theme.success)
        let root = scene.rootNode

        let cam = SCNCamera()
        cam.fieldOfView = CGFloat(PlaygroundMath.fovDegrees)
        cam.projectionDirection = .vertical // halfExtents assumes the fov spans the height
        cam.zNear = 0.1
        cam.zFar = 100
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.simdPosition = [0, 0, PlaygroundMath.cameraZ]
        root.addChildNode(camNode)

        func light(_ type: SCNLight.LightType, _ color: NSColor, _ intensity: CGFloat, _ p: SIMD3<Float>) {
            let n = SCNNode()
            n.light = SCNLight()
            n.light!.type = type
            n.light!.color = color
            n.light!.intensity = intensity
            n.simdPosition = p
            n.simdLook(at: .zero)
            root.addChildNode(n)
        }
        light(.ambient, .white, 350, .zero)
        light(.directional, .white, 900, [2, 6, 8])
        light(.omni, a, 700, [6, -3, 5])
        light(.omni, b, 700, [-6, 4, 5])
        // Soft studio gradient so the glass has something to reflect.
        scene.lightingEnvironment.contents = NSImage(size: NSSize(width: 64, height: 32), flipped: false) { r in
            NSGradient(colors: [b.blended(withFraction: 0.4, of: .black)!, .black, a.blended(withFraction: 0.3, of: .black)!])?.draw(in: r, angle: -90)
            return true
        }
        scene.lightingEnvironment.intensity = 1.4
        scene.background.contents = NSColor.clear // with the view's clear background, lets the camera show through
        scene.physicsWorld.gravity = SCNVector3(0, -12, 0)

        for _ in 0..<4 {
            let w = SCNNode()
            w.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            w.physicsBody!.restitution = 0.7
            root.addChildNode(w)
            walls.append(w)
        }

        let shapes: [(SCNGeometry, Float, NSColor)] = [
            (SCNBox(width: 0.9, height: 0.9, length: 0.9, chamferRadius: 0.16), 0.6, a),
            (SCNSphere(radius: 0.55), 0.55, b),
            (SCNTorus(ringRadius: 0.5, pipeRadius: 0.18), 0.68, g),
            (SCNCapsule(capRadius: 0.3, height: 1.1), 0.55, a),
            (SCNSphere(radius: 0.4), 0.4, b),
        ]
        for (geo, radius, color) in shapes {
            geo.firstMaterial = Self.glass(color)
            let visual = SCNNode(geometry: geo)
            let halo = SCNNode(geometry: geo.copy() as? SCNGeometry)
            halo.geometry!.firstMaterial = Self.halo(color)
            halo.simdScale = [1.12, 1.12, 1.12]
            visual.addChildNode(halo)

            let node = SCNNode()
            node.addChildNode(visual)
            let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: geo, options: nil))
            body.mass = 1
            body.restitution = 0.65
            body.friction = 0.5
            body.rollingFriction = 0.05
            body.velocityFactor = SCNVector3(1, 1, 0) // stay on the hand's z plane
            body.continuousCollisionDetectionThreshold = 0.3 // fast throws must not tunnel through walls
            node.physicsBody = body
            root.addChildNode(node)
            bodies.append(node)
            radii.append(radius)
            floating.append(true)
        }

        for i in 0..<10 {
            let p = SCNParticleSystem()
            p.birthRate = 0
            p.particleLifeSpan = 0.45
            p.particleLifeSpanVariation = 0.15
            p.particleSize = 0.1
            p.particleImage = Self.dot
            p.particleColor = a.blended(withFraction: CGFloat(i % 5) / 4, of: b)!
            p.blendMode = .additive
            p.emitterShape = SCNSphere(radius: 0.025)
            p.particleVelocity = 0.15
            p.spreadingAngle = 180
            p.isLightingEnabled = false
            p.sortingMode = .none
            p.propertyControllers = [.opacity: Self.fade(1, 0), .size: Self.fade(0.12, 0.01)]
            let n = SCNNode()
            n.addParticleSystem(p)
            root.addChildNode(n)
            tips.append(n)
            trails.append(p)
        }

        for color in [a, b] {
            let torus = SCNTorus(ringRadius: 1, pipeRadius: 0.035)
            torus.firstMaterial = Self.halo(color)
            torus.firstMaterial!.cullMode = .back
            torus.firstMaterial!.transparency = 1
            let n = SCNNode(geometry: torus)
            n.eulerAngles.x = .pi / 2 // torus lies in XZ by default; face the camera
            n.opacity = 0
            root.addChildNode(n)
            rings.append(n)
        }

        burst.loops = false
        burst.birthRate = 900
        burst.emissionDuration = 0.06
        burst.particleLifeSpan = 0.7
        burst.particleLifeSpanVariation = 0.3
        burst.particleVelocity = 7
        burst.particleVelocityVariation = 4
        burst.spreadingAngle = 180
        burst.dampingFactor = 3
        burst.emitterShape = SCNSphere(radius: 0.2)
        burst.particleSize = 0.12
        burst.particleImage = Self.dot
        burst.particleColor = a
        burst.particleColorVariation = SCNVector4(0.15, 0, 0, 0)
        burst.blendMode = .additive
        burst.isLightingEnabled = false
        burst.propertyControllers = [.opacity: Self.fade(1, 0)]
    }

    // MARK: Per-frame

    func update(_ frame: HandFrame, _ gesture: Gesture) {
        guard size.width > 0 else { return }
        let now = frame.time

        // Implicit 1/30 s animation smooths the 30 fps hand data into the 60 fps render, so trails stay continuous.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.0 / 30
        for s in 0..<2 {
            let hand = s < frame.hands.count ? frame.hands[s] : nil
            for f in 0..<5 {
                let i = s * 5 + f
                guard let p = hand?.points[tipJoints[f]] else {
                    if tipVisible[i] { trails[i].birthRate = 0; tipVisible[i] = false }
                    continue
                }
                let w = PlaygroundMath.world(viewPoint(p, in: size), in: size)
                if tipVisible[i] {
                    tips[i].simdPosition = w
                } else {
                    // Jump, don't glide, from where the finger was last seen.
                    SCNTransaction.begin()
                    SCNTransaction.disableActions = true
                    tips[i].simdPosition = w
                    SCNTransaction.commit()
                    trails[i].birthRate = Self.trailRate
                    tipVisible[i] = true
                }
            }
        }
        SCNTransaction.commit()

        // shortcut: hand slots follow Vision's result order, which can swap when two hands cross; track by position if that bites.
        for s in 0..<2 {
            let pts = s < frame.hands.count ? frame.hands[s].points : [:]
            guard let th = pts[.thumbTip], let ix = pts[.indexTip], let wr = pts[.wrist], let mm = pts[.middleMCP] else {
                release(s)
                continue
            }
            let a = viewPoint(th, in: size), b = viewPoint(ix, in: size)
            let w = viewPoint(wr, in: size), m = viewPoint(mm, in: size)
            let palm = hypot(w.x - m.x, w.y - m.y)
            let ratio = palm > 0 ? hypot(a.x - b.x, a.y - b.y) / palm : .infinity
            let p = PlaygroundMath.world(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), in: size)

            // Same 0.3 as classify() to start; release at 0.5 so jitter doesn't drop the object mid-drag.
            if !slots[s].pinching, ratio < 0.3 {
                slots[s].pinching = true
                grab(s, at: p)
            } else if slots[s].pinching, ratio > 0.5 {
                release(s)
            }
            if let i = slots[s].grabbed, let body = bodies[i].physicsBody {
                body.velocity = SCNVector3((p - bodies[i].presentation.simdPosition) * 18)
                if slots[s].samples.count == 8 { slots[s].samples.removeFirst() }
                slots[s].samples.append(.init(p: p, t: now))
            }
        }

        // A floating object knocked by another one joins the physics for real.
        for i in bodies.indices where floating[i] {
            if let v = bodies[i].physicsBody?.velocity, simd_length(SIMD3<Float>(v)) > 0.8 { setFloating(i, false) }
        }

        let hand = frame.hands.first
        if gesture == .fist, now - lastBlast > 1, let c = hand?.points[.middleMCP] ?? hand?.points[.wrist] {
            lastBlast = now
            blast(at: PlaygroundMath.world(viewPoint(c, in: size), in: size))
        }

        var progress = 0.0
        if gesture == .open {
            let since = openSince ?? now
            openSince = since
            if !didReset {
                progress = min(now - since, 1)
                if progress >= 1 { didReset = true; progress = 0; respawn() }
            }
        } else {
            openSince = nil
            didReset = false
        }
        // Quantised so SwiftUI only re-renders the HUD when the ring visibly moves.
        if abs(progress - holdProgress) > 0.03 || (progress == 0) != (holdProgress == 0) { holdProgress = progress }
    }

    // MARK: Actions

    func layout(_ s: CGSize) {
        guard s.width > 0, s.height > 0, s != size else { return }
        let first = size == .zero
        size = s
        let e = PlaygroundMath.halfExtents(s)
        let t: Float = 2 // thick walls so nothing tunnels through
        let frames: [(SIMD2<Float>, SIMD2<Float>)] = [
            ([t, 2 * e.y + 2 * t], [-e.x - t / 2, 0]),
            ([t, 2 * e.y + 2 * t], [e.x + t / 2, 0]),
            ([2 * e.x + 2 * t, t], [0, e.y + t / 2]),
            ([2 * e.x + 2 * t, t], [0, -e.y - t / 2]), // floor
        ]
        for (wall, (dim, pos)) in zip(walls, frames) {
            wall.physicsBody!.physicsShape = SCNPhysicsShape(geometry: SCNBox(width: CGFloat(dim.x), height: CGFloat(dim.y), length: 4, chamferRadius: 0), options: nil)
            wall.simdPosition = [pos.x, pos.y, 0]
            wall.physicsBody!.resetTransform()
        }
        if first { respawn(); return }
        // The window shrank: pull anything now outside the walls back in.
        for (i, n) in bodies.enumerated() {
            let p = n.presentation.simdPosition, r = radii[i]
            let c = SIMD3<Float>(min(max(p.x, -e.x + r), e.x - r), min(max(p.y, -e.y + r), e.y - r), 0)
            if c != p { n.simdPosition = c; n.physicsBody?.resetTransform() }
        }
    }

    func respawn() {
        guard size.width > 0 else { return }
        for s in slots.indices { slots[s].grabbed = nil; slots[s].samples.removeAll(keepingCapacity: true) }
        let e = PlaygroundMath.halfExtents(size)
        for (i, n) in bodies.enumerated() {
            let x = (Float(i) / Float(bodies.count - 1) - 0.5) * 1.3 * e.x
            n.simdPosition = [x, e.y * (i.isMultiple(of: 2) ? 0.2 : -0.1), 0]
            n.simdOrientation = simd_quatf(angle: 0.5, axis: simd_normalize([1, 0.6, 0.2]))
            n.physicsBody!.velocity = SCNVector3Zero
            n.physicsBody!.angularVelocity = SCNVector4(0.3, 1, 0.2, i.isMultiple(of: 2) ? 0.5 : -0.4)
            n.physicsBody!.resetTransform()
            setFloating(i, true)

            let v = n.childNodes[0]
            v.removeAction(forKey: "pop")
            v.simdScale = .zero
            v.opacity = 0
            let up = SCNAction.scale(to: 1.18, duration: 0.28)
            up.timingMode = .easeOut
            let settle = SCNAction.scale(to: 1, duration: 0.18)
            settle.timingMode = .easeInEaseOut
            v.runAction(.sequence([.wait(duration: 0.07 * Double(i)), .group([.fadeIn(duration: 0.2), .sequence([up, settle])])]), forKey: "pop")
        }
    }

    private func grab(_ s: Int, at p: SIMD3<Float>) {
        var best: Int?
        var bestD = Float.infinity
        for (i, n) in bodies.enumerated() {
            let d = simd_length(n.presentation.simdPosition - p)
            if d < radii[i] + 0.5, d < bestD { best = i; bestD = d }
        }
        guard let i = best else { return }
        let other = 1 - s
        if slots[other].grabbed == i { slots[other].grabbed = nil } // the other hand steals it
        slots[s].grabbed = i
        slots[s].samples.removeAll(keepingCapacity: true)
        setFloating(i, false)
        bodies[i].physicsBody!.isAffectedByGravity = false
        bodies[i].childNodes[0].opacity = 1 // in case the pop-in fade gets cut short
        bodies[i].childNodes[0].runAction(.scale(to: 1.12, duration: 0.15), forKey: "pop")
    }

    private func release(_ s: Int) {
        slots[s].pinching = false
        guard let i = slots[s].grabbed, let body = bodies[i].physicsBody else { return }
        slots[s].grabbed = nil
        didReset = true // a throw ends in an open palm; don't let that follow-through count as a reset hold
        body.isAffectedByGravity = true
        body.velocity = SCNVector3(PlaygroundMath.throwVelocity(slots[s].samples[...]))
        bodies[i].childNodes[0].runAction(.scale(to: 1, duration: 0.2), forKey: "pop")
    }

    private func blast(at c: SIMD3<Float>) {
        for (k, ring) in rings.enumerated() {
            ring.removeAllActions()
            ring.simdPosition = c
            ring.simdScale = [0.2, 0.2, 0.2]
            ring.opacity = 1
            let grow = SCNAction.scale(to: k == 0 ? 7 : 5, duration: 0.65)
            grow.timingMode = .easeOut
            ring.runAction(.sequence([.wait(duration: 0.08 * Double(k)), .group([grow, .fadeOut(duration: 0.65)])]))
        }
        scene.removeAllParticleSystems()
        burst.reset()
        scene.addParticleSystem(burst, transform: SCNMatrix4MakeTranslation(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z)))

        for (i, n) in bodies.enumerated() where !slots.contains(where: { $0.grabbed == i }) {
            let d = n.presentation.simdPosition - c
            let dist = simd_length(d)
            let dir = dist > 0.01 ? d / dist : [0, 1, 0]
            setFloating(i, false)
            n.physicsBody!.applyForce(SCNVector3((dir + [0, 0.35, 0]) * (16 / (1 + dist * 0.4))), asImpulse: true)
            n.physicsBody!.applyTorque(SCNVector4(dir.y, -dir.x, 0.3, 2), asImpulse: true)
        }
    }

    private func setFloating(_ i: Int, _ on: Bool) {
        floating[i] = on
        let body = bodies[i].physicsBody!, v = bodies[i].childNodes[0]
        body.isAffectedByGravity = !on
        body.damping = on ? 0.6 : 0.05
        body.angularDamping = on ? 0 : 0.3
        if on {
            let rise = SCNAction.moveBy(x: 0, y: 0.12, z: 0, duration: 1.4)
            rise.timingMode = .easeInEaseOut
            v.runAction(.repeatForever(.sequence([rise, rise.reversed()])), forKey: "bob")
        } else if v.action(forKey: "bob") != nil {
            v.removeAction(forKey: "bob")
            v.runAction(.move(to: SCNVector3Zero, duration: 0.15))
        }
    }

    // MARK: Materials

    private static func glass(_ c: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.metalness.contents = 0.15
        m.roughness.contents = 0.08
        m.emission.contents = c.blended(withFraction: 0.65, of: .black)
        m.transparency = 0.72
        m.transparencyMode = .dualLayer // back faces then front: reads as solid glass
        return m
    }

    /// Additive inside-out shell: a cheap neon glow without HDR bloom, which may not keep the view transparent.
    private static func halo(_ c: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c
        m.blendMode = .add
        m.cullMode = .front
        m.writesToDepthBuffer = false
        m.transparency = 0.35
        return m
    }

    private static func fade(_ from: CGFloat, _ to: CGFloat) -> SCNParticlePropertyController {
        let a = CAKeyframeAnimation()
        a.values = [from, to]
        a.keyTimes = [0, 1]
        return SCNParticlePropertyController(animation: a)
    }
}

struct PlaygroundSceneView: NSViewRepresentable {
    let world: PlaygroundWorld
    let size: CGSize

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: nil)
        v.scene = world.scene
        // All three, with the scene's clear background, so the camera shows through the Metal layer.
        v.backgroundColor = .clear
        v.wantsLayer = true
        v.layer?.isOpaque = false
        v.layer?.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.isPlaying = true
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) { world.layout(size) }
}

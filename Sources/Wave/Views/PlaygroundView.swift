import SwiftUI

struct PlaygroundView: View {
    let size: CGSize
    @State private var world = PlaygroundWorld()
    @State private var listener: UUID?
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        ZStack {
            // SCNView is Metal-backed, so snapshots can't capture it.
            if !snapshot {
                PlaygroundSceneView(world: world, size: size)
                    .allowsHitTesting(false)
            }
            PlaygroundHUD(world: world)
                .stageColumn()
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            let world = world
            listener = HandTracker.shared.onFrame { frame, gesture in world.update(frame, gesture) }
        }
        .onDisappear {
            if let listener { HandTracker.shared.removeListener(listener) }
            listener = nil
        }
    }
}

/// Own view so the hold ring's updates don't re-evaluate the scene layer.
private struct PlaygroundHUD: View {
    let world: PlaygroundWorld

    var body: some View {
        let hold = world.holdProgress
        Panel(symbol: "cube.transparent", title: "Playground",
              caption: "Pinch to grab and throw. Make a fist to blast. Hold an open palm to reset.") {
            Button { world.respawn() } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: hold)
                            .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(width: 22, height: 22)
                    Text("Reset objects")
                }
            }
            .buttonStyle(GlassButtonStyle())
            .help("Respawn the objects")
        }
        .scaleEffect(hold > 0 ? 1.03 : 1)
        .animation(Theme.spring, value: hold > 0)
    }
}

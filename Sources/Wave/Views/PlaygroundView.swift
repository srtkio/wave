import SwiftUI

/// Shown inside a `CameraStage`: the 3D toy over the full-size camera.
struct PlaygroundView: View {
    let size: CGSize
    let onFullscreen: (() -> Void)?
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
            PlaygroundHUD(world: world, onFullscreen: onFullscreen)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(16)
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
    let onFullscreen: (() -> Void)?

    var body: some View {
        let hold = world.holdProgress
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playground").font(.headline)
                Text("Pinch to grab and throw. Make a fist to blast. Hold an open palm to reset.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button { world.respawn() } label: {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(.quaternary, lineWidth: 2)
                        Circle().trim(from: 0, to: hold)
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 14, height: 14)
                    Text("Reset")
                }
            }
            .help("Respawn the objects")
            if let onFullscreen {
                Button(action: onFullscreen) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Full screen")
                    .accessibilityLabel("Full screen")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

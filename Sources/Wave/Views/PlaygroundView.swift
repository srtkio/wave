import SwiftUI

struct PlaygroundView: View {
    @State private var world = PlaygroundWorld()
    @State private var listener: UUID?

    var body: some View {
        CameraStage { size in
            ZStack(alignment: .topTrailing) {
                PlaygroundSceneView(world: world, size: size)
                    .allowsHitTesting(false)
                PlaygroundHUD(world: world)
                    .padding(Theme.pad)
            }
            .frame(width: size.width, height: size.height)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
                Text("Playground")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Theme.caption("Pinch to grab · Fist to blast · Open palm to reset")
                .fixedSize(horizontal: false, vertical: true)
            Button { world.respawn() } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.15), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: hold)
                            .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(width: 22, height: 22)
                    Text("Reset").font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glass(corner: 14, highlighted: hold > 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Respawn the objects")
        }
        .padding(16)
        .frame(width: 250, alignment: .leading)
        .glass()
        .scaleEffect(hold > 0 ? 1.03 : 1)
        .animation(Theme.spring, value: hold > 0)
    }
}

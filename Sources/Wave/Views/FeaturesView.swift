import SwiftUI

struct FeaturesView: View {
    var body: some View {
        Form {
            ForEach(FeatureHub.shared.all, id: \.key) { FeatureSection(feature: $0) }
            Section {
                Text("Features keep working when this window is closed. They pause while cursor mode is on.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FeatureSection: View {
    let feature: FeatureBase
    @AppStorage private var on: Bool

    init(feature: FeatureBase) {
        self.feature = feature
        _on = AppStorage(wrappedValue: false, feature.key) // off by default, persisted
    }

    var body: some View {
        let face = feature as? FaceCheck
        Section {
            HStack(spacing: 12) {
                Image(systemName: feature.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(on ? Theme.accent : Color.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.name)
                    Text(feature.blurb).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle(feature.name, isOn: $on).toggleStyle(.switch).labelsHidden()
            }
            if feature.running {
                HStack(spacing: 8) {
                    Circle().fill(feature.live ? Color.green : Color.orange).frame(width: 8, height: 8)
                    Text(feature.status).monospacedDigit().lineLimit(2)
                    Spacer()
                    if let label = feature.action {
                        Button(label) { feature.act() }.disabled(feature.busy)
                    }
                }
            }
            if let face, face.running { FaceDetails(face: face) }
        }
        .onChange(of: on) { FeatureHub.shared.sync() }
    }
}

/// Face check: a small camera (so you can see what it sees while registering) and the live match numbers.
private struct FaceDetails: View {
    let face: FaceCheck

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // While registering, the countdown/progress and the prompt sit on the camera, where the user is looking.
            CameraCard(width: 360) {
                VStack(spacing: 6) {
                    if let banner = face.banner {
                        Text(banner).font(.system(size: 48, weight: .semibold).monospacedDigit())
                    }
                    if let prompt = face.registrationPrompt {
                        Text(prompt).font(.headline)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Nearest").foregroundStyle(.secondary)
                        Text(face.lastDistance.map { String(format: "%.2f", $0) } ?? "–").monospacedDigit()
                    }
                    GridRow {
                        Text("Limit").foregroundStyle(.secondary)
                        Text(face.threshold > 0 ? String(format: "%.2f", face.threshold) : "–").monospacedDigit()
                    }
                    GridRow {
                        Text("Gestures").foregroundStyle(.secondary)
                        Text(face.matched ? "Unlocked" : "Paused").foregroundStyle(face.matched ? .green : .orange)
                    }
                }
                Text("A match is a nearest distance at or under the limit. This is a convenience, not security.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

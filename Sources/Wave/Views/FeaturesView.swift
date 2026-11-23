import SwiftUI

struct FeaturesView: View {
    var body: some View {
        CameraStage { size in
            ZStack(alignment: .trailing) {
                BannerLayer()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Theme.title("Features")
                            Theme.caption("Switch on what Wave does with your hands. They keep working on every tab.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.pad)
                        .glass()
                        ForEach(FeatureHub.shared.all, id: \.key) { FeatureCard(feature: $0) }
                    }
                    .padding(Theme.pad)
                }
                .scrollIndicators(.hidden)
                .frame(width: min(440, size.width * 0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

/// Big countdown or progress over the camera while a feature asks for it.
private struct BannerLayer: View {
    var body: some View {
        if let text = FeatureHub.shared.all.compactMap(\.banner).first {
            Text(text)
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Theme.accent.opacity(0.8), radius: 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, 440)
                .id(text)
                .transition(.scale.combined(with: .opacity))
                .animation(Theme.spring, value: text)
        }
    }
}

private struct FeatureCard: View {
    let feature: FeatureBase
    @AppStorage private var on: Bool

    init(feature: FeatureBase) {
        self.feature = feature
        _on = AppStorage(wrappedValue: false, feature.key) // off by default, persisted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: feature.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(on ? 1 : 0.7))
                    .frame(width: 44, height: 44)
                    .background(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.white.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.name).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Theme.caption(feature.blurb).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(feature.name, isOn: $on).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(feature.live ? Theme.success : Color.gray.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .shadow(color: feature.live ? Theme.success.opacity(0.9) : .clear, radius: 5)
                Text(feature.status)
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let label = feature.action {
                    Button(label) { feature.act() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.gradient, in: Capsule())
                        .opacity(feature.busy ? 0.4 : 1)
                        .disabled(feature.busy)
                }
            }
        }
        .padding(16)
        .glass(highlighted: on)
        .animation(Theme.spring, value: on)
        .onChange(of: on) { FeatureHub.shared.sync() }
    }
}

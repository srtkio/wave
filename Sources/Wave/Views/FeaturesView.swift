import SwiftUI

struct FeaturesView: View {
    var body: some View {
        ZStack {
            BannerLayer()
            Panel(symbol: "switch.2", title: "Features",
                  caption: "Switch on what Wave does with your hands. They keep working on every tab.") {
                VStack(spacing: 10) {
                    ForEach(FeatureHub.shared.all, id: \.key) { FeatureCard(feature: $0) }
                }
                .panelScroll()
            }
            .stageColumn()
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
                .padding(.trailing, Theme.panelWidth + Theme.insets.trailing) // centred in the camera left of the panel
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: feature.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(on ? AnyShapeStyle(.black.opacity(0.8)) : AnyShapeStyle(.white.opacity(0.75)))
                    .frame(width: 38, height: 38)
                    .background(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.white.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Theme.heading(feature.name)
                    Theme.caption(feature.blurb).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Toggle(feature.name, isOn: $on).labelsHidden()
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
                        .buttonStyle(GlassButtonStyle(prominent: true))
                        .disabled(feature.busy)
                }
            }
        }
        .card(highlighted: on)
        .animation(Theme.spring, value: on)
        .onChange(of: on) { FeatureHub.shared.sync() }
    }
}

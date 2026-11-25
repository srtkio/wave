import AppKit
import Observation
import SwiftUI

/// A black pill that grows sideways out of the notch to show what Wave is doing.
/// `flash` shows something briefly; `sticky` stays until cleared (e.g. "Cursor"); `progress` draws a ring.
@Observable
final class NotchHUD {
    static let shared = NotchHUD()

    private(set) var flashItem: (text: String, symbol: String)?
    private(set) var sticky: (text: String, symbol: String)?
    /// 0...1 shows a filling ring on the right instead of text, nil hides it.
    var progress: Double? {
        didSet { if progress != nil { ensurePanel() } }
    }

    var shown: (text: String, symbol: String)? { flashItem ?? sticky }

    @ObservationIgnored private var panel: NSPanel?
    /// `--snapshot` renders the pill itself; no real panel.
    @ObservationIgnored var headless = false
    @ObservationIgnored private var flashID = 0

    func flash(_ text: String, symbol: String = "hand.wave.fill", seconds: Double = 1.4) {
        ensurePanel()
        SessionLog.log("notch \"\(text)\"")
        flashID += 1
        let id = flashID
        withAnimation(Theme.spring) { flashItem = (text, symbol) }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.flashID == id else { return }
            withAnimation(Theme.spring) { self.flashItem = nil }
        }
    }

    func setSticky(_ text: String?, symbol: String = "hand.wave.fill") {
        ensurePanel()
        SessionLog.log("notch sticky \(text.map { "\"\($0)\"" } ?? "off")")
        withAnimation(Theme.spring) { sticky = text.map { ($0, symbol) } }
    }

    private func ensurePanel() {
        guard panel == nil, !headless else { return }
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let notch = Self.notchSize(on: screen)
        let size = CGSize(width: notch.width + 2 * Self.side, height: notch.height + 8)
        let p = NSPanel(contentRect: NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                                            width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) // above the menu bar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.contentView = NSHostingView(rootView: NotchPill(notch: notch))
        p.orderFrontRegardless()
        panel = p
    }

    static let side: CGFloat = 130

    /// The notch's size, or a zero-width bar the height of the menu bar on Macs without one.
    static func notchSize(on s: NSScreen) -> CGSize {
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return CGSize(width: r.minX - l.maxX, height: s.safeAreaInsets.top)
        }
        return CGSize(width: 0, height: max(24, s.frame.maxY - s.visibleFrame.maxY))
    }
}

struct NotchPill: View {
    let notch: CGSize
    var hud = NotchHUD.shared

    var body: some View {
        let open = hud.shown != nil || hud.progress != nil
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: hud.shown?.symbol ?? "hand.wave.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: NotchHUD.side)
                Color.clear.frame(width: notch.width)
                Group {
                    if let p = hud.progress {
                        ZStack {
                            Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                            Circle().trim(from: 0, to: p).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 18, height: 18)
                    } else {
                        Text(hud.shown?.text ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                }
                .frame(width: NotchHUD.side)
            }
            .frame(width: open ? notch.width + 2 * NotchHUD.side : notch.width, height: notch.height)
            .clipped()
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14).fill(.black))
            .opacity(open || notch.width > 0 ? 1 : 0)
            .animation(Theme.spring, value: open)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hud.shown?.text ?? "Wave")
    }
}

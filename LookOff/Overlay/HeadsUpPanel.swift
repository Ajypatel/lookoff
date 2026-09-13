import AppKit
import Observation
import SwiftUI

@MainActor
final class HeadsUpController {
    private var panel: OverlayPanel?
    private var live: HeadsUpLiveState?
    private var hostingInstalled = false
    var onStartNow: (() -> Void)?
    var onSnooze: ((Int) -> Void)?

    private(set) var isVisible = false

    func show(settings: AppSettings, remaining: TimeInterval, breakSeconds: TimeInterval) {
        let screen = NSScreen.screenUnderMouse ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let size = NSSize(width: 400, height: 148)
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - 18
        )

        let live = self.live ?? HeadsUpLiveState()
        live.remaining = remaining
        live.breakSeconds = breakSeconds
        self.live = live

        let panel = self.panel ?? OverlayPanel(
            frame: NSRect(origin: origin, size: size),
            allowsKey: true,
            sharingHidden: settings.hideFromRecordings
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = settings.hideFromRecordings ? .none : .readOnly
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.ignoresMouseEvents = false

        if !hostingInstalled || panel.contentView == nil {
            panel.contentView = NSHostingView(
                rootView: HeadsUpView(
                    live: live,
                    onStartNow: { [weak self] in self?.onStartNow?(); self?.hide() },
                    onSnooze: { [weak self] minutes in self?.onSnooze?(minutes); self?.hide() }
                )
            )
            hostingInstalled = true
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel
        isVisible = true
    }

    func update(remaining: TimeInterval) {
        live?.remaining = remaining
    }

    func hide() {
        isVisible = false
        panel?.orderOut(nil)
    }
}

@MainActor
@Observable
final class HeadsUpLiveState {
    var remaining: TimeInterval = 0
    var breakSeconds: TimeInterval = 20
}

struct HeadsUpView: View {
    @Bindable var live: HeadsUpLiveState
    let onStartNow: () -> Void
    let onSnooze: (Int) -> Void

    private var breakLabel: String {
        let secs = Int(live.breakSeconds.rounded())
        if secs >= 60 {
            let m = secs / 60
            return m == 1 ? "1 min" : "\(m) mins"
        }
        return "\(max(secs, 1)) secs"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            StatusHeroTile(icon: .alert, size: 46)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TimeFormat.overlay(live.remaining))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(Motion.reduceMotion ? .identity : .numericText())
                        .animation(Motion.reduceMotion ? nil : .snappy(duration: 0.2), value: live.remaining)
                    Text("Almost time · short break · \(breakLabel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                LookOffGlassContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: onStartNow) {
                            Text("Start now")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .buttonStyle(LookOffGlassButtonStyle(prominent: true, compact: true))

                        HeadsUpChip(title: "+1m") { onSnooze(1) }
                        HeadsUpChip(title: "+5m") { onSnooze(5) }
                        HeadsUpChip(title: "+15m") { onSnooze(15) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lookOffGlass(in: RoundedRectangle(cornerRadius: Layout.pillRadius, style: .continuous))
        .padding(6)
    }
}

struct HeadsUpChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .buttonStyle(LookOffGlassButtonStyle(compact: true))
    }
}

extension NSScreen {
    static var screenUnderMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }
}

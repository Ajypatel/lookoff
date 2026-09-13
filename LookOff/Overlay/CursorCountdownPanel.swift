import AppKit
import CoreGraphics
import Observation
import SwiftUI

@MainActor
@Observable
final class CursorCountdownLiveState {
    var remaining: TimeInterval = 0
}

@MainActor
final class CursorCountdownController {
    private var panel: OverlayPanel?
    private var follow: DispatchSourceTimer?
    private let live = CursorCountdownLiveState()
    private var hostingInstalled = false
    private var lastOrigin = NSPoint(x: -10_000, y: -10_000)

    func show(remaining: TimeInterval, settings: AppSettings) {
        live.remaining = remaining
        if panel == nil {
            let panel = OverlayPanel(
                frame: NSRect(x: 0, y: 0, width: 148, height: 38),
                allowsKey: false,
                sharingHidden: settings.hideFromRecordings
            )
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.sharingType = settings.hideFromRecordings ? .none : .readOnly
            self.panel = panel
            hostingInstalled = false
        }
        ensureHosting()
        startFollow()
        moveToCursor(force: true)
        panel?.orderFrontRegardless()
    }

    func update(remaining: TimeInterval) {
        live.remaining = remaining
    }

    func hide() {
        follow?.cancel()
        follow = nil
        panel?.orderOut(nil)
        lastOrigin = NSPoint(x: -10_000, y: -10_000)
    }

    private func ensureHosting() {
        guard let panel, !hostingInstalled else { return }
        let hosting = NSHostingView(rootView: CursorCountdownView(live: live))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting
        hostingInstalled = true
    }

    private func startFollow() {
        follow?.cancel()
        let hz: Double = Motion.reduceMotion ? 8 : 12
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / hz, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            self?.moveToCursor(force: false)
        }
        timer.resume()
        follow = timer
    }

    private func moveToCursor(force: Bool) {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 18, y: mouse.y - size.height - 14)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        if !force,
           lastOrigin.x > -9_000,
           abs(origin.x - lastOrigin.x) < 1,
           abs(origin.y - lastOrigin.y) < 1 {
            return
        }
        lastOrigin = origin
        panel.setFrameOrigin(origin)
    }
}

struct CursorCountdownView: View {
    @Bindable var live: CursorCountdownLiveState

    var body: some View {
        HStack(spacing: 8) {
            StatusMarkView(icon: .alert, size: 14)
            Text(TimeFormat.overlay(live.remaining))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(Motion.reduceMotion ? .identity : .numericText())
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lookOffGlass(in: Capsule(style: .continuous))
        .padding(2)
    }
}

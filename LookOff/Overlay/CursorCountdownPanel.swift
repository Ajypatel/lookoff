import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class CursorCountdownController {
    private var panel: OverlayPanel?
    private var follow: DispatchSourceTimer?
    private var remaining: TimeInterval = 0

    func show(remaining: TimeInterval, settings: AppSettings) {
        self.remaining = remaining
        if panel == nil {
            let panel = OverlayPanel(frame: NSRect(x: 0, y: 0, width: 148, height: 38), allowsKey: false, sharingHidden: settings.hideFromRecordings)
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.sharingType = settings.hideFromRecordings ? .none : .readOnly
            self.panel = panel
        }
        install()
        startFollow()
        panel?.orderFrontRegardless()
    }

    func update(remaining: TimeInterval) {
        self.remaining = remaining
        install()
    }

    func hide() {
        follow?.cancel()
        follow = nil
        panel?.orderOut(nil)
    }

    private func install() {
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: CursorCountdownView(remaining: remaining))
        moveToCursor()
    }

    private func startFollow() {
        follow?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0, leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.moveToCursor()
        }
        timer.resume()
        follow = timer
    }

    private func moveToCursor() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 18, y: mouse.y - size.height - 14)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

struct CursorCountdownView: View {
    let remaining: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            StatusMarkView(icon: .alert, size: 14)
            Text(TimeFormat.overlay(remaining))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lookOffGlass(in: Capsule(style: .continuous))
        .padding(2)
    }
}

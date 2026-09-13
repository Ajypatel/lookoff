import AppKit
import SwiftUI

/// Lightweight toast for Smart Pause / idle-return alerts (LookAway-style).
@MainActor
final class StatusToastController {
    private var panel: OverlayPanel?
    private var hideWork: DispatchWorkItem?

    func show(title: String, subtitle: String? = nil, symbol: String? = nil, seconds: TimeInterval = 3.5) {
        hideWork?.cancel()
        let screen = NSScreen.screenUnderMouse ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let size = NSSize(width: 360, height: subtitle == nil ? 58 : 74)
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - 18
        )
        let panel = self.panel ?? OverlayPanel(
            frame: NSRect(origin: origin, size: size),
            allowsKey: false,
            sharingHidden: true
        )
        panel.level = .statusBar
        panel.hasShadow = false
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(
            rootView: StatusToastView(title: title, subtitle: subtitle, symbol: symbol)
        )
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
    }
}

private struct StatusToastView: View {
    let title: String
    let subtitle: String?
    var symbol: String?

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .lookOffGlass(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .lookOffGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(4)
    }
}

import AppKit
import SwiftUI

enum StatusIcon: Equatable {
    case rest
    case alert
    case open
    case off
    case symbol(String)

    static func forSnapshot(_ snapshot: EngineSnapshot) -> StatusIcon {
        if !snapshot.scheduleEnabled || snapshot.phase == .stopped { return .off }
        if snapshot.phase == .onBreak { return .open }
        if snapshot.phase == .headsUp || snapshot.phase == .cursorWarn { return .alert }
        if let reason = snapshot.pauseReason, snapshot.phase != .onBreak {
            return .symbol(reason.menuSymbol)
        }
        return .rest
    }

    var tint: Color {
        switch self {
        case .open: Palette.breakNow
        case .alert: Palette.accent
        case .off: Color.secondary
        case .symbol: Palette.pause
        case .rest: Palette.work
        }
    }
}

/// Brand face in-app. Menu bar uses filled SF Symbols — stroke templates vanish on Tahoe glass.
enum StatusMark {
    static func menuBarName(_ icon: StatusIcon) -> String {
        switch icon {
        case .rest: "eye.fill"
        case .open: "eye.circle.fill"
        case .alert: "bell.fill"
        case .off: "eye.slash.fill"
        case .symbol(let name): name
        }
    }

    static func menuBarImage(
        _ icon: StatusIcon,
        accessibilityDescription: String = "LookOff"
    ) -> NSImage {
        symbolImage(menuBarName(icon), size: 16, accessibilityDescription: accessibilityDescription)
    }

    static func image(
        _ icon: StatusIcon,
        size: CGFloat = 18,
        accessibilityDescription: String = "LookOff"
    ) -> NSImage {
        switch icon {
        case .symbol(let name):
            return symbolImage(name, size: size, accessibilityDescription: accessibilityDescription)
        case .rest, .alert, .open, .off:
            return symbolImage(menuBarName(icon), size: size, accessibilityDescription: accessibilityDescription)
        }
    }

    static func symbolImage(
        _ name: String,
        size: CGFloat,
        accessibilityDescription: String
    ) -> NSImage {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
            ?? NSImage(size: NSSize(width: size, height: size))
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .bold)
            .applying(NSImage.SymbolConfiguration(scale: .medium))
        let configured = base.withSymbolConfiguration(config) ?? base
        configured.isTemplate = true
        configured.accessibilityDescription = accessibilityDescription
        return configured
    }
}

struct StatusMarkView: View {
    var icon: StatusIcon
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: StatusMark.menuBarName(icon))
            .font(.system(size: size * 0.72, weight: .bold))
            .symbolRenderingMode(.hierarchical)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct StatusHeroTile: View {
    var icon: StatusIcon
    var size: CGFloat = 52

    var body: some View {
        StatusMarkView(icon: icon, size: size * 0.46)
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .lookOffGlass(in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(icon.tint.opacity(0.35), lineWidth: 1)
            }
    }
}

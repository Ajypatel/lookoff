import AppKit

/// Menu-bar default (`.accessory`). Flip to `.regular` while Settings / onboarding
/// so the app appears in Dock and Mission Control like a normal windowed app.
@MainActor
enum AppDockPolicy {
    static func showInDock() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func hideFromDockIfNoUserWindows() {
        let hasUserWindow = NSApp.windows.contains { window in
            guard window.isVisible, !window.isSheet else { return false }
            // Ignore status-item / overlay / popover chrome
            if window.level != .normal { return false }
            if window.styleMask.contains(.nonactivatingPanel) { return false }
            return window.title.isEmpty == false || window.contentViewController != nil
        }
        guard !hasUserWindow else { return }
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

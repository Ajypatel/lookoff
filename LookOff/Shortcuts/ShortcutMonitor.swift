import AppKit

@MainActor
final class ShortcutMonitor {
    private var monitor: Any?
    private var settings = AppSettings()
    var onStartBreak: (() -> Void)?
    var onSnooze: (() -> Void)?
    var onPause: (() -> Void)?

    func start(settings: AppSettings) {
        self.settings = settings
        rebind()
    }

    func update(settings: AppSettings) {
        self.settings = settings
        rebind()
    }

    func rebind() {
        stop()
        guard PermissionManager.accessibilityTrusted() else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if matches(settings.shortcutStartBreak, event, flags) {
            onStartBreak?()
        } else if matches(settings.shortcutSnooze, event, flags) {
            onSnooze?()
        } else if matches(settings.shortcutPause, event, flags) {
            onPause?()
        }
    }

    private func matches(_ chord: KeyChord?, _ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard let chord else { return false }
        return event.keyCode == chord.keyCode && flags == chord.modifierFlags
    }
}

enum ShortcutDisplay {
    static func string(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyName(keyCode))
        return parts.joined()
    }

    static func keyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: "A"
        case 1: "S"
        case 2: "D"
        case 3: "F"
        case 11: "B"
        case 35: "P"
        case 49: "Space"
        case 53: "Esc"
        default: "Key \(keyCode)"
        }
    }
}

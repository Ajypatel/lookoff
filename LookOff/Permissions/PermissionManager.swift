import AppKit
import ApplicationServices
import EventKit
import Foundation
import Intents
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LookOff login item failed: \(error.localizedDescription)")
        }
    }
}

enum PermissionState: Equatable {
    case granted
    case denied
    case notDetermined
    case limited

    var label: String {
        switch self {
        case .granted: "On"
        case .denied: "Off"
        case .notDetermined: "Not asked"
        case .limited: "Limited"
        }
    }
}

enum PermissionManager {
    static func accessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func accessibilityState() -> PermissionState {
        accessibilityTrusted() ? .granted : .notDetermined
    }

    /// Prompt only when the user taps Enable. Never at launch.
    static func requestAccessibility() {
        if accessibilityTrusted() { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !AXIsProcessTrusted() {
            openPrivacyPane("Privacy_Accessibility")
        }
    }

    static func calendarState() -> PermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: .granted
        case .denied, .restricted: .denied
        case .writeOnly: .limited
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    static func requestCalendar(store: EKEventStore = EKEventStore()) {
        switch calendarState() {
        case .granted:
            return
        case .denied, .limited:
            openPrivacyPane("Privacy_Calendars")
        case .notDetermined:
            store.requestFullAccessToEvents { _, _ in
                NotificationCenter.default.post(name: .lookOffPermissionsChanged, object: nil)
            }
        }
    }

    static func focusState() -> PermissionState {
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    static func requestFocus() {
        switch focusState() {
        case .granted:
            return
        case .denied:
            openPrivacyPane("Privacy_Focus")
        case .notDetermined, .limited:
            INFocusStatusCenter.default.requestAuthorization { _ in
                NotificationCenter.default.post(name: .lookOffPermissionsChanged, object: nil)
            }
        }
    }

    static func openPrivacyPane(_ fragment: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?\(fragment)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(fragment)"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }
}

extension Notification.Name {
    static let lookOffPermissionsChanged = Notification.Name("lookoff.permissions.changed")
}

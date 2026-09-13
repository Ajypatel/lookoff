import SwiftUI

/// All TCC entries are optional. Schedule, overlays, Smart Pause (apps + Core Audio),
/// wellness, and stats run with nothing granted.
enum LookOffPermission: String, CaseIterable, Identifiable {
    case accessibility
    case calendar
    case focusStatus

    var id: String { rawValue }

    static var onboarding: [LookOffPermission] { [] }
    static var settingsList: [LookOffPermission] { [.accessibility, .calendar, .focusStatus] }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .calendar: "Calendar"
        case .focusStatus: "Focus Status"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .calendar: "calendar"
        case .focusStatus: "moon.fill"
        }
    }

    var why: String {
        switch self {
        case .accessibility:
            "Global hotkeys and postpone-while-typing or dragging. LookOff never drives other apps."
        case .calendar:
            "Pause breaks during timed events you opt into. Event details stay on this Mac."
        case .focusStatus:
            "Pause while a Focus mode with a LookOff filter is on."
        }
    }

    var skipOK: String {
        switch self {
        case .accessibility: "Skip → hotkeys and typing/drag postpone stay off. Idle, meetings, video still work."
        case .calendar: "Skip → calendar pause stays off."
        case .focusStatus: "Skip → Focus Filters stay off."
        }
    }

    var state: PermissionState {
        switch self {
        case .accessibility: PermissionManager.accessibilityState()
        case .calendar: PermissionManager.calendarState()
        case .focusStatus: PermissionManager.focusState()
        }
    }

    var isAuthorized: Bool { state == .granted }

    func request() {
        switch self {
        case .accessibility: PermissionManager.requestAccessibility()
        case .calendar: PermissionManager.requestCalendar()
        case .focusStatus: PermissionManager.requestFocus()
        }
    }
}

struct PermissionExplainRow: View {
    let permission: LookOffPermission
    var onChanged: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(permission.title)
                        .font(.headline)
                    Spacer()
                    Text(permission.state.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(permission.isAuthorized ? .green : .secondary)
                }
                Text(permission.why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !permission.isAuthorized {
                    Text(permission.skipOK)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Button(permission.isAuthorized ? "Recheck" : "Enable") {
                permission.request()
                onChanged?()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

struct PermissionNeededBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Palette.accent)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

import AppIntents
import Foundation

enum LookOffFocusGate {
    static let pauseKey = "lookoff.focusFilter.pauseBreaks"

    static var filterAsksPause: Bool {
        get { UserDefaults.standard.bool(forKey: pauseKey) }
        set { UserDefaults.standard.set(newValue, forKey: pauseKey) }
    }

    @MainActor static var isFocused = false

    @MainActor static var shouldPause: Bool { filterAsksPause && isFocused }
}

struct LookOffFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource { "LookOff" }
    static var description: IntentDescription { IntentDescription("Pause LookOff while this Focus is on.") }

    @Parameter(title: "Pause breaks", default: true)
    var pauseBreaks: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "LookOff",
            subtitle: pauseBreaks ? "Pause breaks" : "Keep running"
        )
    }

    func perform() async throws -> some IntentResult {
        LookOffFocusGate.filterAsksPause = pauseBreaks
        NotificationCenter.default.post(name: .lookOffFocusFilterChanged, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let lookOffFocusFilterChanged = Notification.Name("lookoff.focusFilter.changed")
}

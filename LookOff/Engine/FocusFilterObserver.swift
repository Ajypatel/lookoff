import AppIntents
import Foundation
import Intents

@MainActor
final class FocusFilterObserver {
    private var onChange: (() -> Void)?
    private var timer: Timer?

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        NotificationCenter.default.addObserver(
            forName: .lookOffFocusFilterChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: .lookOffPermissionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func requestAccess() {
        PermissionManager.requestFocus()
        refresh()
    }

    func refresh() {
        guard PermissionManager.focusState() == .granted else {
            LookOffFocusGate.isFocused = false
            onChange?()
            return
        }
        LookOffFocusGate.isFocused = INFocusStatusCenter.default.focusStatus.isFocused == true
        onChange?()
    }
}

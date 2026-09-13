import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppController {
    static let shared = AppController()

    let settingsStore = SettingsStore()
    let engine = BreakEngine()
    let idle = IdleMonitor()
    let pause = SmartPauseCoordinator()
    let wellness = WellnessEngine()
    let overlays = BreakOverlayController()
    let headsUp = HeadsUpController()
    let cursor = CursorCountdownController()
    let wellnessUI = WellnessOverlayController()
    let status = StatusItemController()
    let shortcuts = ShortcutMonitor()
    let sounds = SoundPlayer()
    let toast = StatusToastController()
    let stats = StatsStore()
    let planned = PlannedBreakScheduler()
    let focusObserver = FocusFilterObserver()

    var snapshot = EngineSnapshot.idle
    var settingsTab: SettingsTab = .general
    private var started = false
    private var listenTask: Task<Void, Never>?
    private var wasIdle = false
    private var lastAlertedReason: PauseReason?
    private var wellnessPauseApplied = false
    private var headsUpShownAt: Date?
    private var tempPauseTask: Task<Void, Never>?
    private var plannedTimer: Timer?
    private var lastPlannedSuppress: Bool?

    var settings: AppSettings { settingsStore.settings }

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        status.install(self)
        overlays.onSkip = { [weak self] in self?.skip() }
        overlays.onEnd = { [weak self] in self?.endBreak() }
        overlays.onLock = { ScreenLocker.lock() }
        overlays.onExtend = { [weak self] minutes in self?.extendBreak(minutes: minutes) }
        overlays.onSecondTick = { [weak self] second in
            guard let self else { return }
            self.sounds.playTick(self.settings, second: second)
        }
        overlays.onStage = { [weak self] stage in
            guard let self else { return }
            self.sounds.playStage(stage, settings: self.settings)
        }
        headsUp.onStartNow = { [weak self] in self?.startBreakNow() }
        headsUp.onSnooze = { [weak self] minutes in self?.snooze(minutes: minutes) }
        shortcuts.onStartBreak = { [weak self] in self?.startBreakNow() }
        shortcuts.onSnooze = { [weak self] in self?.snooze(minutes: 5) }
        shortcuts.onPause = { [weak self] in self?.togglePause() }

        idle.start(threshold: settings.idlePauseSeconds) { [weak self] in
            self?.pushIdle()
        }
        pause.start(settings: settings) { [weak self] reason in
            self?.handleSmartPauseChange(reason)
        }
        wellness.start(settings: settings) { [weak self] kind in
            self?.showWellness(kind)
        }
        wellnessUI.onCue = { [weak self] cue, kind in
            guard let self else { return }
            switch cue {
            case .enter: self.sounds.playWellnessEnter(self.settings, kind: kind)
            case .rise: self.sounds.playWellnessRise(self.settings, kind: kind)
            case .blink: self.sounds.playWellnessTick(self.settings, kind: kind)
            case .happy: self.sounds.playWellnessHappy(self.settings, kind: kind)
            case .exit: self.sounds.playWellnessExit(self.settings, kind: kind)
            }
        }
        shortcuts.start(settings: settings)

        planned.onStart = { [weak self] item, remaining in
            self?.startCustomBreak(seconds: remaining, message: item.name)
        }
        let plannedTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickPlanned() }
        }
        plannedTimer.tolerance = 2
        RunLoop.main.add(plannedTimer, forMode: .common)
        self.plannedTimer = plannedTimer

        focusObserver.start { [weak self] in
            self?.pushPause()
        }

        listenTask = Task { [weak self] in
            guard let self else { return }
            await self.engine.setSettings(self.settings)
            for await snap in await self.engine.snapshots() {
                self.apply(snap)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.overlays.handleScreenChange()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }

        if settings.launchAtLogin {
            LoginItem.setEnabled(true)
        }

        if settings.hasCompletedOnboarding {
            if settings.scheduleEnabled {
                Task { await engine.start() }
            }
        } else {
            OnboardingWindowController.shared.show()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebindOptionalInput() }
        }
        NotificationCenter.default.addObserver(
            forName: .lookOffPermissionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebindOptionalInput() }
        }
    }

    func rebindOptionalInput() {
        idle.rebindInputMonitors()
        shortcuts.rebind()
        focusObserver.refresh()
        pushIdle()
        pushPause()
    }

    func settingsDidChange() {
        Task { await engine.setSettings(settings) }
        idle.updateThreshold(settings.idlePauseSeconds)
        pause.update(settings: settings)
        wellness.update(settings: settings)
        shortcuts.update(settings: settings)
        rebindOptionalInput()
        LoginItem.setEnabled(settings.launchAtLogin)
        tickPlanned()
        // Re-evaluate wellness pause when Common settings change
        let hold = wellnessShouldBePaused(for: snapshot)
        if hold != wellnessPauseApplied {
            wellnessPauseApplied = hold
            wellness.setPaused(hold)
            // Do not cancel an on-screen nudge — let it finish while you work.
        }
    }

    func finishOnboarding() {
        settingsStore.settings.hasCompletedOnboarding = true
        settingsStore.settings.scheduleEnabled = true
        Task { await engine.start() }
    }

    func startSchedule() {
        settingsStore.settings.scheduleEnabled = true
        Task { await engine.start() }
        toast.show(title: "LookOff started", subtitle: "Next break in \(Int(settings.workMinutes)) min", symbol: "play.fill")
    }

    func stopSchedule() {
        settingsStore.settings.scheduleEnabled = false
        Task { await engine.stop() }
        headsUp.hide()
        cursor.hide()
        overlays.hide()
        toast.show(title: "LookOff stopped", symbol: "stop.fill")
    }

    func handleWake() {
        Task {
            await engine.handleWake()
            pushIdle()
            pushPause()
        }
    }

    func startBreakNow() {
        guard settings.scheduleEnabled || snapshot.phase == .onBreak else {
            startSchedule()
            return
        }
        Task { await engine.startBreakNow() }
    }

    func skip() {
        Task { await engine.skip() }
    }

    func snooze(minutes: Int) {
        Task { await engine.snooze(minutes: minutes) }
        headsUp.hide()
        cursor.hide()
    }

    func endBreak() {
        Task { await engine.endBreak() }
    }

    func extendBreak(minutes: Int) {
        Task { await engine.extendBreak(minutes: minutes) }
    }

    func startLongBreak() {
        guard settings.scheduleEnabled || snapshot.phase == .onBreak else {
            startSchedule()
            return
        }
        Task { await engine.startLongBreak() }
    }

    func startCustomBreak(seconds: TimeInterval, message: String?) {
        if !settings.scheduleEnabled {
            startSchedule()
        }
        Task { await engine.startCustomBreak(seconds: seconds, message: message) }
    }

    func postponeBreak(seconds: TimeInterval) {
        Task { await engine.postponeBreak(by: seconds) }
        headsUp.hide()
        cursor.hide()
    }

    func pauseFromScript() {
        Task { await engine.pauseManual() }
    }

    func resumeFromScript() {
        Task { await engine.resume() }
    }

    func pauseTemporarily(seconds: TimeInterval) {
        tempPauseTask?.cancel()
        Task { await engine.pauseManual() }
        tempPauseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await engine.resume()
        }
    }

    func togglePause() {
        Task {
            switch snapshot.phase {
            case .manuallyPaused, .idlePaused, .smartPaused:
                await engine.resume()
            case .stopped:
                await engine.start()
            default:
                await engine.pauseManual()
            }
        }
    }

    func openSettings(tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.shared.show()
    }

    func persistStatsNow() {
        stats.flush()
    }

    private func pushIdle() {
        let isIdle = settings.idleAutoPause && idle.isIdle
        let dictating = DictationActivity.isDictating(settings: settings)
        Task {
            await engine.setIdle(active: isIdle, seconds: idle.idleSeconds, spoofWarning: idle.spoofWarning)
            await engine.setTyping(idle.isTyping || dictating)
            await engine.setDragging(idle.isDragging)
        }

        if wasIdle && !isIdle && settings.showHeadsUpAfterIdle {
            toast.show(title: "Welcome back", subtitle: "Break schedule resumed", symbol: "sun.horizon.fill")
            sounds.playIdleReturn(settings)
        }
        wasIdle = isIdle

        if !settings.isOfficeHours() {
            Task { await engine.setSmartPause(.officeHours) }
        }
    }

    private func pushPause() {
        if !settings.isOfficeHours() {
            Task { await engine.setSmartPause(.officeHours) }
            return
        }
        Task {
            await engine.setSmartPause(pause.reason, suppressBreaks: pause.isBreakSuppressed)
        }
    }

    private func handleSmartPauseChange(_ reason: PauseReason?) {
        pushPause()
        guard let reason else {
            lastAlertedReason = nil
            return
        }
        guard reason != lastAlertedReason else { return }
        lastAlertedReason = reason
        guard shouldAlert(for: reason) else { return }
        toast.show(title: reason.alertTitle, symbol: reason.menuSymbol)
        sounds.playSmartPauseAlert(settings)
    }

    private func shouldAlert(for reason: PauseReason) -> Bool {
        switch reason {
        case .meeting: settings.alertOnMeeting
        case .video: settings.alertOnVideo
        case .recording: settings.alertOnRecording
        case .calendar: settings.alertOnCalendar
        case .focus, .systemFocus: settings.alertOnFocus
        case .game: settings.alertOnGame
        default: false
        }
    }

    func previewWellness(_ kind: WellnessEngine.Kind) {
        // Do not activate LookOff — keeps focus in whatever app you are using.
        wellnessUI.show(
            kind: kind,
            settings: settings,
            recordingActive: false,
            durationOverride: max(8.0, settings.wellnessDurationSeconds + 3.0)
        )
    }

    func previewWellnessBoth() {
        previewWellness(.posture)
        let gap = max(8.2, settings.wellnessDurationSeconds + 3.2)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            previewWellness(.blink)
        }
    }

    private func showWellness(_ kind: WellnessEngine.Kind) {
        guard snapshot.phase != .onBreak else { return }
        if shouldHoldWellnessForPause { return }
        wellnessUI.show(kind: kind, settings: settings, recordingActive: pause.reason == .recording)
    }

    /// When “keep during smart-pause” is off, suppress nudges while paused.
    private var shouldHoldWellnessForPause: Bool {
        guard !settings.wellnessDuringSmartPause else { return false }
        switch snapshot.phase {
        case .smartPaused, .idlePaused, .manuallyPaused, .stopped:
            return true
        default:
            return false
        }
    }

    private func syncWellnessPause(previous: EngineSnapshot, current: EngineSnapshot) {
        let hold = wellnessShouldBePaused(for: current)
        guard hold != wellnessPauseApplied else { return }
        wellnessPauseApplied = hold
        wellness.setPaused(hold)
        // Pause future timers only — never yank a nudge mid-animation on click/idle/smart-pause.
        _ = previous
    }

    private func wellnessShouldBePaused(for snap: EngineSnapshot) -> Bool {
        if snap.phase == .onBreak { return true }
        if !settings.wellnessDuringSmartPause {
            switch snap.phase {
            case .smartPaused, .idlePaused, .manuallyPaused, .stopped:
                return true
            default:
                break
            }
        }
        return false
    }

    private func apply(_ snapshot: EngineSnapshot) {
        let previous = self.snapshot
        self.snapshot = snapshot
        status.apply(snapshot)
        overlays.apply(snapshot: snapshot, settings: settings)
        stats.ingest(snapshot: snapshot, previous: previous, workMinutes: settings.workMinutes)

        switch snapshot.phase {
        case .headsUp:
            if previous.phase != .headsUp || !headsUp.isVisible {
                headsUp.show(
                    settings: settings,
                    remaining: snapshot.remaining,
                    breakSeconds: settings.shortBreakDuration
                )
                headsUpShownAt = Date()
                if settings.headsUpSoundEnabled, previous.phase != .headsUp {
                    sounds.playNudge(settings)
                }
            } else {
                headsUp.update(remaining: snapshot.remaining)
                if settings.headsUpStaySeconds > 0,
                   let shown = headsUpShownAt,
                   Date().timeIntervalSince(shown) >= settings.headsUpStaySeconds,
                   headsUp.isVisible {
                    headsUp.hide()
                }
            }
            cursor.hide()
            // Leave wellness alone — short nudge must finish; clicks pass through.
        case .cursorWarn:
            // Last seconds: cursor countdown takes over; hide the top toast once.
            if headsUp.isVisible { headsUp.hide() }
            if previous.phase != .cursorWarn {
                cursor.show(remaining: snapshot.remaining, settings: settings)
            } else {
                cursor.update(remaining: snapshot.remaining)
            }
        case .onBreak:
            headsUp.hide()
            cursor.hide()
            wellnessUI.hide()
        default:
            // Don't tear down heads-up on brief smart-pause blips if we were mid-heads-up —
            // only hide when truly leaving the approach window.
            if previous.phase == .headsUp || previous.phase == .cursorWarn {
                headsUp.hide()
                cursor.hide()
            } else if snapshot.phase != .smartPaused && snapshot.phase != .idlePaused {
                headsUp.hide()
                cursor.hide()
            }
        }

        syncWellnessPause(previous: previous, current: snapshot)

        switch snapshot.event {
        case .breakStarted:
            AutomationRunner.run(settings.automations, trigger: .breakStart)
            if settings.lockMacOnBreakStart {
                ScreenLocker.lock()
            }
        case .breakEnded, .idleCountedAsBreak:
            sounds.playEnd(settings)
            AutomationRunner.run(settings.automations, trigger: .breakEnd)
        case .breakSkipped:
            AutomationRunner.run(settings.automations, trigger: .breakEnd)
        case .overtimeNudge:
            sounds.playOvertime(settings)
            toast.show(title: "Overtime", subtitle: "A break is waiting — wrap up when you can", symbol: "clock.badge.exclamationmark")
        case .headsUp, .none:
            break
        }
        tickPlanned()
    }

    private func tickPlanned() {
        let busy: Bool = {
            switch snapshot.phase {
            case .smartPaused, .manuallyPaused, .idlePaused: true
            default: false
            }
        }()
        planned.evaluate(
            breaks: settings.plannedBreaks,
            isBusy: busy || LookOffFocusGate.shouldPause,
            isIdle: settings.idleAutoPause && idle.isIdle,
            idleSeconds: idle.idleSeconds,
            onBreak: snapshot.phase == .onBreak,
            scheduleRunning: settings.scheduleEnabled && snapshot.phase != .stopped
        )
        let suppress = planned.suppressRegular
        guard lastPlannedSuppress != suppress else { return }
        lastPlannedSuppress = suppress
        Task { await engine.setPlannedSuppress(suppress) }
    }
}

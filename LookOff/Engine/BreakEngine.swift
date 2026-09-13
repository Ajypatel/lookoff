import Foundation

actor BreakEngine {
    private var settings = AppSettings()
    private var phase: BreakPhase = .stopped
    private var endsAt = Date()
    private var frozenRemaining: TimeInterval = 0
    private var isLongBreak = false
    private var completedShorts = 0
    private var skipUnlockedAt: Date?
    private var breakStartedAt: Date?
    private var breakDurationTotal: TimeInterval = 0
    private var currentMessage = ""
    private var currentInstruction = ""
    private var lastMessage = ""
    private var lastInstruction = ""
    private var pendingEvent: EngineEvent = .none
    private var smartReason: PauseReason?
    private var smartBreakSuppressed = false
    private var idleActive = false
    private var idleSeconds: TimeInterval = 0
    private var typing = false
    private var dragging = false
    private var idleSpoofWarning = false
    private var overdueHeld = false
    private var overtimeNudged = false
    private var plannedSuppress = false
    private var idleBreakConsumed = false
    /// True when schedule should run. Distinct from phase so wake can recover.
    private var scheduleEnabled = true
    private var timer: DispatchSourceTimer?
    private var continuation: AsyncStream<EngineSnapshot>.Continuation?
    private let timerQueue = DispatchQueue(label: "in.kamero.lookoff.engine", qos: .userInitiated)

    func snapshots() -> AsyncStream<EngineSnapshot> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            Task { await self.bind(continuation) }
            continuation.onTermination = { _ in
                Task { await self.clearContinuation() }
            }
        }
    }

    private func bind(_ continuation: AsyncStream<EngineSnapshot>.Continuation) {
        self.continuation = continuation
        continuation.yield(snapshot())
    }

    func setSettings(_ settings: AppSettings) {
        self.settings = settings
        scheduleEnabled = settings.scheduleEnabled
        if scheduleEnabled, phase == .stopped {
            startWork()
        } else if !scheduleEnabled, phase != .stopped {
            phase = .stopped
            stopTimer()
        }
        yield()
    }

    func setSmartPause(_ reason: PauseReason?, suppressBreaks: Bool = false) {
        smartReason = reason
        smartBreakSuppressed = suppressBreaks
        tick()
    }

    func setIdle(active: Bool, seconds: TimeInterval, spoofWarning: Bool) {
        idleActive = active
        idleSeconds = seconds
        idleSpoofWarning = spoofWarning
        tick()
    }

    func setTyping(_ typing: Bool) {
        self.typing = typing
        tick()
    }

    func setDragging(_ dragging: Bool) {
        self.dragging = dragging
        tick()
    }

    func setPlannedSuppress(_ suppress: Bool) {
        plannedSuppress = suppress
        tick()
    }

    func start() {
        scheduleEnabled = true
        if phase == .stopped || phase == .manuallyPaused {
            startWork()
        }
        startTimer()
        yield()
    }

    func stop() {
        scheduleEnabled = false
        phase = .stopped
        smartReason = nil
        idleActive = false
        stopTimer()
        yield()
    }

    func pauseManual() {
        guard isLiveCountdown else { return }
        freeze()
        phase = .manuallyPaused
        yield()
    }

    func resume() {
        guard scheduleEnabled else {
            start()
            return
        }
        switch phase {
        case .manuallyPaused, .smartPaused, .idlePaused:
            thaw()
        case .stopped:
            startWork()
        default:
            break
        }
        startTimer()
        yield()
    }

    /// After sleep/wake: revive timer, credit long away as break, start fresh work like LookAway.
    func handleWake() {
        guard scheduleEnabled else {
            phase = .stopped
            yield()
            return
        }
        startTimer()

        let overdue = endsAt.timeIntervalSinceNow < -5
        let longAway = idleSeconds >= settings.idleResetSeconds

        if phase == .stopped {
            startWork()
            return
        }

        // Slept through a work interval or were away long enough — fresh cycle, no instant break dump.
        if overdue || (longAway && (phase == .idlePaused || phase == .working || phase == .headsUp || phase == .cursorWarn || phase == .smartPaused || phase == .snoozed)) {
            idleBreakConsumed = false
            idleActive = false
            startWork()
            return
        }

        tick()
    }

    func startBreakNow() {
        beginBreak()
    }

    func startLongBreak() {
        completedShorts = max(settings.shortsBeforeLong, 1)
        beginBreak(forceLong: true)
    }

    func startCustomBreak(seconds: TimeInterval, message: String?) {
        let duration = min(max(seconds, 5), 2 * 60 * 60)
        isLongBreak = false
        phase = .onBreak
        breakStartedAt = Date()
        endsAt = Date().addingTimeInterval(duration)
        frozenRemaining = duration
        breakDurationTotal = duration
        skipUnlockedAt = Date().addingTimeInterval(settings.skipMode == .balanced ? settings.skipUnlockSeconds : 0)
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        currentMessage = trimmed.isEmpty ? pickMessage() : trimmed
        currentInstruction = pickInstruction()
        pendingEvent = .breakStarted
        startTimer(fast: true)
        yield()
        pendingEvent = .none
    }

    func postponeBreak(by seconds: TimeInterval) {
        let duration = max(seconds, 5)
        endsAt = Date().addingTimeInterval(duration)
        frozenRemaining = duration
        isLongBreak = false
        breakStartedAt = nil
        skipUnlockedAt = nil
        phase = .snoozed
        pendingEvent = .none
        startTimer()
        yield()
    }

    func skip() {
        guard phase == .onBreak, snapshot().skipAllowed else { return }
        pendingEvent = .breakSkipped
        startWork()
        pendingEvent = .none
    }

    /// Add time to the active break (LookAway +1 / +5 min).
    func extendBreak(minutes: Int) {
        guard phase == .onBreak, minutes > 0 else { return }
        let extra = TimeInterval(minutes * 60)
        endsAt = endsAt.addingTimeInterval(extra)
        breakDurationTotal += extra
        frozenRemaining = max(0, endsAt.timeIntervalSinceNow)
        yield()
    }

    func snooze(minutes: Int) {
        let duration = TimeInterval(minutes * 60)
        endsAt = Date().addingTimeInterval(duration)
        frozenRemaining = duration
        isLongBreak = false
        breakStartedAt = nil
        skipUnlockedAt = nil
        phase = .snoozed
        pendingEvent = .none
        startTimer()
        yield()
    }

    func endBreak() {
        guard phase == .onBreak else { return }
        finishBreak(countShort: true)
    }

    private func clearContinuation() {
        continuation = nil
    }

    private var isLiveCountdown: Bool {
        switch phase {
        case .working, .headsUp, .cursorWarn, .snoozed:
            true
        default:
            false
        }
    }

    private func startWork() {
        phase = .working
        isLongBreak = false
        breakStartedAt = nil
        skipUnlockedAt = nil
        breakDurationTotal = 0
        endsAt = Date().addingTimeInterval(settings.workDuration)
        frozenRemaining = settings.workDuration
        currentMessage = pickMessage()
        currentInstruction = pickInstruction()
        overtimeNudged = false
        overdueHeld = false
        startTimer()
        yield()
    }

    private func beginBreak(forceLong: Bool = false) {
        isLongBreak = forceLong || (settings.longBreakEnabled && completedShorts >= max(1, settings.shortsBeforeLong))
        let duration = isLongBreak ? settings.longBreakDuration : settings.shortBreakDuration
        phase = .onBreak
        breakStartedAt = Date()
        endsAt = Date().addingTimeInterval(duration)
        frozenRemaining = duration
        breakDurationTotal = duration
        skipUnlockedAt = Date().addingTimeInterval(settings.skipMode == .balanced ? settings.skipUnlockSeconds : 0)
        currentMessage = pickMessage()
        currentInstruction = pickInstruction()
        pendingEvent = .breakStarted
        startTimer(fast: true)
        yield()
        pendingEvent = .none
    }

    private func finishBreak(countShort: Bool) {
        if countShort, !isLongBreak {
            completedShorts += 1
        }
        if isLongBreak {
            completedShorts = 0
        }
        pendingEvent = .breakEnded
        startWork()
        pendingEvent = .none
    }

    private func freeze() {
        frozenRemaining = max(0, endsAt.timeIntervalSinceNow)
    }

    private func thaw() {
        endsAt = Date().addingTimeInterval(max(0, frozenRemaining))
        phase = phaseForRemaining(frozenRemaining)
        if phase == .onBreak {
            beginBreak()
        }
    }

    private func phaseForRemaining(_ remaining: TimeInterval) -> BreakPhase {
        if remaining <= 0 { return .onBreak }
        if remaining <= settings.cursorCountdownSeconds { return .cursorWarn }
        if remaining <= settings.reminderLeadSeconds { return .headsUp }
        return .working
    }

    private func startTimer(fast: Bool? = nil) {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        let interval: TimeInterval = {
            if let fast, fast { return 0.2 }
            switch phase {
            case .onBreak, .cursorWarn, .headsUp, .snoozed:
                return 0.2
            default:
                return 1
            }
        }()
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(80))
        source.setEventHandler { [weak self] in
            Task { await self?.tick() }
        }
        source.resume()
        timer = source
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        if phase == .stopped {
            yield()
            return
        }

        if phase == .onBreak {
            let remaining = max(0, endsAt.timeIntervalSinceNow)
            if remaining <= 0, !settings.keepUntilEndBreak {
                finishBreak(countShort: true)
                return
            }
            yield()
            return
        }

        if phase == .manuallyPaused {
            yield()
            return
        }

        if let smartReason, smartReason != .idle, smartReason != .officeHours {
            if phase != .smartPaused {
                freeze()
                phase = .smartPaused
            }
            yield()
            return
        }

        if smartReason == .officeHours {
            if phase != .smartPaused {
                freeze()
                phase = .smartPaused
            }
            yield()
            return
        }

        if idleActive, phase != .idlePaused {
            freeze()
            phase = .idlePaused
            idleBreakConsumed = false
            yield()
            return
        }

        if phase == .idlePaused {
            if idleActive {
                if settings.countIdleAsBreak, !idleBreakConsumed, idleSeconds >= settings.idleResetSeconds {
                    idleBreakConsumed = true
                    pendingEvent = .idleCountedAsBreak
                    yield()
                    pendingEvent = .none
                    return
                }
                yield()
                return
            }
            // Returned from idle — LookAway starts a fresh work interval after away-as-break.
            if idleBreakConsumed {
                idleBreakConsumed = false
                startWork()
                return
            }
            thaw()
            yield()
            return
        }

        if phase == .smartPaused {
            if smartReason == nil, !idleActive {
                thaw()
            }
            yield()
            return
        }

        let remaining = max(0, endsAt.timeIntervalSinceNow)
        frozenRemaining = remaining

        // If the Mac slept through the whole work window, don't dump into a break — fresh cycle.
        if remaining <= 0, idleSeconds >= settings.idlePauseSeconds {
            startWork()
            return
        }

        if remaining <= 0 {
            if shouldPostpone || smartBreakSuppressed || plannedSuppress {
                if !overdueHeld {
                    overdueHeld = true
                }
                if settings.overtimeNudgeEnabled, !overtimeNudged, overdueHeld {
                    overtimeNudged = true
                    pendingEvent = .overtimeNudge
                    yield()
                    pendingEvent = .none
                }
                // Hold just above break without phase thrashing (was +2s → flicker)
                endsAt = Date().addingTimeInterval(max(settings.cursorCountdownSeconds, 8))
                if phase != .cursorWarn && phase != .headsUp {
                    phase = .headsUp
                }
                yield()
                return
            }
            beginBreak()
            return
        }

        let next = remaining <= settings.cursorCountdownSeconds
            ? BreakPhase.cursorWarn
            : remaining <= settings.reminderLeadSeconds ? .headsUp : (phase == .snoozed ? .snoozed : .working)

        if next == .headsUp, phase != .headsUp, phase != .cursorWarn {
            pendingEvent = .headsUp
            phase = next
            startTimer(fast: true)
            yield()
            pendingEvent = .none
            return
        }

        if next != phase, next != .working || phase != .snoozed {
            phase = next
            startTimer(fast: next != .working)
        }
        yield()
    }

    private var shouldPostpone: Bool {
        (settings.postponeOnTyping && typing) || (settings.postponeOnDragging && dragging)
    }

    private func snapshot() -> EngineSnapshot {
        let remaining: TimeInterval = {
            switch phase {
            case .manuallyPaused, .smartPaused, .idlePaused, .stopped:
                frozenRemaining
            default:
                max(0, endsAt.timeIntervalSinceNow)
            }
        }()

        let total: TimeInterval = {
            switch phase {
            case .onBreak:
                breakDurationTotal > 0
                    ? breakDurationTotal
                    : (isLongBreak ? settings.longBreakDuration : settings.shortBreakDuration)
            case .snoozed:
                max(remaining, 1)
            default:
                settings.workDuration
            }
        }()

        let elapsed = max(0, total - remaining)
        let skipAllowed: Bool = {
            guard phase == .onBreak else { return false }
            switch settings.skipMode {
            case .hardcore: return false
            case .casual: return true
            case .balanced:
                guard let skipUnlockedAt else { return false }
                return Date() >= skipUnlockedAt
            }
        }()

        let skipUnlockProgress: Double = {
            guard phase == .onBreak else { return 1 }
            switch settings.skipMode {
            case .casual, .hardcore:
                return skipAllowed ? 1 : 0
            case .balanced:
                let window = max(settings.skipUnlockSeconds, 0.1)
                guard let skipUnlockedAt else { return 0 }
                let remainingUnlock = skipUnlockedAt.timeIntervalSinceNow
                if remainingUnlock <= 0 { return 1 }
                return max(0, min(1, 1 - remainingUnlock / window))
            }
        }()

        let endEarlyAllowed = phase == .onBreak
            && total > 0
            && (elapsed / total) * 100 >= settings.endEarlyAfterPercent

        let reason: PauseReason? = {
            switch phase {
            case .manuallyPaused: return .manual
            case .idlePaused: return .idle
            case .smartPaused: return smartReason ?? .manual
            default: return nil
            }
        }()

        let menuTitle: String = {
            // Short pause label (bright) — easier to read than dimmed timer
            if let reason, phase != .onBreak {
                return reason.shortMenuLabel
            }
            switch phase {
            case .onBreak: return TimeFormat.overlay(remaining)
            case .stopped: return scheduleEnabled ? "…" : "Off"
            default: return TimeFormat.menu(remaining)
            }
        }()

        return EngineSnapshot(
            phase: phase,
            remaining: remaining,
            total: total,
            isLongBreak: isLongBreak,
            skipAllowed: skipAllowed,
            skipUnlockProgress: skipUnlockProgress,
            endEarlyAllowed: endEarlyAllowed || (phase == .onBreak && settings.keepUntilEndBreak && remaining <= 0),
            pauseReason: reason,
            menuTitle: menuTitle,
            completedShorts: completedShorts,
            message: currentMessage,
            instruction: currentInstruction,
            event: pendingEvent,
            idleSpoofWarning: idleSpoofWarning,
            scheduleEnabled: scheduleEnabled
        )
    }

    private func pickMessage() -> String {
        let custom = settings.overlayMessages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let source = AppSettings.defaultMessages + custom
        let picked = Self.randomAvoiding(last: lastMessage, from: source) ?? "Rest your eyes."
        lastMessage = picked
        return picked
    }

    private func pickInstruction() -> String {
        let custom = settings.breakInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let stock = Set(AppSettings.defaultInstructions)
        if !custom.isEmpty, !stock.contains(custom), custom != AppSettings.defaultInstruction {
            return custom
        }
        let picked = Self.randomAvoiding(last: lastInstruction, from: AppSettings.defaultInstructions)
            ?? AppSettings.defaultInstruction
        lastInstruction = picked
        return picked
    }

    private static func randomAvoiding(last: String, from pool: [String]) -> String? {
        let choices = pool.filter { $0 != last }
        return (choices.isEmpty ? pool : choices).randomElement()
    }

    private func yield() {
        continuation?.yield(snapshot())
    }
}

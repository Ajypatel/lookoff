import AppKit
import CoreAudio
import CoreGraphics
import EventKit

@MainActor
final class SmartPauseCoordinator {
    private var timer: DispatchSourceTimer?
    private var lastActiveReason: PauseReason?
    private var lastActiveAt: Date?
    private(set) var reason: PauseReason?
    /// After a smart pause ends, suppress *starting* a break for this long — timer still runs.
    private(set) var breakSuppressedUntil: Date?
    private var settings = AppSettings()
    private var onChange: ((PauseReason?) -> Void)?
    private let calendarStore = EKEventStore()
    private var frontmostObserver: NSObjectProtocol?

    func start(settings: AppSettings, onChange: @escaping (PauseReason?) -> Void) {
        self.settings = settings
        self.onChange = onChange
        stop()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // LookAway-ish: react in ~1s, not 2s
        timer.schedule(deadline: .now(), repeating: 0.75, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.evaluate()
        }
        timer.resume()
        self.timer = timer

        // Instant clear/set when user switches apps (e.g. leave YouTube → Cursor)
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluate()
        }
        evaluate()
    }

    func update(settings: AppSettings) {
        self.settings = settings
        if settings.pauseOnCalendar {
            CalendarAccess.requestIfNeeded(store: calendarStore)
        }
        evaluate()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
            self.frontmostObserver = nil
        }
    }

    var isBreakSuppressed: Bool {
        guard let breakSuppressedUntil else { return false }
        return Date() < breakSuppressedUntil
    }

    private func evaluate() {
        let detected = detect()
        let now = Date()
        if let detected {
            lastActiveReason = detected
            lastActiveAt = now
            publish(detected)
            return
        }
        // Detection gone → clear status + resume timer immediately (LookAway).
        // Cooldown only delays the *next break*, it must not keep showing Video / stay paused.
        if lastActiveReason != nil {
            let cool = settings.pauseCooldownSeconds
            if cool > 0 {
                breakSuppressedUntil = now.addingTimeInterval(cool)
            }
            lastActiveReason = nil
        }
        publish(nil)
    }

    private func publish(_ reason: PauseReason?) {
        guard self.reason != reason else { return }
        self.reason = reason
        onChange?(reason)
    }

    private func detect() -> PauseReason? {
        if LookOffFocusGate.shouldPause { return .systemFocus }
        if settings.pauseOnMeeting, isMeeting() { return .meeting }
        if settings.pauseOnRecording, isRecording() { return .recording }
        if settings.pauseOnVideo, isVideo() { return .video }
        if settings.pauseOnCalendar, isCalendarEvent() { return .calendar }
        if settings.pauseOnGames, isFullscreenGame() { return .game }
        if settings.pauseOnFocusApps, isFocusApp() { return .focus }
        return nil
    }

    // MARK: - Meetings

    private func isMeeting() -> Bool {
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let frontID, settings.meetingDenyBundleIDs.contains(frontID) { return false }
        if let frontID, settings.dictationBundleIDs.contains(frontID) { return false }

        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if !settings.meetingAllowBundleIDs.isEmpty {
            return settings.meetingAllowBundleIDs.contains { running.contains($0) }
        }

        switch settings.meetingDetectMode {
        case .meetingApps:
            return knownMeetingApps.contains(where: { running.contains($0) })
        case .microphone:
            // Core Audio "in use" — no Microphone TCC prompt
            guard AudioActivity.inputRunning() else { return false }
            if knownMeetingApps.contains(where: { running.contains($0) }) { return true }
            // Mic busy + not a deny/dictation frontmost app
            if let frontID, settings.meetingDenyBundleIDs.contains(frontID) { return false }
            return true
        }
    }

    private var knownMeetingApps: Set<String> {
        [
            "us.zoom.xos",
            "com.microsoft.teams2",
            "com.microsoft.teams",
            "com.apple.FaceTime",
            "com.apple.TelephonyUtilities",
            "com.cisco.webexmeetingsapp",
            "com.hnc.Discord",
            "com.tinyspeck.slackmacgap"
        ]
    }

    // MARK: - Recording / Video / Calendar

    private func isRecording() -> Bool {
        let deny = Set(settings.recordingDenyBundleIDs)
        let recorders: Set<String> = [
            "com.obsproject.obs-studio",
            "com.apple.QuickTimePlayerX",
            "com.loom.desktop",
            "com.kap.desktop",
            "com.telestream.screenflow",
            "com.reincubate.macos.camo",
            "com.apple.screencaptureui"
        ]
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return running.contains(where: { recorders.contains($0) && !deny.contains($0) })
    }

    private func isVideo() -> Bool {
        let deny = settings.videoDenyBundleIDs
        if settings.videoFrontmostOnly {
            return MediaPlaybackDetector.isVideoPlaying(frontmostOnly: true, denyBundleIDs: deny)
        }
        // "Playing anywhere": native players can be background; browsers stay frontmost-only
        // so switching away from YouTube resumes the timer (LookAway-like).
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           MediaPlaybackDetector.isLikelyBrowser(front) {
            return MediaPlaybackDetector.isVideoPlaying(frontmostOnly: true, denyBundleIDs: deny)
        }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           !MediaPlaybackDetector.isMediaSurface(front) {
            // In Cursor/etc. — only pause for background *native* players with audio
            guard AudioActivity.outputRunning() else { return false }
            return NSWorkspace.shared.runningApplications.contains { app in
                guard let id = app.bundleIdentifier else { return false }
                return MediaPlaybackDetector.isNativePlayer(id) && !deny.contains(id)
            }
        }
        return MediaPlaybackDetector.isVideoPlaying(frontmostOnly: false, denyBundleIDs: deny)
    }

    private func isCalendarEvent() -> Bool {
        CalendarAccess.hasOngoingTimedEvent(store: calendarStore)
    }

    // MARK: - Games / Focus

    private func isFullscreenGame() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if front.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        guard isLikelyGame(front), isFullscreen(pid: front.processIdentifier) else { return false }
        return true
    }

    private func isLikelyGame(_ app: NSRunningApplication) -> Bool {
        if let url = app.bundleURL,
           let cat = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
           cat.contains("games") {
            return true
        }
        let id = app.bundleIdentifier?.lowercased() ?? ""
        return id.contains("steam") || id.contains("epicgames") || id.contains("valvesoftware")
    }

    private func isFocusApp() -> Bool {
        let running = NSWorkspace.shared.runningApplications
        let front = NSWorkspace.shared.frontmostApplication
        for item in settings.focusApps {
            guard let app = running.first(where: { $0.bundleIdentifier == item.bundleID }) else { continue }
            switch item.match {
            case .open:
                return true
            case .foreground:
                if front?.bundleIdentifier == item.bundleID { return true }
            case .foregroundFullscreen:
                if front?.bundleIdentifier == item.bundleID, isFullscreen(pid: app.processIdentifier) {
                    return true
                }
            }
        }
        return false
    }

    private func isFullscreen(pid: pid_t) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let screens = NSScreen.screens.map(\.frame)
        for window in info {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            for screen in screens {
                if abs(rect.width - screen.width) < 8, abs(rect.height - screen.height) < 8 {
                    return true
                }
            }
        }
        return false
    }
}

enum CalendarAccess {
    static func requestIfNeeded(store: EKEventStore) {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            store.requestFullAccessToEvents { _, _ in }
        default:
            break
        }
    }

    static func hasOngoingTimedEvent(store: EKEventStore) -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else { return false }
        let now = Date()
        let end = now.addingTimeInterval(90)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return events.contains { event in
            guard !event.isAllDay,
                  let start = event.startDate,
                  let finish = event.endDate,
                  start <= now,
                  finish > now else { return false }
            // Ignore tiny reminders (< 5 min)
            return finish.timeIntervalSince(start) >= 5 * 60
        }
    }
}

enum AudioActivity {
    static func inputRunning() -> Bool {
        deviceRunning(scope: kAudioObjectPropertyScopeInput)
    }

    static func outputRunning() -> Bool {
        deviceRunning(scope: kAudioObjectPropertyScopeOutput)
    }

    private static func deviceRunning(scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return false
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices) == noErr else {
            return false
        }
        for device in devices {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: scope,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}

enum DictationActivity {
    static func isDictating(settings: AppSettings) -> Bool {
        guard settings.postponeOnDictation else { return false }
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        guard settings.dictationBundleIDs.contains(front) else { return false }
        return AudioActivity.inputRunning()
    }
}

import AppKit
import Foundation
import SwiftUI

enum BreakPhase: String, Sendable, Equatable {
    case stopped
    case working
    case headsUp
    case cursorWarn
    case onBreak
    case snoozed
    case smartPaused
    case idlePaused
    case manuallyPaused
}

enum PauseReason: String, Sendable, Equatable, CaseIterable {
    case meeting = "Meeting"
    case recording = "Rec"
    case video = "Video"
    case focus = "Focus"
    case game = "Game"
    case calendar = "Calendar"
    case typing = "Typing"
    case drag = "Drag"
    case idle = "Idle"
    case officeHours = "Off hours"
    case systemFocus = "Focus mode"
    case manual = "Paused"

    /// LookAway-style menu bar label — make pause reason obvious.
    var statusBarTitle: String {
        switch self {
        case .idle: "Paused · idle"
        case .video: "Paused · Video"
        case .meeting: "Paused · Meeting"
        case .recording: "Paused · Rec"
        case .focus: "Paused · Focus"
        case .game: "Paused · Game"
        case .calendar: "Paused · Cal"
        case .manual: "Paused"
        case .officeHours: "Off hours"
        case .systemFocus: "Paused · Focus mode"
        case .typing: "Paused · Typing"
        case .drag: "Paused · Drag"
        }
    }

    var alertTitle: String {
        switch self {
        case .meeting: "Meeting detected — breaks paused"
        case .recording: "Screen recording — breaks paused"
        case .video: "Video playback — breaks paused"
        case .focus: "Focus app — breaks paused"
        case .game: "Gaming — breaks paused"
        case .calendar: "Calendar event — breaks paused"
        case .systemFocus: "Focus mode — breaks paused"
        case .idle: "Welcome back"
        default: "Smart Pause"
        }
    }

    /// Short status-bar word. Icon already carries the meaning.
    var shortMenuLabel: String {
        switch self {
        case .idle: "Idle"
        case .video: "Video"
        case .meeting: "Meeting"
        case .recording: "Rec"
        case .focus: "Focus"
        case .game: "Game"
        case .calendar: "Cal"
        case .manual: "Paused"
        case .officeHours: "Off"
        case .systemFocus: "Focus"
        case .typing: "Type"
        case .drag: "Drag"
        }
    }

    var menuSymbol: String {
        switch self {
        case .idle: "cup.and.saucer.fill"
        case .video: "video.fill"
        case .meeting: "headphones"
        case .recording: "record.circle"
        case .focus: "app.badge.fill"
        case .game: "gamecontroller.fill"
        case .calendar: "calendar"
        case .manual: "pause.fill"
        case .officeHours: "clock.fill"
        case .systemFocus: "moon.fill"
        case .typing: "keyboard.fill"
        case .drag: "hand.draw.fill"
        }
    }
}

enum MeetingDetectMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case meetingApps
    case microphone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .meetingApps: "Meeting apps"
        case .microphone: "Microphone (in use)"
        }
    }
}

enum EngineEvent: Sendable, Equatable {
    case none
    case breakStarted
    case breakEnded
    case breakSkipped
    case headsUp
    case overtimeNudge
    case idleCountedAsBreak
}

enum SkipMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case casual
    case balanced
    case hardcore
    var id: String { rawValue }
    var title: String {
        switch self {
        case .casual: "Casual"
        case .balanced: "Balanced"
        case .hardcore: "Hardcore"
        }
    }
    var detail: String {
        switch self {
        case .casual: "Skip anytime"
        case .balanced: "Skip after a short delay"
        case .hardcore: "No skip during rest"
        }
    }

    var lookAwayDetail: String {
        switch self {
        case .casual: "Skip anytime"
        case .balanced: "Skip after a pause"
        case .hardcore: "No skips allowed"
        }
    }

    var glyph: String {
        switch self {
        case .casual: "chevron.forward.2"
        case .balanced: "pause.circle"
        case .hardcore: "minus.circle"
        }
    }
}

enum BackgroundStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case desktop
    case gradient
    case orbs
    case particles
    case wallpaper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .desktop: "Desktop wallpaper"
        case .gradient: "Gradient wash"
        case .orbs: "Soft orbs"
        case .particles: "Drift"
        case .wallpaper: "Custom image"
        }
    }
}

enum SoundPair: String, Codable, CaseIterable, Identifiable, Sendable {
    case lookoffDefault
    case tibetanBells
    case piano
    case indianFlute
    case bubblesPop
    case harp
    case whoosh
    case twinkle
    case classic
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lookoffDefault: "Default"
        case .tibetanBells: "Tibetan bells"
        case .piano: "Piano"
        case .indianFlute: "Indian flute"
        case .bubblesPop: "Bubbles pop"
        case .harp: "Harp"
        case .whoosh: "Whoosh"
        case .twinkle: "Twinkle"
        case .classic: "Classic"
        case .custom: "Custom"
        }
    }

    /// Bundled wav first; system sound as fallback.
    var enterSystemSound: String {
        switch self {
        case .lookoffDefault, .classic: "Glass"
        case .tibetanBells: "Glass"
        case .piano: "Pop"
        case .indianFlute: "Bottle"
        case .bubblesPop: "Blow"
        case .harp: "Purr"
        case .whoosh: "Submarine"
        case .twinkle: "Ping"
        case .custom: "Glass"
        }
    }

    var exitSystemSound: String {
        switch self {
        case .lookoffDefault, .classic: "Purr"
        case .tibetanBells: "Purr"
        case .piano: "Pop"
        case .indianFlute: "Bottle"
        case .bubblesPop: "Tink"
        case .harp: "Purr"
        case .whoosh: "Submarine"
        case .twinkle: "Ping"
        case .custom: "Purr"
        }
    }
}

enum WellnessPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
    case activeScreen
    case allScreens
    case chosenDisplay
    var id: String { rawValue }
    var title: String {
        switch self {
        case .activeScreen: "Active screen"
        case .allScreens: "All screens"
        case .chosenDisplay: "Chosen display"
        }
    }
}

enum WellnessSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
    var pointSize: CGFloat {
        switch self {
        case .small: 88
        case .medium: 120
        case .large: 152
        }
    }
}

enum WellnessScreenPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeft, top, topRight
    case midLeft, center, midRight
    case bottomLeft, bottom, bottomRight

    var id: String { rawValue }

    var gridRow: Int {
        switch self {
        case .topLeft, .top, .topRight: 0
        case .midLeft, .center, .midRight: 1
        case .bottomLeft, .bottom, .bottomRight: 2
        }
    }

    var gridColumn: Int {
        switch self {
        case .topLeft, .midLeft, .bottomLeft: 0
        case .top, .center, .bottom: 1
        case .topRight, .midRight, .bottomRight: 2
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .top: .top
        case .topRight: .topTrailing
        case .midLeft: .leading
        case .center: .center
        case .midRight: .trailing
        case .bottomLeft: .bottomLeading
        case .bottom: .bottom
        case .bottomRight: .bottomTrailing
        }
    }

    static func at(row: Int, column: Int) -> WellnessScreenPosition {
        switch (row, column) {
        case (0, 0): .topLeft
        case (0, 1): .top
        case (0, 2): .topRight
        case (1, 0): .midLeft
        case (1, 2): .midRight
        case (2, 0): .bottomLeft
        case (2, 1): .bottom
        case (2, 2): .bottomRight
        default: .center
        }
    }

    /// Origin for a panel inside `visibleFrame`.
    func origin(in visible: NSRect, size: NSSize, margin: CGFloat = 28) -> NSPoint {
        let x: CGFloat = {
            switch gridColumn {
            case 0: return visible.minX + margin
            case 2: return visible.maxX - size.width - margin
            default: return visible.midX - size.width / 2
            }
        }()
        let y: CGFloat = {
            switch gridRow {
            case 0: return visible.maxY - size.height - margin // top in AppKit
            case 2: return visible.minY + margin
            default: return visible.midY - size.height / 2
            }
        }()
        return NSPoint(x: x, y: y)
    }

    /// Keep full-screen (dim) badge off menu bar / dock / edges.
    var overlayInsets: EdgeInsets {
        let m: CGFloat = 36
        return EdgeInsets(
            top: gridRow == 0 ? m : 0,
            leading: gridColumn == 0 ? m : 0,
            bottom: gridRow == 2 ? m : 0,
            trailing: gridColumn == 2 ? m : 0
        )
    }
}

enum FocusMatch: String, Codable, CaseIterable, Identifiable, Sendable {
    case open
    case foreground
    case foregroundFullscreen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "Open"
        case .foreground: "Foreground"
        case .foregroundFullscreen: "Foreground + fullscreen"
        }
    }
}

enum BreakPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced
    case deepFocus
    case eyeCare
    case wellness
    var id: String { rawValue }
    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .deepFocus: "Deep Focus"
        case .eyeCare: "Eye Care"
        case .wellness: "Wellness"
        }
    }
    var detail: String {
        switch self {
        case .balanced: "20m work · 20s rest"
        case .deepFocus: "45m work · 30s rest + long"
        case .eyeCare: "15m work · 15s rest"
        case .wellness: "25m work · 45s rest"
        }
    }

    func apply(to settings: inout AppSettings) {
        settings.preset = self
        switch self {
        case .balanced:
            settings.workMinutes = 20
            settings.shortBreakSeconds = 20
            settings.longBreakEnabled = false
        case .deepFocus:
            settings.workMinutes = 45
            settings.shortBreakSeconds = 30
            settings.longBreakEnabled = true
            settings.longBreakMinutes = 8
            settings.shortsBeforeLong = 2
        case .eyeCare:
            settings.workMinutes = 15
            settings.shortBreakSeconds = 15
            settings.longBreakEnabled = false
        case .wellness:
            settings.workMinutes = 25
            settings.shortBreakSeconds = 45
            settings.longBreakEnabled = true
            settings.longBreakMinutes = 5
            settings.shortsBeforeLong = 3
        }
    }
}

struct PlannedBreak: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String = "Lunch"
    var startMinutes: Int = 13 * 60
    var durationSeconds: Double = 30 * 60
    var days: [Int] = [2, 3, 4, 5, 6]
    var symbol: String = "fork.knife"
    var enabled: Bool = true

    var durationLabel: String {
        let m = Int(durationSeconds / 60)
        if m >= 60 {
            let h = m / 60
            let rem = m % 60
            return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
        }
        return "\(max(m, 1)) min"
    }
}

enum AutomationTrigger: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakStart
    case breakEnd
    var id: String { rawValue }
    var title: String {
        switch self {
        case .breakStart: "Start of break"
        case .breakEnd: "End of break"
        }
    }
}

enum AutomationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case shortcut
    case appleScript
    case shell
    var id: String { rawValue }
    var title: String {
        switch self {
        case .shortcut: "Shortcut"
        case .appleScript: "AppleScript"
        case .shell: "Shell"
        }
    }
}

struct BreakAutomation: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var trigger: AutomationTrigger = .breakStart
    var kind: AutomationKind = .shortcut
    var title: String = "New automation"
    var payload: String = ""
    var enabled: Bool = true
}

struct FocusApp: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var bundleID: String
    var name: String
    var match: FocusMatch
}

struct KeyChord: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt
    var display: String

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    static func defaultChord(keyCode: UInt16, name: String) -> KeyChord {
        let flags = NSEvent.ModifierFlags.control.union(.option).union(.command)
        return KeyChord(keyCode: keyCode, modifiers: flags.rawValue, display: "⌃⌥⌘\(name)")
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var hasCompletedOnboarding: Bool = false
    /// When false, schedule is Off until user starts it (menu / settings).
    var scheduleEnabled: Bool = true
    var preset: BreakPreset = .balanced

    var workMinutes: Double = 20
    var shortBreakSeconds: Double = 20
    var longBreakEnabled: Bool = false
    var longBreakMinutes: Double = 5
    var shortsBeforeLong: Int = 3

    var reminderLeadSeconds: Double = 60
    var cursorCountdownSeconds: Double = 5

    var skipMode: SkipMode = .balanced
    var skipUnlockSeconds: Double = 6

    var idlePauseSeconds: Double = 60
    /// After this long away, idle counts as the break and work timer resets on return.
    var idleResetSeconds: Double = 300
    var countIdleAsBreak: Bool = true

    var launchAtLogin: Bool = true

    var officeHoursEnabled: Bool = false
    var officeStartMinutes: Int = 9 * 60
    var officeEndMinutes: Int = 18 * 60
    var officeDays: [Int] = [2, 3, 4, 5, 6]

    var pauseOnMeeting: Bool = true
    var pauseOnRecording: Bool = true
    var pauseOnVideo: Bool = true
    var videoFrontmostOnly: Bool = true
    var pauseOnGames: Bool = true
    var pauseOnFocusApps: Bool = true
    var pauseOnCalendar: Bool = false
    var focusApps: [FocusApp] = []
    var pauseCooldownSeconds: Double = 60
    var postponeOnTyping: Bool = true
    var postponeOnDragging: Bool = true
    var postponeOnDictation: Bool = true
    var meetingDetectMode: MeetingDetectMode = .meetingApps
    var meetingAllowBundleIDs: [String] = []
    var meetingDenyBundleIDs: [String] = [
        "com.apple.siri",
        "com.apple.VoiceMemos"
    ]
    var dictationBundleIDs: [String] = [
        "com.apple.VoiceMemos",
        "com.apple.Shortcuts",
        "com.apple.dictation"
    ]
    var recordingDenyBundleIDs: [String] = []
    var videoDenyBundleIDs: [String] = []
    var alertOnMeeting: Bool = true
    var alertOnVideo: Bool = false
    var alertOnRecording: Bool = false
    var alertOnCalendar: Bool = true
    var alertOnFocus: Bool = false
    var alertOnGame: Bool = false
    var showHeadsUpAfterIdle: Bool = true
    var idleAutoPause: Bool = true

    var blinkEnabled: Bool = false
    var blinkIntervalSeconds: Double = 10 * 60
    var postureEnabled: Bool = true
    var postureIntervalMinutes: Double = 10
    var wellnessDurationSeconds: Double = 4
    var wellnessDim: Bool = true
    var wellnessPlacement: WellnessPlacement = .activeScreen
    var wellnessSize: WellnessSize = .large
    var wellnessScreenPosition: WellnessScreenPosition = .center
    var wellnessDisplayID: UInt32 = 0
    var hideFromRecordings: Bool = true
    var resetWellnessAfterBreak: Bool = true
    var wellnessDuringSmartPause: Bool = false

    var backgroundStyle: BackgroundStyle = .desktop
    var wallpaperBookmark: Data?
    var overlayMessages: [String] = []
    var breakInstruction: String = ""
    var keepUntilEndBreak: Bool = false
    var endEarlyAfterPercent: Double = 50
    var lockMacOnBreakStart: Bool = false
    var overtimeNudgeEnabled: Bool = true
    var headsUpStaySeconds: Double = 0
    var plannedBreaks: [PlannedBreak] = []
    var automations: [BreakAutomation] = []
    var respectReduceMotion: Bool = true

    var soundEnabled: Bool = true
    var soundPair: SoundPair = .lookoffDefault
    var playBreakStart: Bool = true
    var playBreakEnd: Bool = true
    var breakSoundVolume: Double = 0.7
    var postureSoundEnabled: Bool = true
    var blinkSoundEnabled: Bool = true
    var wellnessSoundVolume: Double = 0.7
    var headsUpSoundEnabled: Bool = true
    var smartPauseSoundEnabled: Bool = true
    var idleReturnSoundEnabled: Bool = false
    var overtimeSoundEnabled: Bool = true
    var alertSoundVolume: Double = 0.7
    var startSoundName: String = "chime-in"
    var endSoundName: String = "chime-out"
    var customStartBookmark: Data?
    var customEndBookmark: Data?

    var shortcutStartBreak: KeyChord? = KeyChord.defaultChord(keyCode: 11, name: "B")
    var shortcutSnooze: KeyChord? = KeyChord.defaultChord(keyCode: 1, name: "S")
    var shortcutPause: KeyChord? = KeyChord.defaultChord(keyCode: 35, name: "P")

    var workDuration: TimeInterval { workMinutes * 60 }
    var shortBreakDuration: TimeInterval { shortBreakSeconds }
    var longBreakDuration: TimeInterval { longBreakMinutes * 60 }

    static let defaultInstruction = "Find a distant spot to rest your eyes on while you wait"

    static let defaultInstructions = [
        "Find a distant spot to rest your eyes on while you wait",
        "Look out a window — something far, not the glass",
        "Blink slowly. Soften your gaze for a few seconds",
        "Roll your shoulders. Unclench your jaw",
        "Stand if you can. Let your eyes travel the room",
        "Pick a far corner. Hold soft focus until the timer ends"
    ]

    static let defaultMessages = [
        "Eyes to the horizon",
        "Time for a quick reset",
        "Look twenty feet out",
        "Soften the stare. Blink",
        "Unfocus. Let the room blur",
        "Far focus for a moment",
        "Give your eyes a break",
        "Blink. Breathe. Begin again",
        "Look past the screen",
        "Stretch the stare away",
        "Rest the focus muscle",
        "Horizon over headlines",
        "Ease the near-work grind",
        "A short look far away",
        "Unstick your gaze"
    ]

    func isOfficeHours(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard officeHoursEnabled else { return true }
        let weekday = calendar.component(.weekday, from: date)
        guard officeDays.contains(weekday) else { return false }
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if officeStartMinutes <= officeEndMinutes {
            return minutes >= officeStartMinutes && minutes < officeEndMinutes
        }
        return minutes >= officeStartMinutes || minutes < officeEndMinutes
    }
}

struct EngineSnapshot: Equatable, Sendable {
    var phase: BreakPhase
    var remaining: TimeInterval
    var total: TimeInterval
    var isLongBreak: Bool
    var skipAllowed: Bool
    /// 0...1 while Balanced unlock counts up; 1 when skip ready.
    var skipUnlockProgress: Double
    var endEarlyAllowed: Bool
    var pauseReason: PauseReason?
    var menuTitle: String
    var completedShorts: Int
    var message: String
    var instruction: String
    var event: EngineEvent
    var idleSpoofWarning: Bool
    var scheduleEnabled: Bool

    static let idle = EngineSnapshot(
        phase: .stopped,
        remaining: 0,
        total: 0,
        isLongBreak: false,
        skipAllowed: false,
        skipUnlockProgress: 1,
        endEarlyAllowed: false,
        pauseReason: nil,
        menuTitle: "Off",
        completedShorts: 0,
        message: "",
        instruction: "",
        event: .none,
        idleSpoofWarning: false,
        scheduleEnabled: false
    )
}

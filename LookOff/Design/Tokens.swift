import AppKit
import SwiftUI

enum Palette {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let glassStroke = Color.primary.opacity(0.14)
    static let caption = Color.secondary
    static let magenta = Color(red: 0.89, green: 0.29, blue: 0.82)
    static let purple = Color(red: 0.48, green: 0.28, blue: 0.92)
    static let gold = Color(red: 0.96, green: 0.78, blue: 0.38)
    static let accent = Color.accentColor
    static let work = Color(nsColor: .systemPurple)
    static let pause = Color(nsColor: .systemOrange)
    static let breakNow = Color(nsColor: .systemPink)
}

enum Motion {
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)
    static let overlayFade: Double = 0.35

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    static func appear(_ reduce: Bool) -> Animation {
        reduce || reduceMotion ? .easeInOut(duration: 0.22) : spring
    }
}

enum Layout {
    static let cardRadius: CGFloat = 24
    static let pillRadius: CGFloat = 20
    static let wellnessSize: CGFloat = 120
}

enum TimeFormat {
    static func menu(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    static func overlay(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(interval)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Hours/minutes for daily totals.
    static func compact(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours)h" : "\(hours)h \(rem)m"
    }

    /// Current focus stretch, LookAway-style.
    static func focusSession(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 { return "Less than a minute" }
        return compact(interval)
    }
}

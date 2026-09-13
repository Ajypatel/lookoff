import AppKit
import Foundation
import Observation

struct DayStats: Codable, Equatable, Sendable {
    var day: String
    var screenSeconds: Double = 0
    var breaksTaken: Int = 0
    var breaksSkipped: Int = 0
    var sessions: [Double] = []
    var appSeconds: [String: Double] = [:]

    var longestSession: Double { sessions.max() ?? 0 }

    var medianSession: Double {
        let sorted = sessions.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// Session discipline 60 + break adherence 40.
    func screenScore(workMinutes: Double) -> Int {
        let target = max(workMinutes * 60, 60)
        let longest = longestSession
        let sessionPart: Double = {
            if longest <= 0 { return 60 }
            let ratio = longest / (target * 1.25)
            return max(0, min(60, 60 * (2 - ratio)))
        }()
        let totalBreaks = breaksTaken + breaksSkipped
        let adhere: Double = {
            guard totalBreaks > 0 else { return 40 }
            return 40 * (Double(breaksTaken) / Double(totalBreaks))
        }()
        return Int((sessionPart + adhere).rounded())
    }
}

@MainActor
@Observable
final class StatsStore {
    private let key = "lookoff.stats.v1"
    private(set) var days: [String: DayStats] = [:]
    private var lastSample: Date?
    private var lastPersist: Date?
    private var sessionAccum: Double = 0
    private var inWorkSession = false

    init() {
        load()
    }

    var currentFocusSeconds: TimeInterval { inWorkSession ? sessionAccum : 0 }

    func today() -> DayStats {
        let key = Self.dayKey()
        return days[key] ?? DayStats(day: key)
    }

    func ingest(snapshot: EngineSnapshot, previous: EngineSnapshot, workMinutes: Double) {
        _ = workMinutes
        let now = Date()
        let key = Self.dayKey(now)
        var day = days[key] ?? DayStats(day: key)

        let working: Set<BreakPhase> = [.working, .headsUp, .cursorWarn, .snoozed]
        if working.contains(snapshot.phase) {
            if let lastSample {
                let delta = min(2.5, now.timeIntervalSince(lastSample))
                if delta > 0 {
                    day.screenSeconds += delta
                    sessionAccum += delta
                    if let app = NSWorkspace.shared.frontmostApplication?.localizedName {
                        day.appSeconds[app, default: 0] += delta
                    }
                }
            }
            inWorkSession = true
        } else if inWorkSession, snapshot.phase == .onBreak || snapshot.phase == .stopped {
            if sessionAccum > 20 {
                day.sessions.append(sessionAccum)
            }
            sessionAccum = 0
            inWorkSession = false
        }

        switch snapshot.event {
        case .breakEnded, .idleCountedAsBreak:
            day.breaksTaken += 1
        case .breakSkipped:
            day.breaksSkipped += 1
        default:
            break
        }

        days[key] = day
        lastSample = now
        let eventful = snapshot.event != .none
        if eventful || lastPersist == nil || now.timeIntervalSince(lastPersist ?? .distantPast) >= 15 {
            persist()
            lastPersist = now
        }
    }

    func flush() {
        persist()
        lastPersist = Date()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: DayStats].self, from: data) else { return }
        days = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func dayKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

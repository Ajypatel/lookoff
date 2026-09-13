import Foundation

@MainActor
final class PlannedBreakScheduler {
    private var skipped: [UUID: String] = [:]
    private var completed: [UUID: String] = [:]
    private var idleCredit: [UUID: TimeInterval] = [:]
    private(set) var suppressRegular = false

    var onStart: ((PlannedBreak, TimeInterval) -> Void)?

    func skipToday(_ id: UUID) {
        skipped[id] = Self.dayKey()
    }

    func markCompleted(_ id: UUID) {
        completed[id] = Self.dayKey()
    }

    func evaluate(
        breaks: [PlannedBreak],
        isBusy: Bool,
        isIdle: Bool,
        idleSeconds: TimeInterval,
        onBreak: Bool,
        scheduleRunning: Bool
    ) {
        guard scheduleRunning else {
            suppressRegular = false
            return
        }
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let key = Self.dayKey(now)
        var near = false

        for item in breaks where item.enabled && item.days.contains(weekday) {
            if skipped[item.id] == key || completed[item.id] == key { continue }
            let start = item.startMinutes
            let durationMin = Int(item.durationSeconds / 60)
            let end = start + max(durationMin, 1)
            if abs(minutes - start) <= 10 || (minutes >= start && minutes < end) {
                near = true
            }
            guard minutes >= start else { continue }

            let remainingMinutes = end - minutes
            if remainingMinutes < 1 {
                skipped[item.id] = key
                continue
            }

            if isIdle {
                idleCredit[item.id, default: 0] += 15
                if idleCredit[item.id, default: 0] >= item.durationSeconds {
                    completed[item.id] = key
                    idleCredit[item.id] = 0
                }
                continue
            }

            if isBusy || onBreak { continue }

            let remaining = TimeInterval(remainingMinutes * 60)
            completed[item.id] = key
            idleCredit[item.id] = 0
            onStart?(item, remaining)
        }
        suppressRegular = near
    }

    private static func dayKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

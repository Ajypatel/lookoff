import AppKit
import Observation
import SwiftUI

enum MenuBarPane: String, CaseIterable, Identifiable {
    case now, stats
    var id: String { rawValue }
    var title: String {
        switch self {
        case .now: "Now"
        case .stats: "Stats"
        }
    }
}

@MainActor
@Observable
final class MenuBarPopoverModel {
    var snapshot = EngineSnapshot.idle
    var shortBreakSeconds: TimeInterval = 20
    var longBreakSeconds: TimeInterval = 300
    var today = DayStats(day: "")
    var workMinutes: Double = 20
    var currentFocusSeconds: TimeInterval = 0
    var pane: MenuBarPane = .now

    var score: Int { today.screenScore(workMinutes: workMinutes) }

    var isRunning: Bool {
        snapshot.scheduleEnabled && snapshot.phase != .stopped
    }

    var isOnBreak: Bool { snapshot.phase == .onBreak }

    var icon: StatusIcon { StatusIcon.forSnapshot(snapshot) }

    var headline: String {
        if !isRunning { return "Schedule is off" }
        if let reason = snapshot.pauseReason, !isOnBreak {
            return reason.statusBarTitle
        }
        switch snapshot.phase {
        case .onBreak:
            return snapshot.isLongBreak ? "Long break ends in" : "Break ends in"
        case .headsUp, .cursorWarn:
            return "Break starting in"
        case .snoozed:
            return "Snoozed — break in"
        default:
            return "Break starts in"
        }
    }

    var timerText: String {
        if !isRunning { return "—" }
        return TimeFormat.overlay(snapshot.remaining)
    }

    var upcomingBreakLabel: String {
        let kind = snapshot.isLongBreak ? "Long" : "Short"
        let secs = Int((snapshot.isLongBreak ? longBreakSeconds : shortBreakSeconds).rounded())
        if secs >= 60 {
            let m = secs / 60
            return "\(kind) · \(m == 1 ? "1 min" : "\(m) min")"
        }
        return "\(kind) · \(max(secs, 1)) secs"
    }

    var canSnooze: Bool {
        isRunning && !isOnBreak
    }

    var pauseTitle: String {
        switch snapshot.phase {
        case .manuallyPaused, .idlePaused, .smartPaused: return "Resume"
        default: return "Pause"
        }
    }

    var pauseSymbol: String {
        switch snapshot.phase {
        case .manuallyPaused, .idlePaused, .smartPaused: return "play.fill"
        default: return "pause.fill"
        }
    }

    var topApps: [(name: String, seconds: Double)] {
        today.appSeconds.sorted { $0.value > $1.value }.prefix(4).map { (name: $0.key, seconds: $0.value) }
    }
}

private struct MenuBarPanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MenuBarPopoverView: View {
    @Bindable var model: MenuBarPopoverModel
    var onStartBreak: () -> Void
    var onSnooze: (Int) -> Void
    var onTogglePause: () -> Void
    var onToggleSchedule: () -> Void
    var onEndBreak: () -> Void
    var onSkip: () -> Void
    var onSettings: () -> Void
    var onStats: () -> Void
    var onQuit: () -> Void
    var onSizeChange: (CGSize) -> Void

    var body: some View {
        VStack(spacing: 12) {
            tabBar
            switch model.pane {
            case .now: nowBody
            case .stats: statsBody
            }
        }
        .padding(16)
        .frame(width: 368)
        .lookOffGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), clear: true)
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
        .padding(14)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: MenuBarPanelSizeKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(MenuBarPanelSizeKey.self) { size in
            guard size.width > 1, size.height > 1 else { return }
            onSizeChange(size)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            LookOffGlassContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(MenuBarPane.allCases) { pane in
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) { model.pane = pane }
                        } label: {
                            Text(pane.title)
                        }
                        .buttonStyle(
                            LookOffGlassButtonStyle(
                                prominent: model.pane == pane,
                                compact: true
                            )
                        )
                    }
                }
            }

            Spacer(minLength: 8)

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(LookOffGlassButtonStyle(compact: true, circle: true))
            .help("Settings")
        }
    }

    private var nowBody: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                StatusHeroTile(icon: model.icon, size: 52)
                VStack(spacing: 2) {
                    Text(model.headline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(model.timerText)
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.25), value: model.timerText)
                }
            }

            actionRow

            VStack(spacing: 8) {
                infoRow(
                    symbol: "bolt.fill",
                    tint: Palette.gold,
                    title: "Current focus time",
                    value: TimeFormat.focusSession(model.currentFocusSeconds)
                )
                infoRow(
                    symbol: "hourglass",
                    tint: Palette.work,
                    title: "Upcoming break",
                    value: model.isRunning ? model.upcomingBreakLabel : "—"
                )
            }

            if model.snapshot.idleSpoofWarning {
                warningRow
            }

            footer
        }
    }

    private var statsBody: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("\(min(max(model.score, 0), 100))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Screen Score")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 108, height: 84)
                .lookOffGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    statLine("Screen", TimeFormat.compact(model.today.screenSeconds))
                    statLine("Breaks", "\(model.today.breaksTaken)")
                    statLine("Skipped", "\(model.today.breaksSkipped)")
                }
                Spacer(minLength: 0)
            }

            infoRow(
                symbol: "clock.fill",
                tint: Palette.purple,
                title: "Longest session",
                value: TimeFormat.compact(model.today.longestSession)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Apps")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                if model.topApps.isEmpty {
                    Text("No samples yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                } else {
                    ForEach(model.topApps, id: \.name) { app in
                        HStack {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(TimeFormat.compact(app.seconds))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(12)
            .lookOffGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: onStats) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Open Stats")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LookOffGlassButtonStyle(compact: true))

            footer
        }
    }

    private var actionRow: some View {
        LookOffGlassContainer(spacing: 8) {
            HStack(spacing: 8) {
                if model.isOnBreak {
                    let canEnd = model.snapshot.endEarlyAllowed || model.snapshot.remaining <= 0
                    Button(action: onEndBreak) {
                        label("End", symbol: "checkmark")
                    }
                    .buttonStyle(LookOffGlassButtonStyle(prominent: true, compact: true))
                    .disabled(!canEnd)
                    .opacity(canEnd ? 1 : 0.4)

                    if model.snapshot.skipAllowed {
                        Button(action: onSkip) {
                            label("Skip", symbol: "forward.fill")
                        }
                        .buttonStyle(LookOffGlassButtonStyle(compact: true))
                    }
                } else {
                    Button(action: onStartBreak) {
                        label(model.isRunning ? "Start break" : "On", symbol: "play.fill")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(LookOffGlassButtonStyle(prominent: true, compact: true))

                    snoozeChip("+1m") { onSnooze(1) }
                    snoozeChip("+5m") { onSnooze(5) }
                    snoozeChip("+15m") { onSnooze(15) }
                }
            }
        }
    }

    private func infoRow(symbol: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .lookOffGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), clear: true)
    }

    private func statLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var warningRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Idle may be blocked by Amphetamine/Caffeine")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange.opacity(0.95))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            footerButton(
                model.isRunning ? "Stop" : "Start",
                symbol: model.isRunning ? "stop.fill" : "play.fill",
                action: onToggleSchedule
            )
            if model.isRunning, !model.isOnBreak {
                footerButton(model.pauseTitle, symbol: model.pauseSymbol, action: onTogglePause)
            }
            Spacer()
            footerButton("Quit", symbol: "power", action: onQuit)
        }
        .padding(.top, 2)
    }

    private func label(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(title)
        }
    }

    private func snoozeChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .buttonStyle(LookOffGlassButtonStyle(compact: true))
        .disabled(!model.canSnooze)
        .opacity(model.canSnooze ? 1 : 0.35)
    }

    private func footerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

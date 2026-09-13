import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general, breaks, smartPause, wellness, stats, sounds, shortcuts, automations, permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .breaks: "Screen Breaks"
        case .smartPause: "Smart Pause"
        case .wellness: "Wellness Reminders"
        case .stats: "Stats"
        case .sounds: "Sounds"
        case .shortcuts: "Keyboard Shortcuts"
        case .automations: "Automations"
        case .permissions: "Permissions"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Schedule, presets, and launch"
        case .breaks: "Timing, warnings, and overlay"
        case .smartPause: "Meetings, video, idle, and more"
        case .wellness: "Posture and blink nudges"
        case .stats: "Screen time, sessions, and score"
        case .sounds: "Break audio cues"
        case .shortcuts: "Global hotkeys"
        case .automations: "Scripts at break start and end"
        case .permissions: "What LookOff can access"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gear"
        case .breaks: "eye.fill"
        case .smartPause: "pause.circle.fill"
        case .wellness: "figure.stand"
        case .stats: "chart.bar.fill"
        case .sounds: "speaker.wave.2.fill"
        case .shortcuts: "keyboard.fill"
        case .automations: "bolt.fill"
        case .permissions: "checkmark.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(nsColor: .systemGray)
        case .breaks: Color(nsColor: .systemPink)
        case .smartPause: Color(nsColor: .systemOrange)
        case .wellness: Color(nsColor: .systemPink)
        case .stats: Color(nsColor: .systemBlue)
        case .sounds: Color(nsColor: .systemOrange)
        case .shortcuts: Color(nsColor: .systemIndigo)
        case .automations: Color(nsColor: .systemYellow)
        case .permissions: Color(nsColor: .systemGreen)
        }
    }

    static var focusGroup: [SettingsTab] { [.general, .breaks, .smartPause, .wellness, .stats] }
    static var behaviorGroup: [SettingsTab] { [.sounds, .shortcuts, .automations] }
    static var aboutGroup: [SettingsTab] { [.permissions] }
}

enum SettingsChrome {
    static let accent = Color.accentColor
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let sidebar = Color.clear
    static let cardRadius: CGFloat = 10
    static let skipGradient = LinearGradient(
        colors: [
            Color(nsColor: .systemPink),
            Color(nsColor: .systemOrange)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct SettingsPage<Content: View>: View {
    let tab: SettingsTab
    var showsHeader: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if showsHeader {
                    HStack(spacing: 10) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(tab.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tab.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text(tab.subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                content()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// LookAway grouped inset card. Title sits above the card.
struct SettingsCard<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsChrome.cardRadius, style: .continuous)
                    .fill(SettingsChrome.card)
            )

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsChrome.accent)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 38)
    }
}

struct SettingsHairline: View {
    var body: some View {
        Divider()
            .opacity(0.35)
            .padding(.leading, 14)
    }
}

struct SettingsValueText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
    }
}

struct PresetChip: View {
    let preset: BreakPreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(preset.detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SettingsChrome.accent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.08 : 0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(selected ? 0.12 : 0.06), lineWidth: 1)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

struct SkipModeCard: View {
    let mode: SkipMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                VStack(spacing: 6) {
                    Image(systemName: mode.glyph)
                        .font(.system(size: 13, weight: .bold))
                    Text("Skip Break")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(SettingsChrome.skipGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                }

                VStack(spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(mode.lookAwayDetail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct SettingsSidebarButton: View {
    let tab: SettingsTab
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(tab.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsSidebarSection: View {
    let title: String
    let tabs: [SettingsTab]
    @Binding var selection: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(tabs) { item in
                SettingsSidebarButton(tab: item, selected: selection == item) {
                    selection = item
                }
            }
        }
    }
}

struct WellnessPositionGrid: View {
    @Binding var position: WellnessScreenPosition

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { col in
                        let value = WellnessScreenPosition.at(row: row, column: col)
                        Button {
                            position = value
                        } label: {
                            Circle()
                                .fill(position == value ? SettingsChrome.accent : Color.primary.opacity(0.2))
                                .frame(width: 8, height: 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(value.rawValue)
                        .accessibilityAddTraits(position == value ? .isSelected : [])
                    }
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            SettingsChrome.accent.opacity(0.22),
                            Color.primary.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SettingsChrome.accent.opacity(0.22), lineWidth: 1)
        }
        .frame(width: 68, height: 68)
    }
}

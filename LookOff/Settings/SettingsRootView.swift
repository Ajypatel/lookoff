import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsRootView: View {
    @Environment(AppController.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(selection: $app.settingsTab) {
                Section("Focus & Wellbeing") {
                    ForEach(SettingsTab.focusGroup) { item in
                        sidebarRow(item)
                    }
                }
                Section("Behavior & Feedback") {
                    ForEach(SettingsTab.behaviorGroup) { item in
                        sidebarRow(item)
                    }
                }
                Section("LookOff") {
                    ForEach(SettingsTab.aboutGroup) { item in
                        sidebarRow(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 196, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isScheduleRunning ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(isScheduleRunning ? "Schedule is on" : "Schedule is off")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } detail: {
            Group {
                switch app.settingsTab {
                case .general: GeneralPane()
                case .breaks: BreaksPane()
                case .smartPause: SmartPausePane()
                case .wellness: WellnessPane()
                case .stats: StatsPane()
                case .sounds: SoundsPane()
                case .shortcuts: ShortcutsPane()
                case .automations: AutomationsPane()
                case .permissions: PermissionsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(app.settingsTab)
        }
        .frame(minWidth: 840, minHeight: 560)
        .environment(app)
        .onChange(of: app.settingsStore.settings) { _, _ in
            app.settingsDidChange()
        }
    }

    private func sidebarRow(_ item: SettingsTab) -> some View {
        Label {
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
        } icon: {
            Image(systemName: item.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .background(item.tint.gradient, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
        }
        .tag(item)
    }

    private var isScheduleRunning: Bool {
        app.snapshot.scheduleEnabled && app.snapshot.phase != .stopped
    }
}
// MARK: - General

struct GeneralPane: View {
    @Environment(AppController.self) private var app

    private let weekdays: [(Int, String)] = [
        (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")
    ]

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsPage(tab: .general) {
            SettingsCard(title: "Preset") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(BreakPreset.allCases) { preset in
                        PresetChip(preset: preset, selected: store.settings.preset == preset) {
                            store.settings.preset = preset
                            store.applyPreset(preset)
                        }
                    }
                }
                .padding(12)
            }

            SettingsCard(title: "Schedule") {
                SettingsRow(title: "LookOff schedule", subtitle: "When off, breaks never start") {
                    Toggle("", isOn: $store.settings.scheduleEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: store.settings.scheduleEnabled) { _, on in
                            if on { app.startSchedule() } else { app.stopSchedule() }
                        }
                }
                SettingsHairline()
                SettingsRow(title: "Launch at login") {
                    Toggle("", isOn: $store.settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Office hours", subtitle: "Only run during these hours") {
                    Toggle("", isOn: $store.settings.officeHoursEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if store.settings.officeHoursEnabled {
                    SettingsHairline()
                    SettingsRow(title: "Start") {
                        DatePicker("", selection: officeBinding(\.officeStartMinutes), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    SettingsRow(title: "End") {
                        DatePicker("", selection: officeBinding(\.officeEndMinutes), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Text("Past-midnight ranges wrap (22:00–02:00).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                    HStack(spacing: 6) {
                        ForEach(weekdays, id: \.0) { day, label in
                            let on = store.settings.officeDays.contains(day)
                            Button(label) {
                                var days = store.settings.officeDays
                                if on {
                                    days.removeAll { $0 == day }
                                } else {
                                    days.append(day)
                                }
                                store.settings.officeDays = days
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 36, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(on ? SettingsChrome.accent.opacity(0.9) : Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(on ? .white : .secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }

            SettingsCard(title: "Motion") {
                SettingsRow(title: "Respect Reduce Motion", subtitle: "Softer animations when enabled in System Settings") {
                    Toggle("", isOn: $store.settings.respectReduceMotion)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            if app.snapshot.idleSpoofWarning {
                SettingsCard {
                    Text("Amphetamine/Caffeine may keep idle at 0. Idle tracking lives under Smart Pause.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(14)
                }
            }
        }
    }

    private func officeBinding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding {
            minutesToDate(app.settingsStore.settings[keyPath: keyPath])
        } set: { date in
            app.settingsStore.settings[keyPath: keyPath] = dateToMinutes(date)
        }
    }
}

// MARK: - Breaks

struct BreaksPane: View {
    @Environment(AppController.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsPage(tab: .breaks) {
            SettingsCard(title: "General") {
                SettingsRow(title: "Show a break after") {
                    Stepper(
                        "\(Int(store.settings.workMinutes)) min of focus",
                        value: $store.settings.workMinutes,
                        in: 1...120
                    )
                }
                SettingsHairline()
                SettingsRow(title: "Break duration") {
                    Stepper(
                        "\(Int(store.settings.shortBreakSeconds)) s",
                        value: $store.settings.shortBreakSeconds,
                        in: 5...300,
                        step: 5
                    )
                }
                SettingsHairline()
                SettingsRow(title: "Long breaks") {
                    Toggle("", isOn: $store.settings.longBreakEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if store.settings.longBreakEnabled {
                    SettingsHairline()
                    SettingsRow(title: "Long break length") {
                        Stepper("\(Int(store.settings.longBreakMinutes)) min", value: $store.settings.longBreakMinutes, in: 1...30)
                    }
                    SettingsHairline()
                    SettingsRow(title: "Every") {
                        Stepper("\(store.settings.shortsBeforeLong) short breaks", value: $store.settings.shortsBeforeLong, in: 1...12)
                    }
                }
                SettingsHairline()
                SettingsRow(title: "Heads-up lead") {
                    Stepper("\(Int(store.settings.reminderLeadSeconds)) s", value: $store.settings.reminderLeadSeconds, in: 10...180, step: 5)
                }
                SettingsHairline()
                SettingsRow(title: "Cursor countdown") {
                    Stepper("\(Int(store.settings.cursorCountdownSeconds)) s", value: $store.settings.cursorCountdownSeconds, in: 3...15)
                }
            }

            SettingsCard(title: "Break enforcement") {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(SkipMode.allCases) { mode in
                        SkipModeCard(mode: mode, selected: store.settings.skipMode == mode) {
                            store.settings.skipMode = mode
                        }
                    }
                }
                .padding(14)
                if store.settings.skipMode == .balanced {
                    SettingsHairline()
                    SettingsRow(title: "Unlock after") {
                        Stepper(
                            "\(Int(store.settings.skipUnlockSeconds)) s",
                            value: $store.settings.skipUnlockSeconds,
                            in: 4...20
                        )
                    }
                }
            }

            PlannedBreaksSection()

            SettingsCard(title: "More") {
                SettingsRow(title: "Break background") {
                    Picker("", selection: $store.settings.backgroundStyle) {
                        ForEach(BackgroundStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsHairline()
                SettingsRow(title: "Choose wallpaper") {
                    Button("Choose…") { pickWallpaper() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                SettingsHairline()
                SettingsRow(title: "Keep the break screen up until I press End Break") {
                    Toggle("", isOn: $store.settings.keepUntilEndBreak)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Let me End Break early if nearly done") {
                    Toggle("", isOn: endEarlyBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Lock my Mac automatically when a break starts") {
                    Toggle("", isOn: $store.settings.lockMacOnBreakStart)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Overtime nudge if a break is held back") {
                    Toggle("", isOn: $store.settings.overtimeNudgeEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Keep heads-up visible for", subtitle: "0 = until the cursor countdown") {
                    Stepper(
                        store.settings.headsUpStaySeconds <= 0
                            ? "Until countdown"
                            : "\(Int(store.settings.headsUpStaySeconds)) s",
                        value: $store.settings.headsUpStaySeconds,
                        in: 0...120,
                        step: 5
                    )
                }
            }

            SettingsCard(title: "Custom message", footnote: "Built-in lines stay in the app. Add your own only if you want extras in the mix.") {
                if store.settings.overlayMessages.isEmpty {
                    SettingsRow(title: "No custom message") {
                        Button("Add") {
                            store.settings.overlayMessages = [""]
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    ForEach(Array(store.settings.overlayMessages.indices), id: \.self) { index in
                        if index > 0 { SettingsHairline() }
                        HStack(spacing: 8) {
                            TextField("Your message", text: messageBinding(index), axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(1...3)
                            Button {
                                store.settings.overlayMessages.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    SettingsHairline()
                    SettingsRow(title: "Add another") {
                        Button("Add") {
                            store.settings.overlayMessages.append("")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var endEarlyBinding: Binding<Bool> {
        Binding {
            app.settingsStore.settings.endEarlyAfterPercent < 100
        } set: { on in
            app.settingsStore.settings.endEarlyAfterPercent = on ? 50 : 100
        }
    }

    private func messageBinding(_ index: Int) -> Binding<String> {
        Binding {
            app.settingsStore.settings.overlayMessages[index]
        } set: { value in
            app.settingsStore.settings.overlayMessages[index] = value
        }
    }

    private func pickWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app.settingsStore.settings.wallpaperBookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        app.settingsStore.settings.backgroundStyle = .wallpaper
    }
}

// MARK: - Wellness

struct WellnessPane: View {
    @Environment(AppController.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsPage(tab: .wellness) {
            HStack(alignment: .top, spacing: 14) {
                WellnessReminderColumn(
                    kind: .posture,
                    title: "Posture Reminder",
                    blurb: "Helps maintain good posture by gently alerting you to sit upright and avoid strain.",
                    enabled: $store.settings.postureEnabled,
                    everyMinutes: $store.settings.postureIntervalMinutes,
                    onPreview: { app.previewWellness(.posture) }
                )
                WellnessReminderColumn(
                    kind: .blink,
                    title: "Blink Reminder",
                    blurb: "Prevents dry eyes by gently nudging you to blink at healthy intervals.",
                    enabled: $store.settings.blinkEnabled,
                    everyMinutes: Binding(
                        get: { max(1, store.settings.blinkIntervalSeconds / 60) },
                        set: { store.settings.blinkIntervalSeconds = $0 * 60 }
                    ),
                    onPreview: { app.previewWellness(.blink) }
                )
            }

            SettingsCard(title: "Common settings") {
                SettingsRow(title: "Size") {
                    Picker("", selection: $store.settings.wellnessSize) {
                        ForEach(WellnessSize.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                SettingsHairline()
                SettingsRow(title: "Position") {
                    WellnessPositionGrid(position: $store.settings.wellnessScreenPosition)
                }
                SettingsHairline()
                SettingsRow(title: "Visible for") {
                    Stepper("\(Int(store.settings.wellnessDurationSeconds)) s", value: $store.settings.wellnessDurationSeconds, in: 2...10)
                }
                SettingsHairline()
                SettingsRow(title: "Dim behind reminder") {
                    Toggle("", isOn: $store.settings.wellnessDim)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Keep active during smart-pause") {
                    Toggle("", isOn: $store.settings.wellnessDuringSmartPause)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Hide from screen recordings") {
                    Toggle("", isOn: $store.settings.hideFromRecordings)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Reset timers after break") {
                    Toggle("", isOn: $store.settings.resetWellnessAfterBreak)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Show on") {
                    Picker("", selection: $store.settings.wellnessPlacement) {
                        ForEach(WellnessPlacement.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                if store.settings.wellnessPlacement == .chosenDisplay {
                    SettingsHairline()
                    SettingsRow(title: "Display") {
                        Picker("", selection: displayIDBinding) {
                            ForEach(displayOptions, id: \.id) { item in
                                Text(item.name).tag(item.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }
            }
        }
    }

    private var displayOptions: [(id: UInt32, name: String)] {
        NSScreen.screens.map { screen in
            (BreakOverlayController.displayID(screen), screen.localizedName)
        }
    }

    private var displayIDBinding: Binding<UInt32> {
        Binding {
            let current = app.settingsStore.settings.wellnessDisplayID
            if displayOptions.contains(where: { $0.id == current }) {
                return current
            }
            return displayOptions.first?.id
                ?? BreakOverlayController.displayID(NSScreen.main ?? NSScreen.screens[0])
        } set: { id in
            app.settingsStore.settings.wellnessDisplayID = id
        }
    }
}

private struct WellnessReminderColumn: View {
    let kind: WellnessEngine.Kind
    let title: String
    let blurb: String
    @Binding var enabled: Bool
    @Binding var everyMinutes: Double
    var onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(blurb)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)

            WellnessSettingsPreviewCard(kind: kind, muted: !enabled, onPreview: onPreview)

            SettingsCard {
                SettingsRow(title: "Enabled") {
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Show Every") {
                    Picker("", selection: $everyMinutes) {
                        Text("5 minutes").tag(5.0)
                        Text("10 minutes").tag(10.0)
                        Text("15 minutes").tag(15.0)
                        Text("20 minutes").tag(20.0)
                        Text("30 minutes").tag(30.0)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!enabled)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct WellnessSettingsPreviewCard: View {
    let kind: WellnessEngine.Kind
    var muted: Bool
    var onPreview: () -> Void
    @State private var wallpaper: NSImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let wallpaper {
                    Image(nsImage: wallpaper)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.42, blue: 0.52),
                            Color(red: 0.12, green: 0.2, blue: 0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            WellnessPreviewLoop(kind: kind)
                .opacity(muted ? 0.45 : 1)
                .padding(.horizontal, 8)
                .padding(.bottom, 34)
                .padding(.top, 6)

            Button(action: onPreview) {
                Text(kind == .posture ? "Preview posture on screen" : "Preview blink on screen")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
        }
        .frame(height: 188)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipped()
        .onAppear {
            wallpaper = DesktopWallpaper.image(for: NSScreen.main ?? NSScreen.screens[0])
        }
    }
}

// MARK: - Sounds

struct SoundsPane: View {
    @Environment(AppController.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsPage(tab: .sounds) {
            SettingsCard(title: "Break sounds") {
                SettingsRow(title: "Play sounds") {
                    Toggle("", isOn: $store.settings.soundEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Sound pair") {
                    Picker("", selection: $store.settings.soundPair) {
                        ForEach(SoundPair.allCases) { pair in
                            Text(pair.title).tag(pair)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsHairline()
                SettingsRow(title: "Play on break start") {
                    HStack(spacing: 8) {
                        Button {
                            app.sounds.previewPair(store.settings, enter: true)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Toggle("", isOn: $store.settings.playBreakStart)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                SettingsHairline()
                SettingsRow(title: "Play on break end") {
                    HStack(spacing: 8) {
                        Button {
                            app.sounds.previewPair(store.settings, enter: false)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Toggle("", isOn: $store.settings.playBreakEnd)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                SettingsHairline()
                SettingsRow(title: "Volume") {
                    Slider(value: $store.settings.breakSoundVolume, in: 0...1)
                        .frame(width: 160)
                }
                if store.settings.soundPair == .custom {
                    SettingsHairline()
                    SettingsRow(title: "Start file") {
                        HStack(spacing: 8) {
                            Button("Choose…") { pick(.start) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            if store.settings.customStartBookmark != nil {
                                Button("Clear") { store.settings.customStartBookmark = nil }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    SettingsHairline()
                    SettingsRow(title: "End file") {
                        HStack(spacing: 8) {
                            Button("Choose…") { pick(.end) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            if store.settings.customEndBookmark != nil {
                                Button("Clear") { store.settings.customEndBookmark = nil }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            SettingsCard(title: "Wellness reminder sounds") {
                SettingsRow(title: "Posture reminder sound") {
                    Toggle("", isOn: $store.settings.postureSoundEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Blink reminder sound") {
                    Toggle("", isOn: $store.settings.blinkSoundEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Volume") {
                    Slider(value: $store.settings.wellnessSoundVolume, in: 0...1)
                        .frame(width: 160)
                }
            }

            SettingsCard(title: "Alerts and nudges") {
                SettingsRow(title: "Break reminder sound") {
                    Toggle("", isOn: $store.settings.headsUpSoundEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Smart pause notification sound") {
                    Toggle("", isOn: $store.settings.smartPauseSoundEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Notification sound when you return from idle") {
                    Toggle("", isOn: $store.settings.idleReturnSoundEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Overtime nudge sound") {
                    Toggle("", isOn: $store.settings.overtimeSoundEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsHairline()
                SettingsRow(title: "Volume") {
                    Slider(value: $store.settings.alertSoundVolume, in: 0...1)
                        .frame(width: 160)
                }
            }
        }
    }

    private enum Slot { case start, end }

    private func pick(_ slot: Slot) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        switch slot {
        case .start: app.settingsStore.settings.customStartBookmark = data
        case .end: app.settingsStore.settings.customEndBookmark = data
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @Environment(AppController.self) private var app

    var body: some View {
        SettingsPage(tab: .shortcuts) {
            SettingsCard(title: "Global hotkeys", footnote: "Optional. Skip Accessibility and hotkeys stay local-only (none).") {
                if !PermissionManager.accessibilityTrusted() {
                    PermissionNeededBanner(text: "Enable Accessibility to capture these shortcuts while other apps are focused. LookOff runs without it.")
                    SettingsHairline()
                }
                ShortcutRecorderRow(title: "Start break", chord: shortcutBinding(\.shortcutStartBreak))
                SettingsHairline()
                ShortcutRecorderRow(title: "Snooze +5m", chord: shortcutBinding(\.shortcutSnooze))
                SettingsHairline()
                ShortcutRecorderRow(title: "Pause / resume", chord: shortcutBinding(\.shortcutPause))
            }
        }
    }

    private func shortcutBinding(_ keyPath: WritableKeyPath<AppSettings, KeyChord?>) -> Binding<KeyChord?> {
        Binding {
            app.settingsStore.settings[keyPath: keyPath]
        } set: { value in
            app.settingsStore.settings[keyPath: keyPath] = value
        }
    }
}

struct ShortcutRecorderRow: View {
    let title: String
    @Binding var chord: KeyChord?
    @State private var recording = false

    var body: some View {
        SettingsRow(title: title, subtitle: recording ? "Press keys now…" : nil) {
            HStack(spacing: 8) {
                ZStack {
                    ShortcutCatcher(isRecording: recording) { captured in
                        chord = captured
                        recording = false
                    }
                    .frame(width: 1, height: 1)
                    Text(recording ? "Listening…" : (chord?.display ?? "None"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(recording ? Palette.gold : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .onTapGesture { recording = true }
                }
                Button("Clear") { chord = nil; recording = false }
                    .buttonStyle(.borderless)
            }
        }
    }
}

struct ShortcutCatcher: NSViewRepresentable {
    var isRecording: Bool
    var onChord: (KeyChord) -> Void

    func makeNSView(context: Context) -> ShortcutCatcherView {
        let view = ShortcutCatcherView()
        view.onChord = onChord
        return view
    }

    func updateNSView(_ nsView: ShortcutCatcherView, context: Context) {
        nsView.onChord = onChord
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class ShortcutCatcherView: NSView {
    var isRecording = false
    var onChord: ((KeyChord) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let display = ShortcutDisplay.string(keyCode: event.keyCode, flags: flags)
        onChord?(KeyChord(keyCode: event.keyCode, modifiers: flags.rawValue, display: display))
    }
}

// MARK: - Permissions

struct PermissionsPane: View {
    @Environment(AppController.self) private var app
    @State private var refresh = 0

    var body: some View {
        SettingsPage(tab: .permissions) {
            SettingsCard(
                title: "Privacy stance",
                footnote: "Every item below is optional. Schedule, breaks, wellness, and Smart Pause (apps + Core Audio) run with none granted. No Screen Recording, Microphone, or Camera prompts."
            ) {
                Text("Grant only what you want. Deny or skip anything — LookOff keeps working.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                ForEach(LookOffPermission.settingsList) { item in
                    PermissionExplainRow(permission: item) {
                        refresh += 1
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            .id(refresh)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refresh += 1
                app.rebindOptionalInput()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lookOffPermissionsChanged)) { _ in
                refresh += 1
                app.rebindOptionalInput()
            }

            SettingsCard(title: "How detection works") {
                VStack(alignment: .leading, spacing: 10) {
                    bullet("Meetings", "Zoom / Teams / FaceTime process list (or mic-in-use mode).")
                    bullet("Recording", "OBS / QuickTime / Loom-style apps — no screen capture.")
                    bullet("Wellness", "Timers only. Break screens stay screenshot-friendly.")
                }
                .padding(14)
            }
        }
    }

    private func bullet(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Palette.purple)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }
}

private func minutesToDate(_ minutes: Int) -> Date {
    Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? .now
}

private func dateToMinutes(_ date: Date) -> Int {
    let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
}

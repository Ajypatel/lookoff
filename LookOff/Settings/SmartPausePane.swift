import AppKit
import EventKit
import SwiftUI

/// LookAway-style Smart Pause settings: hold-off, auto-pause rows + Options, idle.
struct SmartPausePane: View {
    @Environment(AppController.self) private var app
    @State private var path = NavigationPath()

    var body: some View {
        @Bindable var store = app.settingsStore
        NavigationStack(path: $path) {
            SettingsPage(tab: .smartPause) {
                SettingsCard(title: "Focus Filters") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add LookOff under System Settings → Focus → Focus Filters so a Focus mode can pause breaks. Enable “Pause breaks” in the filter.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(PermissionManager.focusState() == .granted ? "Focus Status: On" : "Focus Status optional")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if PermissionManager.focusState() != .granted {
                                Button("Enable") {
                                    app.focusObserver.requestAccess()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(14)
                }

                SettingsCard(title: "Hold off") {
                    Toggle(isOn: holdOffBinding) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("While typing, dragging, or dictating")
                                .font(.system(size: 14, weight: .medium))
                            Text("Prevents a break from starting mid-flow. Typing and drag need Accessibility; idle still works without it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(14)
                }

                if store.settings.postponeOnDictation || store.settings.postponeOnTyping {
                    SettingsCard(title: "Dictation apps", footnote: "Mic use in these apps counts as dictation, not a call.") {
                        ForEach(Array(store.settings.dictationBundleIDs.enumerated()), id: \.element) { index, id in
                            if index > 0 { SettingsHairline() }
                            SettingsRow(title: dictationDisplayName(id)) {
                                Button("Remove") {
                                    store.settings.dictationBundleIDs.removeAll { $0 == id }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        SettingsHairline()
                        SettingsRow(title: "Add an app") {
                            Button {
                                addBundleID(to: \.dictationBundleIDs)
                            } label: {
                                Label("Frontmost app", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                SettingsCard(title: "Automatically pause during") {
                    SmartPauseRow(
                        icon: "headphones",
                        tint: .blue,
                        title: "Meetings or Calls",
                        subtitle: "Zoom, Teams, FaceTime, and more",
                        isOn: $store.settings.pauseOnMeeting,
                        onOptions: { path.append(SmartPauseRoute.meetings) }
                    )
                    Divider().opacity(0.3)
                    SmartPauseRow(
                        icon: "play.rectangle.on.rectangle",
                        tint: .purple,
                        title: "Video playback",
                        subtitle: "YouTube, Netflix, local players…",
                        isOn: $store.settings.pauseOnVideo,
                        onOptions: { path.append(SmartPauseRoute.video) }
                    )
                    Divider().opacity(0.3)
                    SmartPauseRow(
                        icon: "rectangle.dashed.badge.record",
                        tint: .orange,
                        title: "Screen recording or sharing",
                        subtitle: "OBS, QuickTime, Loom…",
                        isOn: $store.settings.pauseOnRecording,
                        onOptions: { path.append(SmartPauseRoute.recording) }
                    )
                    Divider().opacity(0.3)
                    SmartPauseRow(
                        icon: "calendar",
                        tint: .red,
                        title: "Calendar Events",
                        subtitle: "Timed events on your calendars",
                        isOn: $store.settings.pauseOnCalendar,
                        onOptions: { path.append(SmartPauseRoute.calendar) }
                    )
                    Divider().opacity(0.3)
                    SmartPauseRow(
                        icon: "app.badge",
                        tint: .pink,
                        title: "Deep focus apps",
                        subtitle: "Apps you mark as do-not-disturb",
                        isOn: $store.settings.pauseOnFocusApps,
                        onOptions: { path.append(SmartPauseRoute.focus) }
                    )
                    Divider().opacity(0.3)
                    SmartPauseRow(
                        icon: "gamecontroller",
                        tint: .green,
                        title: "Gaming",
                        subtitle: "Fullscreen games",
                        isOn: $store.settings.pauseOnGames,
                        onOptions: { path.append(SmartPauseRoute.gaming) }
                    )
                }

                SettingsCard(title: "Cooldown") {
                    SettingsRow(title: "After smart pause ends", subtitle: "Delay before the next break can start") {
                        Picker("", selection: cooldownBinding) {
                            Text("Off").tag(0.0)
                            Text("30s").tag(30.0)
                            Text("1m").tag(60.0)
                            Text("2m").tag(120.0)
                            Text("5m").tag(300.0)
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                }

                SettingsCard(title: "Idle tracking") {
                    HStack(alignment: .center, spacing: 10) {
                        Toggle("", isOn: $store.settings.idleAutoPause)
                            .labelsHidden()
                            .toggleStyle(.switch)
                        Text("Pause timers after")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(store.settings.idleAutoPause ? .primary : .secondary)
                        Picker("", selection: $store.settings.idlePauseSeconds) {
                            Text("30 seconds").tag(30.0)
                            Text("1 minute").tag(60.0)
                            Text("2 minutes").tag(120.0)
                            Text("3 minutes").tag(180.0)
                            Text("5 minutes").tag(300.0)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .disabled(!store.settings.idleAutoPause)
                        Text("of inactivity")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    SettingsHairline()
                    HStack(alignment: .center, spacing: 10) {
                        Toggle("", isOn: $store.settings.countIdleAsBreak)
                            .labelsHidden()
                            .toggleStyle(.switch)
                        Text("Reset timers after")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(store.settings.countIdleAsBreak ? .primary : .secondary)
                        Picker("", selection: $store.settings.idleResetSeconds) {
                            Text("2 minutes").tag(120.0)
                            Text("3 minutes").tag(180.0)
                            Text("5 minutes").tag(300.0)
                            Text("10 minutes").tag(600.0)
                            Text("15 minutes").tag(900.0)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .disabled(!store.settings.countIdleAsBreak)
                        Text("of inactivity")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    SettingsHairline()
                    SettingsRow(title: "Heads-up after returning") {
                        Toggle("", isOn: $store.settings.showHeadsUpAfterIdle)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    if app.snapshot.idleSpoofWarning {
                        Text("Amphetamine/Caffeine may keep idle at 0.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(for: SmartPauseRoute.self) { route in
                switch route {
                case .meetings: MeetingOptionsPane()
                case .video: VideoOptionsPane()
                case .recording: RecordingOptionsPane()
                case .calendar: CalendarOptionsPane()
                case .focus: FocusOptionsPane()
                case .gaming: GamingOptionsPane()
                }
            }
        }
    }

    private var holdOffBinding: Binding<Bool> {
        Binding {
            app.settingsStore.settings.postponeOnTyping
                || app.settingsStore.settings.postponeOnDragging
                || app.settingsStore.settings.postponeOnDictation
        } set: { on in
            app.settingsStore.settings.postponeOnTyping = on
            app.settingsStore.settings.postponeOnDragging = on
            app.settingsStore.settings.postponeOnDictation = on
        }
    }

    private var cooldownBinding: Binding<Double> {
        Binding {
            app.settingsStore.settings.pauseCooldownSeconds
        } set: { app.settingsStore.settings.pauseCooldownSeconds = $0 }
    }

    private func dictationDisplayName(_ bundleID: String) -> String {
        switch bundleID {
        case "com.apple.dictation": "Dictation"
        case "com.apple.VoiceMemos": "Voice Memos"
        case "com.apple.Shortcuts": "Shortcuts"
        default: appName(for: bundleID) ?? bundleID
        }
    }

    private func addBundleID(to keyPath: WritableKeyPath<AppSettings, [String]>) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier else { return }
        var list = self.app.settingsStore.settings[keyPath: keyPath]
        guard !list.contains(id) else { return }
        list.append(id)
        self.app.settingsStore.settings[keyPath: keyPath] = list
    }

    private func appName(for bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { Bundle(url: $0)?.name }
    }
}

private enum SmartPauseRoute: Hashable {
    case meetings, video, recording, calendar, focus, gaming
}

private struct SmartPauseRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let onOptions: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Options", action: onOptions)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 14)
    }
}

// MARK: - Options panes

struct MeetingOptionsPane: View {
    @Environment(AppController.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        Form {
            Section {
                Picker("Detect meetings using", selection: $store.settings.meetingDetectMode) {
                    ForEach(MeetingDetectMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(store.settings.meetingDetectMode == .microphone
                      ? "Uses system mic-in-use signal (no Microphone permission prompt). Dictation apps are ignored."
                      : "Pauses when known meeting apps are running (Zoom, Teams, FaceTime…).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Only these apps") {
                Text(store.settings.meetingAllowBundleIDs.isEmpty
                     ? "LookOff watches its built-in meeting app list. Add apps here to use a custom allow-list instead."
                     : "Only the apps below can trigger a meeting pause.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                BundleIDListEditor(ids: $store.settings.meetingAllowBundleIDs)
            }
            Section("Excluded apps") {
                Text("These apps never count as a meeting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                BundleIDListEditor(ids: $store.settings.meetingDenyBundleIDs)
            }
            Section {
                Toggle("Show an alert when a meeting is detected", isOn: $store.settings.alertOnMeeting)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configure Meeting Detection")
    }
}

struct VideoOptionsPane: View {
    @Environment(AppController.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        Form {
            Section {
                Picker("Trigger when video is…", selection: $store.settings.videoFrontmostOnly) {
                    Text("Frontmost only").tag(true)
                    Text("Playing anywhere").tag(false)
                }
                Text("Frontmost only clears Video as soon as you leave the player (LookAway-like). Browsers always use frontmost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Excluded apps") {
                Text("Video editors and music apps are good exclusions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                BundleIDListEditor(ids: $store.settings.videoDenyBundleIDs)
            }
            Section {
                Toggle("Show an alert when video playback is detected", isOn: $store.settings.alertOnVideo)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configure Video Playback Detection")
    }
}

struct RecordingOptionsPane: View {
    @Environment(AppController.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        Form {
            Section("Excluded apps") {
                Text("Apps that should not trigger recording pause.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                BundleIDListEditor(ids: $store.settings.recordingDenyBundleIDs)
            }
            Section {
                Toggle("Show an alert when recording is detected", isOn: $store.settings.alertOnRecording)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configure Recording Detection")
    }
}

struct CalendarOptionsPane: View {
    @Environment(AppController.self) private var app
    @State private var statusText = ""

    var body: some View {
        @Bindable var store = app.settingsStore
        Form {
            Section {
                Text("Pauses during timed calendar events (all-day ignored). Needs Calendar access.")
                    .foregroundStyle(.secondary)
                Button("Enable Calendar access") {
                    PermissionManager.requestCalendar()
                    refreshStatus()
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show an alert when a calendar event is detected", isOn: $store.settings.alertOnCalendar)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configure Calendar Detection")
        .onAppear(perform: refreshStatus)
    }

    private func refreshStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized: statusText = "Calendar access: On"
        case .denied, .restricted: statusText = "Calendar access: Denied — enable in System Settings"
        case .writeOnly: statusText = "Calendar access: Write-only — need full access"
        case .notDetermined: statusText = "Calendar access: Not requested yet"
        @unknown default: statusText = "Calendar access: Unknown"
        }
    }
}

struct FocusOptionsPane: View {
    @Environment(AppController.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        Form {
            Section("Deep focus apps") {
                ForEach(store.settings.focusApps) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Match", selection: matchBinding(item.id)) {
                            ForEach(FocusMatch.allCases) { match in
                                Text(match.title).tag(match)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        Button("Remove") {
                            store.settings.focusApps.removeAll { $0.id == item.id }
                        }
                    }
                }
                Button("Add frontmost app") { addFrontmost() }
            }
            Section {
                Toggle("Show an alert when a focus app is detected", isOn: $store.settings.alertOnFocus)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configure Deep Focus Apps")
    }

    private func matchBinding(_ id: UUID) -> Binding<FocusMatch> {
        Binding {
            app.settingsStore.settings.focusApps.first { $0.id == id }?.match ?? .foreground
        } set: { match in
            if let index = app.settingsStore.settings.focusApps.firstIndex(where: { $0.id == id }) {
                app.settingsStore.settings.focusApps[index].match = match
            }
        }
    }

    private func addFrontmost() {
        guard let running = NSWorkspace.shared.frontmostApplication,
              let id = running.bundleIdentifier else { return }
        if app.settingsStore.settings.focusApps.contains(where: { $0.bundleID == id }) { return }
        app.settingsStore.settings.focusApps.append(
            FocusApp(id: UUID(), bundleID: id, name: running.localizedName ?? id, match: .foreground)
        )
    }
}

struct GamingOptionsPane: View {
    @Environment(AppController.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        Form {
            Section {
                Text("Pauses when a fullscreen game is frontmost (Steam / Epic / Games category).")
                    .foregroundStyle(.secondary)
                Toggle("Show an alert when gaming is detected", isOn: $store.settings.alertOnGame)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configure Gaming Detection")
    }
}

struct BundleIDListEditor: View {
    @Binding var ids: [String]

    var body: some View {
        ForEach(ids, id: \.self) { id in
            HStack {
                Text(displayName(id))
                Spacer()
                Button("Remove") { ids.removeAll { $0 == id } }
                    .buttonStyle(.borderless)
            }
        }
        Button {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  let id = app.bundleIdentifier,
                  !ids.contains(id) else { return }
            ids.append(id)
        } label: {
            Label("Add an app", systemImage: "plus")
        }
    }

    private func displayName(_ id: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            .flatMap { Bundle(url: $0)?.name } ?? id
    }
}

private extension Bundle {
    var name: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleIdentifier
            ?? "App"
    }
}

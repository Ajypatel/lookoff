import SwiftUI

struct AutomationsPane: View {
    @Environment(AppController.self) private var app
    @State private var editing: BreakAutomation.ID?

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsPage(tab: .automations) {
            SettingsCard(
                title: "When a break starts or ends",
                footnote: "Runs a Shortcut by name, AppleScript, or a zsh command. LookOff must stay running."
            ) {
                if store.settings.automations.isEmpty {
                    SettingsRow(title: "No automations yet") {
                        Button("Add") { addNew() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } else {
                    ForEach(Array(store.settings.automations.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SettingsHairline() }
                        automationRow(item)
                    }
                    SettingsHairline()
                    SettingsRow(title: "Add another") {
                        Button("Add") { addNew() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            if let editing, let idx = store.settings.automations.firstIndex(where: { $0.id == editing }) {
                editor(index: idx)
            }
        }
    }

    @ViewBuilder
    private func automationRow(_ item: BreakAutomation) -> some View {
        SettingsRow(title: item.title, subtitle: "\(item.trigger.title) · \(item.kind.title)") {
            HStack(spacing: 8) {
                Toggle("", isOn: enabledBinding(item.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                Button("Edit") { editing = item.id }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Remove") {
                    app.settingsStore.settings.automations.removeAll { $0.id == item.id }
                    if editing == item.id { editing = nil }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func editor(index: Int) -> some View {
        @Bindable var store = app.settingsStore
        SettingsCard(title: "Edit automation") {
            SettingsRow(title: "Name") {
                TextField("Name", text: $store.settings.automations[index].title)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            SettingsHairline()
            SettingsRow(title: "When") {
                Picker("", selection: $store.settings.automations[index].trigger) {
                    ForEach(AutomationTrigger.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            SettingsHairline()
            SettingsRow(title: "Kind") {
                Picker("", selection: $store.settings.automations[index].kind) {
                    ForEach(AutomationKind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            SettingsHairline()
            VStack(alignment: .leading, spacing: 8) {
                Text(payloadLabel(store.settings.automations[index].kind))
                    .font(.system(size: 13.5, weight: .medium))
                TextEditor(text: $store.settings.automations[index].payload)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 88)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(14)
        }
    }

    private func payloadLabel(_ kind: AutomationKind) -> String {
        switch kind {
        case .shortcut: "Shortcut name"
        case .appleScript: "AppleScript"
        case .shell: "Shell command"
        }
    }

    private func addNew() {
        var item = BreakAutomation()
        item.title = "New automation"
        app.settingsStore.settings.automations.append(item)
        editing = item.id
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding {
            app.settingsStore.settings.automations.first { $0.id == id }?.enabled ?? false
        } set: { on in
            if let idx = app.settingsStore.settings.automations.firstIndex(where: { $0.id == id }) {
                app.settingsStore.settings.automations[idx].enabled = on
            }
        }
    }
}

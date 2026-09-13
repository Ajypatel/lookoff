import SwiftUI

struct PlannedBreaksSection: View {
    @Environment(AppController.self) private var app
    @State private var editing: PlannedBreak?

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsCard(
            title: "Planned breaks",
            footnote: "Fixed clock times. Independent of office hours. Nearby interval breaks wait."
        ) {
            if store.settings.plannedBreaks.isEmpty {
                SettingsRow(title: "None") {
                    Button("Add") { editing = PlannedBreak() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                ForEach(Array(store.settings.plannedBreaks.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SettingsHairline() }
                    SettingsRow(title: item.name, subtitle: "\(Self.clock(item.startMinutes)) · \(item.durationLabel)") {
                        HStack(spacing: 8) {
                            Toggle("", isOn: enabledBinding(item.id))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            Button("Edit") { editing = item }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("Remove") {
                                store.settings.plannedBreaks.removeAll { $0.id == item.id }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                SettingsHairline()
                SettingsRow(title: "Add another") {
                    Button("Add") { editing = PlannedBreak() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .sheet(item: $editing) { item in
            PlannedBreakEditor(item: item) { saved in
                if let idx = store.settings.plannedBreaks.firstIndex(where: { $0.id == saved.id }) {
                    store.settings.plannedBreaks[idx] = saved
                } else {
                    store.settings.plannedBreaks.append(saved)
                }
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding {
            app.settingsStore.settings.plannedBreaks.first { $0.id == id }?.enabled ?? false
        } set: { on in
            if let idx = app.settingsStore.settings.plannedBreaks.firstIndex(where: { $0.id == id }) {
                app.settingsStore.settings.plannedBreaks[idx].enabled = on
            }
        }
    }

    private static func clock(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%d:%02d", h, m)
    }
}

private struct PlannedBreakEditor: View {
    @State var item: PlannedBreak
    var onSave: (PlannedBreak) -> Void
    var onCancel: () -> Void

    private let weekdays: [(Int, String)] = [
        (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Planned break")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            TextField("Name", text: $item.name)
                .textFieldStyle(.roundedBorder)
            DatePicker("Starts at", selection: startBinding, displayedComponents: .hourAndMinute)
            Stepper("Duration: \(item.durationLabel)", value: $item.durationSeconds, in: 60...7200, step: 60)
            HStack(spacing: 6) {
                ForEach(weekdays, id: \.0) { day, label in
                    let on = item.days.contains(day)
                    Button(label) {
                        if on {
                            item.days.removeAll { $0 == day }
                        } else {
                            item.days.append(day)
                        }
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
            TextField("SF Symbol", text: $item.symbol)
                .textFieldStyle(.roundedBorder)
            Toggle("Enabled", isOn: $item.enabled)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(item) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty || item.days.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var startBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: item.startMinutes / 60, minute: item.startMinutes % 60)) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            item.startMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }
}
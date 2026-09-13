import SwiftUI

struct StatsPane: View {
    @Environment(AppController.self) private var app

    var body: some View {
        let day = app.stats.today()
        let score = day.screenScore(workMinutes: app.settings.workMinutes)
        let apps = day.appSeconds.sorted { $0.value > $1.value }.prefix(8)

        SettingsPage(tab: .stats) {
            SettingsCard(title: "Today") {
                HStack(spacing: 16) {
                    scoreBlock(score)
                    VStack(alignment: .leading, spacing: 8) {
                        metric("Screen time", TimeFormat.overlay(day.screenSeconds))
                        metric("Breaks taken", "\(day.breaksTaken)")
                        metric("Skipped", "\(day.breaksSkipped)")
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
            }

            SettingsCard(title: "Sessions") {
                SettingsRow(title: "Longest uninterrupted") {
                    SettingsValueText(text: TimeFormat.overlay(day.longestSession))
                }
                SettingsHairline()
                SettingsRow(title: "Median session") {
                    SettingsValueText(text: TimeFormat.overlay(day.medianSession))
                }
            }

            SettingsCard(
                title: "App usage",
                footnote: "Time while LookOff counts you at the screen. Website-by-domain tracking is not included."
            ) {
                if apps.isEmpty {
                    Text("No samples yet. Keep the schedule running.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(14)
                } else {
                    ForEach(Array(apps.enumerated()), id: \.offset) { index, item in
                        if index > 0 { SettingsHairline() }
                        SettingsRow(title: item.key) {
                            SettingsValueText(text: TimeFormat.overlay(item.value))
                        }
                    }
                }
            }

            SettingsCard(title: "Screen Score") {
                Text("Up to 60 from session length vs your work interval, 40 from taking breaks instead of skipping.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
        }
    }

    private func scoreBlock(_ score: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(min(max(score, 0), 100))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Screen Score")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 108, height: 88)
        .background(SettingsChrome.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
    }
}

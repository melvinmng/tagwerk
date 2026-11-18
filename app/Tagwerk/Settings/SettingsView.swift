import RemindersKit
import SwiftUI
import TagwerkCore

/// The "Einstellungen" tab (mockup 5).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @State private var calendars: [ListInfo] = []
    @State private var reminderLists: [ListInfo] = []
    @State private var accessRevision = 0

    var body: some View {
        @Bindable var settings = environment.settings
        NavigationStack {
            Form {
                PlanningSettingsSection()

                Section("Mittagspause") {
                    DatePicker("Beginn", selection: time($settings.lunchStartMinutes), displayedComponents: .hourAndMinute)
                    Stepper("Dauer: \(settings.lunchDurationMinutes) min", value: $settings.lunchDurationMinutes, in: 0...180, step: 15)
                }

                Section {
                    Stepper("Puffer: \(settings.bufferMinutes) min", value: $settings.bufferMinutes, in: 0...60, step: 5)
                } footer: {
                    Text("Abstand zwischen Terminen und eingeplanten Aufgaben.")
                }

                Section("Quellen") {
                    NavigationLink {
                        SourceSelectionView(title: "Kalender", items: calendars,
                                            defaultSelection: CalendarSelection.defaultSelected(calendars),
                                            selection: $settings.selectedCalendarIDs)
                    } label: {
                        LabeledContent("Kalender", value: summary(settings.selectedCalendarIDs, all: calendars,
                                                                  fallback: CalendarSelection.defaultSelected(calendars)))
                    }
                    NavigationLink {
                        SourceSelectionView(title: "Erinnerungslisten", items: reminderLists,
                                            defaultSelection: Set(reminderLists.map(\.id)),
                                            selection: $settings.selectedReminderListIDs)
                    } label: {
                        LabeledContent("Erinnerungslisten", value: summary(settings.selectedReminderListIDs, all: reminderLists,
                                                                           fallback: Set(reminderLists.map(\.id))))
                    }
                }

                GitHubSettingsSection()

                Section {
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        LabeledContent("KI", value: aiSummary)
                    }
                }

                Section {
                    Stepper("Vorlauf: \(leadTimeText(settings.leadTimeMinutes))", value: $settings.leadTimeMinutes, in: 15...2880, step: 15)
                    Toggle("Deadline-Termine", isOn: $settings.deadlineCalendarNotifications)
                } header: {
                    Text("Benachrichtigungen")
                } footer: {
                    Text(notificationFooter)
                }

                Section("Zugriff") {
                    accessRow("Erinnerungen", state: environment.gateway.accessState) {
                        _ = try? await environment.gateway.requestAccess()
                    }
                    accessRow("Kalender", state: environment.gateway.calendarAccessState) {
                        _ = try? await environment.gateway.requestCalendarAccess()
                    }
                    accessRow("Benachrichtigungen", state: notificationAccess,
                              settingsURL: UIApplication.openNotificationSettingsURLString) {
                        await environment.notifications.requestAuthorization()
                    }
                }
                .id(accessRevision)

                Section {
                    Button("Einrichtung erneut starten") { environment.restartSetup() }
                }
            }
            .navigationTitle("Einstellungen")
            .assistantToolbarButton { .settings }
            .task {
                loadSources()
                await environment.ai.refreshAccount()
                await environment.notifications.refreshAuthorization()
            }
            .onChange(of: settings.selectedReminderListIDs) { _, _ in
                Task { await environment.taskList.reload() }
            }
        }
    }

    /// Right side of the "KI" row, from stored state only; opening the settings loads nothing (§8.4).
    private var aiSummary: String {
        let ai = environment.ai
        guard ai.isSignedIn else { return "nicht angemeldet" }
        guard let slug = ai.selectedModelSlug else { return "Automatisch" }
        return ai.models.first { $0.slug == slug }?.displayName ?? slug
    }

    /// Notification permission in the terms of the other access rows.
    private var notificationAccess: AccessState {
        switch environment.notifications.authorization {
        case .authorized: .fullAccess
        case .notDetermined: .notDetermined
        case .denied: .denied
        }
    }

    private var notificationFooter: String {
        switch environment.notifications.authorization {
        case .authorized:
            "So lange vor der Fälligkeit erinnert Tagwerk an GitHub- und lokale Aufgaben und an Termine aus Deadline-Kalendern. Ein Datum ohne Uhrzeit gilt als 18:00. An ganztägige Deadline-Termine erinnert Tagwerk am Vortag um 18:00."
        case .notDetermined:
            "Benachrichtigungen sind noch nicht erlaubt. Erlaube sie unten unter „Zugriff“."
        case .denied:
            "Benachrichtigungen sind in iOS ausgeschaltet. Schalte sie unten unter „Zugriff“ wieder ein."
        }
    }

    private func loadSources() {
        calendars = environment.gateway.calendarAccessState == .fullAccess ? environment.gateway.calendars() : []
        reminderLists = environment.gateway.accessState == .fullAccess ? environment.gateway.lists() : []
    }

    @ViewBuilder
    private func accessRow(_ title: String, state: AccessState, settingsURL: String = UIApplication.openSettingsURLString,
                           request: @escaping () async -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            switch state {
            case .fullAccess:
                Text("erlaubt").foregroundStyle(.secondary)
            case .notDetermined:
                Button("Erlauben") {
                    Task {
                        await request()
                        accessRevision += 1
                        loadSources()
                        await environment.taskList.reload()
                    }
                }
            default:
                Button("Einstellungen öffnen") {
                    if let url = URL(string: settingsURL) { openURL(url) }
                }
            }
        }
    }

    private func summary(_ selection: [String]?, all: [ListInfo], fallback: Set<String>) -> String {
        guard !all.isEmpty else { return "–" }
        let count = selection.map { Set($0).intersection(all.map(\.id)).count } ?? fallback.count
        return count == all.count ? "Alle" : "\(count) von \(all.count)"
    }

    private func leadTimeText(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%d:%02d h", minutes / 60, minutes % 60)
    }

    /// Bridges "minutes since midnight" to a `Date` for time pickers.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        let calendar = Calendar.tagwerk
        return Binding(
            get: {
                calendar.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

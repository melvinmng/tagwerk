import HealthBridge
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
    @State private var healthAccess: HealthAccess = .notDetermined
    @State private var stepsAccess: StepsAccess = .asked

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
                                            selection: $settings.selectedReminderListIDs,
                                            lockedIDs: settings.shoppingListID.map { [$0: "Einkaufsliste"] } ?? [:])
                    } label: {
                        LabeledContent("Erinnerungslisten",
                                       value: ReminderListSummary.text(selected: settings.selectedReminderListIDs, lists: reminderLists,
                                                                       shopping: settings.shoppingListID))
                    }
                    NavigationLink {
                        ShoppingSettingsView()
                    } label: {
                        LabeledContent("Einkaufsliste", value: shoppingListSummary)
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
                    NavigationLink {
                        CaptureSettingsView()
                    } label: {
                        LabeledContent("Erfassen", value: IntakeFormat.goalSummary(
                            kcal: settings.goalKilocalories, waterMilliliters: settings.goalWaterMilliliters,
                            workoutMinutesPerWeek: settings.goalWorkoutMinutesPerWeek))
                    }
                }

                Section {
                    NavigationLink {
                        RoutineSettingsView()
                    } label: {
                        LabeledContent("Routinen", value: DateText.time(minutes: settings.bedtimeMinutes, calendar: .tagwerk))
                    }
                    NavigationLink {
                        NotesSettingsView()
                    } label: {
                        LabeledContent("Notizen", value: NotesSettingsView.sortName(settings.noteSortOrder))
                    }
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        LabeledContent("Datensicherung", value: BackupSettingsView.lastBackupText(settings.lastAutoBackupAt))
                    }
                }

                Section {
                    Stepper("Vorlauf: \(leadTimeText(settings.leadTimeMinutes))", value: $settings.leadTimeMinutes, in: 15...2880, step: 15)
                    Toggle("GitHub-Issues", isOn: $settings.githubTaskNotifications)
                    Toggle("Erinnerungen", isOn: $settings.reminderTaskNotifications)
                    Toggle("Lokale Aufgaben", isOn: $settings.localTaskNotifications)
                    Toggle("Deadline-Termine", isOn: $settings.deadlineCalendarNotifications)
                } header: {
                    Text("Benachrichtigungen")
                } footer: {
                    Text(notificationFooter)
                }

                Section {
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
                    healthRow
                    stepsRow
                } header: {
                    Text("Zugriff")
                } footer: {
                    Text(healthFooter)
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
                healthAccess = await environment.health.access()
                stepsAccess = await environment.health.stepsAccess()
            }
            .onChange(of: settings.selectedReminderListIDs) { _, _ in
                Task { await environment.taskList.reload() }
            }
        }
    }

    /// Right side of the "KI" row, from stored state only; opening the settings loads nothing (§8.4).
    private var aiSummary: String {
        let ai = environment.ai
        guard ai.isSignedIn else { return String(localized: "nicht angemeldet") }
        guard let slug = ai.selectedModelSlug else { return String(localized: "Automatisch") }
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
            String(localized: "So lange vor der Fälligkeit erinnert Tagwerk an Aufgaben und Deadline-Termine der eingeschalteten Quellen. Deadline-Termine sind Termine aus Deadline-Kalendern und als Deadline markierte Termine. An Aufgaben ohne Uhrzeit erinnert Tagwerk am Fälligkeitstag um 9:00. An ganztägige Deadline-Termine erinnert Tagwerk am Vortag um 18:00.")
        case .notDetermined:
            String(localized: "Benachrichtigungen sind noch nicht erlaubt. Erlaube sie unten unter „Zugriff“.")
        case .denied:
            String(localized: "Benachrichtigungen sind in iOS ausgeschaltet. Schalte sie unten unter „Zugriff“ wieder ein.")
        }
    }

    /// The "Health" access row; only write access is visible (iOS hides denied reading).
    @ViewBuilder
    private var healthRow: some View {
        HStack {
            Text("Health")
            Spacer()
            switch healthAccess {
            case .unavailable:
                Text("nicht verfügbar").foregroundStyle(.secondary)
            case .notDetermined:
                Button("Verbinden") {
                    Task {
                        await environment.capture.connectHealth()
                        healthAccess = await environment.health.access()
                        stepsAccess = await environment.health.stepsAccess()
                    }
                }
            case .authorized:
                Text("verbunden").foregroundStyle(.secondary)
            case .partial:
                Button("teilweise · Health öffnen") { openHealth() }
            case .denied:
                Button("Health öffnen") { openHealth() }
            }
        }
    }

    /// "Schritte" while the step sheet was never shown; it asks for steps only and leaves the other Health access alone.
    /// Before Health is connected at all, the "Verbinden" button above asks for everything in one sheet.
    @ViewBuilder
    private var stepsRow: some View {
        if stepsAccess == .notAsked, healthAccess.wasAsked {
            HStack {
                Text("Schritte")
                Spacer()
                Button("Schritte erlauben") {
                    Task {
                        await environment.capture.connectSteps()
                        stepsAccess = await environment.health.stepsAccess()
                    }
                }
            }
        }
    }

    private var healthFooter: String {
        switch healthAccess {
        case .partial(let kinds):
            String(localized: "Nicht nach Health geschrieben werden: \(kinds.map(\.displayName).joined(separator: ", ")). Deine Einträge bleiben in Tagwerk.")
        case .denied:
            String(localized: "Tagwerk darf nicht nach Health schreiben. Deine Einträge bleiben in Tagwerk. Ändern kannst du das in der App „Health“ unter Profil › Apps › Tagwerk.")
        default:
            String(localized: "Tagwerk schreibt Mahlzeiten, Wasser und Trainings nach Health und liest Trainings und Schritte. Ob das Lesen erlaubt ist, zeigt iOS nicht an: Fehlen Trainings der Apple Watch oder steht bei den Schritten nur „–“, prüfe den Zugriff in der App „Health“ unter Profil › Apps › Tagwerk.")
        }
    }

    private func openHealth() {
        if let url = URL(string: "x-apple-health://") { openURL(url) }
    }

    private func loadSources() {
        calendars = environment.gateway.calendarAccessState == .fullAccess ? environment.gateway.calendars() : []
        reminderLists = environment.reminderStore.accessState == .fullAccess ? environment.reminderStore.lists() : []
    }

    /// Title of the reminder list that serves as the shopping list, or "Keine".
    private var shoppingListSummary: String {
        guard let id = environment.settings.shoppingListID,
              let list = reminderLists.first(where: { $0.id == id }) else { return String(localized: "Keine") }
        return list.title
    }

    @ViewBuilder
    private func accessRow(_ title: LocalizedStringKey, state: AccessState, settingsURL: String = UIApplication.openSettingsURLString,
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
        return count == all.count ? String(localized: "Alle") : String(localized: "\(count) von \(all.count)")
    }

    private func leadTimeText(_ minutes: Int) -> String {
        minutes % 60 == 0 ? String(localized: "\(minutes / 60) h")
            : String(localized: "\(minutes / 60):\(String(format: "%02d", minutes % 60)) h")
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

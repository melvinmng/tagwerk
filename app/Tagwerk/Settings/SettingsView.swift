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
        NavigationStack(path: Bindable(environment).settingsPath) {
            Form {
                PlanningSettingsSection()

                Section {
                    DatePicker("Beginn", selection: time($settings.lunchStartMinutes), displayedComponents: .hourAndMinute)
                    ValueStepper("Dauer", value: $settings.lunchDurationMinutes, in: 0...180, step: 15, kind: .durationMinutes,
                                 unit: "min", display: ValueStepper.minutesText)
                } header: {
                    Text("Mittagspause")
                        .foregroundStyle(.secondaryText)
                }

                Section {
                    ValueStepper("Puffer", value: $settings.bufferMinutes, in: 0...60, step: 5, kind: .durationMinutes,
                                 unit: "min", display: ValueStepper.minutesText)
                } footer: {
                    Text("Abstand zwischen Terminen und eingeplanten Aufgaben.")
                        .foregroundStyle(.secondaryText)
                }

                Section {
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
                } header: {
                    Text("Quellen")
                        .foregroundStyle(.secondaryText)
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
                    NavigationLink {
                        FocusSettingsView()
                    } label: {
                        LabeledContent("Fokus-Timer", value: FocusTimerText.settingsSummary(settings.focusTimerSettings))
                    }
                    NavigationLink {
                        SiriShortcutsSettingsView()
                    } label: {
                        LabeledContent("Siri & Kurzbefehle", value: String(localized: "\(SiriPhraseCatalog.shortcutCount) Kurzbefehle"))
                    }
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        LabeledContent("Sprachen", value: LanguageSettingsText.summary(settings.contentLanguages))
                    }
                }

                Section {
                    NavigationLink {
                        ReminderDefaultsView()
                    } label: {
                        LabeledContent("Standard-Erinnerungen",
                                       value: ReminderText.summary(settings.reminderDefaults.offsets(for: .localTask, isAllDay: false),
                                                                   subject: .task, locale: .current, calendar: .tagwerk))
                    }
                    Toggle("GitHub-Issues", isOn: $settings.githubTaskNotifications)
                    Toggle("Erinnerungen", isOn: $settings.reminderTaskNotifications)
                    Toggle("Lokale Aufgaben", isOn: $settings.localTaskNotifications)
                    Toggle("Deadline-Termine", isOn: $settings.deadlineCalendarNotifications)
                    NavigationLink {
                        QuietHoursSettingsView()
                    } label: {
                        LabeledContent("Ruhezeiten", value: QuietHoursSettingsView.summary(settings))
                    }
                } header: {
                    Text("Benachrichtigungen")
                        .foregroundStyle(.secondaryText)
                } footer: {
                    Text(notificationFooter)
                        .foregroundStyle(.secondaryText)
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
                        .foregroundStyle(.secondaryText)
                } footer: {
                    Text(healthFooter)
                        .foregroundStyle(.secondaryText)
                }
                .id(accessRevision)

                Section {
                    Button("Einrichtung erneut starten") { environment.restartSetup() }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .languages: LanguageSettingsView()
                case .ai: AISettingsView()
                case .aiVoice: VoiceSettingsView()
                case .capture: CaptureSettingsView()
                case .shopping: ShoppingSettingsView()
                case .siri: SiriShortcutsSettingsView()
                }
            }
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
            String(localized: "Die Standard-Erinnerungen legen fest, wann Tagwerk an Aufgaben und Deadline-Termine der eingeschalteten Quellen erinnert. Einzelne Aufgaben und Deadlines lassen sich abweichend einstellen. Deadline-Termine sind Termine aus Deadline-Kalendern und als Deadline markierte Termine.")
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
                Text("nicht verfügbar").foregroundStyle(.secondaryText)
            case .notDetermined:
                Button("Verbinden") {
                    Task {
                        await environment.capture.connectHealth()
                        healthAccess = await environment.health.access()
                        stepsAccess = await environment.health.stepsAccess()
                    }
                }
            case .authorized:
                Text("verbunden").foregroundStyle(.secondaryText)
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
                Text("erlaubt").foregroundStyle(.secondaryText)
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

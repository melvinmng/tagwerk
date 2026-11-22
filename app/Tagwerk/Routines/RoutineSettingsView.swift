import SwiftUI
import TagwerkCore

/// Einstellungen › Routinen (mockup GS·E, design §11): bedtime, evening checklist, morning reminder, "Planen" and the
/// consent for suggestions from a thought note.
struct RoutineSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @State private var editing: ChecklistItem?
    @State private var isAdding = false

    var body: some View {
        @Bindable var settings = environment.settings
        let store = environment.routineStore
        let items = store.checklist()
        let conflict = RoutineSchedule.quietHoursConflict(
            settings.quietHours, items: items, bedtimeMinutes: settings.bedtimeMinutes, eveningEnabled: settings.eveningRemindersEnabled,
            morningEnabled: settings.morningReminderEnabled, morningMinutes: settings.morningReminderMinutes,
            weekEnabled: settings.weekPlanningReminderEnabled, weekMinutes: settings.weekPlanningReminderMinutes)
        Form {
            Section {
                DatePicker("Zielschlafzeit", selection: $settings.bedtimeMinutes.asTime(), displayedComponents: .hourAndMinute)
                Toggle("Erinnerungen am Abend", isOn: $settings.eveningRemindersEnabled)
                if settings.eveningRemindersEnabled, environment.routineNotifications.authorization != .authorized {
                    notificationHint
                }
            } header: {
                Text("Tagesabschluss")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Abgehakte Punkte erinnern an dem Abend nicht mehr. Tagwerk plant die Erinnerungen für die nächsten 3 Tage und füllt sie nach, sobald du die App öffnest.")
                    if conflict.evening { Text(Self.quietHoursNote) }
                }
            }

            Section {
                ForEach(items) { item in
                    Button { editing = item } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(detail(item, bedtime: settings.bedtimeMinutes)).font(.caption).foregroundStyle(.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in offsets.map { items[$0].id }.forEach(store.deleteItem) }
                .onMove { source, destination in
                    var ids = items.map(\.id)
                    ids.move(fromOffsets: source, toOffset: destination)
                    store.reorderItems(ids)
                }
                if items.isEmpty {
                    Button("Vorschlag übernehmen") { store.adoptSuggestion() }
                }
                Button { isAdding = true } label: { Label("Punkt hinzufügen", systemImage: "plus.circle") }
                    .disabled(items.count >= RoutineSchedule.maximumItems)
            } header: {
                Text("Abend-Checkliste")
            } footer: {
                Text("Die Zeiten folgen der Schlafzeit. Höchstens vier Punkte erinnern; weitere stehen nur in der Liste.")
            }

            Section {
                Toggle("Erinnerung", isOn: $settings.morningReminderEnabled)
                if settings.morningReminderEnabled {
                    DatePicker("Uhrzeit", selection: $settings.morningReminderMinutes.asTime(), displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Tagesstart")
            } footer: {
                if conflict.morning { Text(Self.quietHoursNote) }
            }

            Section {
                Toggle("Erinnerung", isOn: $settings.weekPlanningReminderEnabled)
                if settings.weekPlanningReminderEnabled {
                    Picker("Wochentag", selection: $settings.weekPlanningReminderWeekday) {
                        let names = Calendar.tagwerk.standaloneWeekdaySymbols
                        ForEach(1...7, id: \.self) { weekday in Text(names[weekday - 1]).tag(weekday) }
                    }
                    DatePicker("Uhrzeit", selection: $settings.weekPlanningReminderMinutes.asTime(), displayedComponents: .hourAndMinute)
                    if environment.routineNotifications.authorization != .authorized { notificationHint }
                }
            } header: {
                Text("Wochenplanung")
            } footer: {
                if conflict.week { Text(Self.quietHoursNote) }
            }

            Section {
                Toggle("In Planen anzeigen", isOn: $settings.showsRoutinesInPlan)
            } header: {
                Text("Planen")
            } footer: {
                Text("Zeigt die Karte „Tagesstart“ bzw. „Fokus heute“ und abends die Zeile „Tagesabschluss“ im Tab „Planen“.")
            }

            Section {
                Picker("Bible Study anbieten", selection: $settings.bibleStudyOffer) {
                    Text("Im Tagesabschluss").tag(BibleStudyOffer.evening)
                    Text("Im Tagesstart").tag(BibleStudyOffer.morning)
                    Text("In beiden").tag(BibleStudyOffer.both)
                    Text("Nirgends").tag(BibleStudyOffer.never)
                }
            } header: {
                Text("Bible Study")
            } footer: {
                Text("Wo die Zeile „Bible Study starten“ in den Routinen steht. Das Tagebuch steht im Tagesabschluss.")
            }

            Section {
                NavigationLink("Gewohnheiten bearbeiten") { HabitListView(model: environment.habits) }
            } header: {
                Text("Gewohnheiten")
            }

            Section {
                Toggle("Notizen an ChatGPT senden", isOn: $settings.noteSuggestionConsent)
                    .disabled(!environment.ai.isSignedIn)
            } header: {
                Text("Brain Dump")
            } footer: {
                if environment.ai.isSignedIn {
                    Text("Für Vorschläge sendet Tagwerk den Text der jeweiligen Brain-Dump-Notiz sowie deine offenen Aufgaben und Termine der nächsten 7 Tage (Titel, Fälligkeit, Zeit) an ChatGPT (OpenAI), und nur, wenn du bei der Notiz auf „Vorschläge holen“ tippst. Dankbarkeit, Dream Log, Gewohnheiten, Wochenreflexion, Daten aus Health und frühere Notizen werden nie gesendet.")
                } else {
                    Text("Melde dich unter Einstellungen › KI bei ChatGPT an, um Vorschläge aus einer Notiz zu holen.")
                }
            }
        }
        .navigationTitle("Routinen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !items.isEmpty { EditButton() } }
        .sheet(item: $editing) { item in
            ChecklistItemSheet(store: store, bedtimeMinutes: settings.bedtimeMinutes, item: item, isNew: false)
        }
        .sheet(isPresented: $isAdding) {
            ChecklistItemSheet(store: store, bedtimeMinutes: settings.bedtimeMinutes,
                               item: ChecklistItem(title: "", order: items.count, offsetMinutes: 30), isNew: true)
        }
        .task {
            await environment.ai.refreshAccount()
            // Reads the permission; the hint above follows it.
            await environment.routineNotifications.reschedule()
        }
    }

    /// Without permission the reminders cannot appear; the card and the line in "Planen" stay the way in.
    @ViewBuilder
    private var notificationHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mitteilungen sind für Tagwerk nicht erlaubt. Ohne Erlaubnis erinnert nur die Zeile in „Planen“.",
                  systemImage: "bell.slash")
                .font(.footnote).foregroundStyle(.secondaryText)
            Button(environment.routineNotifications.authorization == .notDetermined ? "Mitteilungen erlauben" : "Mitteilungen in den Einstellungen") {
                if environment.routineNotifications.authorization == .notDetermined {
                    Task {
                        await environment.notifications.requestAuthorization()
                        await environment.routineNotifications.reschedule()
                    }
                } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        }
    }

    /// "60 min vorher · 22:00" or "ohne Erinnerung".
    private func detail(_ item: ChecklistItem, bedtime: Int) -> String {
        guard let offset = item.offsetMinutes else { return String(localized: "ohne Erinnerung") }
        let clock = DateText.time(minutes: RoutineSchedule.anchorMinutes(bedtimeMinutes: bedtime, offsetMinutes: offset),
                                  calendar: .tagwerk)
        return String(localized: "\(offset) min vorher · \(clock)")
    }

    /// Routine reminders are exempt from the quiet hours; the hint says so where one of them falls into the window.
    private static var quietHoursNote: String {
        String(localized: "Eine dieser Erinnerungen liegt in den Ruhezeiten. Routine-Erinnerungen kommen trotzdem.")
    }
}

/// One checklist point: name, and an optional reminder some minutes before bedtime.
private struct ChecklistItemSheet: View {
    let store: RoutineStore
    let bedtimeMinutes: Int
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var item: ChecklistItem
    @State private var remindsMe: Bool
    @State private var refused = false

    init(store: RoutineStore, bedtimeMinutes: Int, item: ChecklistItem, isNew: Bool) {
        self.store = store
        self.bedtimeMinutes = bedtimeMinutes
        self.isNew = isNew
        _item = State(initialValue: item)
        _remindsMe = State(initialValue: item.offsetMinutes != nil)
    }

    private var otherReminders: Int {
        store.checklist().filter { $0.id != item.id && $0.offsetMinutes != nil }.count
    }

    private var canRemind: Bool { remindsMe || otherReminders < RoutineSchedule.maximumReminders }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $item.title)
                        .onChange(of: item.title) { _, value in
                            if value.count > RoutineSchedule.titleLimit { item.title = String(value.prefix(RoutineSchedule.titleLimit)) }
                        }
                }
                Section {
                    Toggle("Erinnerung", isOn: $remindsMe).disabled(!canRemind)
                    if remindsMe {
                        let offset = item.offsetMinutes ?? 30
                        ValueStepper("Abstand", value: Binding(get: { item.offsetMinutes ?? 30 }, set: { item.offsetMinutes = $0 }),
                                     in: RoutineSchedule.offsetRange, step: RoutineSchedule.offsetStep, kind: .durationMinutes,
                                     unit: "min") { String(localized: "\($0) min vorher") }
                        LabeledContent("Uhrzeit", value: DateText.time(
                            minutes: RoutineSchedule.anchorMinutes(bedtimeMinutes: bedtimeMinutes, offsetMinutes: offset),
                            calendar: .tagwerk))
                    }
                } footer: {
                    if !canRemind {
                        Text("Höchstens vier Punkte erinnern. Schalte bei einem anderen Punkt die Erinnerung aus.")
                    } else if refused {
                        Text("Der Punkt konnte nicht gespeichert werden.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "Neuer Punkt" : "Punkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: save)
                        .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: remindsMe) { _, reminds in
                item.offsetMinutes = reminds ? (item.offsetMinutes ?? 30) : nil
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        if store.saveItem(item) { dismiss() } else { refused = true }
    }
}

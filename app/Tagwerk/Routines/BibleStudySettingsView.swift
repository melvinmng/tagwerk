import SwiftUI
import TagwerkCore

/// Einstellungen › Routinen › Bible Study (BS6c, BE2b): where "Bible Study starten" is offered and the reminder times with their
/// weekdays, like the alarms of the clock app.
struct BibleStudySettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @State private var editing: BibleStudyReminderTime?
    @State private var isAdding = false

    var body: some View {
        @Bindable var settings = environment.settings
        let times = settings.bibleStudyReminderTimes
        Form {
            Section {
                Picker("Bible Study anbieten", selection: $settings.bibleStudyOffer) {
                    Text("Im Tagesabschluss").tag(BibleStudyOffer.evening)
                    Text("Im Tagesstart").tag(BibleStudyOffer.morning)
                    Text("In beiden").tag(BibleStudyOffer.both)
                    Text("Nirgends").tag(BibleStudyOffer.never)
                }
            } footer: {
                Text("Wo die Zeile „Bible Study starten“ in den Routinen steht. Das Tagebuch steht im Tagesabschluss.")
            }

            Section {
                Toggle("Erinnerung", isOn: reminderBinding)
                if settings.bibleStudyReminderEnabled, environment.routineNotifications.authorization != .authorized { notificationHint }
            } footer: {
                Text("Übernommene Zeiten ändern sich nicht von selbst. Entfällt an Tagen mit abgeschlossener Sitzung. Tagwerk plant die Erinnerung für die nächsten 3 Tage und füllt sie nach, sobald du die App öffnest.")
            }

            if settings.bibleStudyReminderEnabled {
                Section {
                    ForEach(times) { time in
                        Button { editing = time } label: {
                            HStack {
                                Text(BibleStudyReminderTimes.summary(time, locale: locale))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .tint(.primary)
                    }
                    Button { isAdding = true } label: { Label("Zeit hinzufügen", systemImage: "plus.circle") }
                        .frame(minHeight: 44, alignment: .leading)
                        .disabled(times.flatMap(\.weekdays).count >= 7)
                } header: {
                    Text("Zeiten")
                }

                Section {
                    Toggle("Stelle in der Mitteilung zeigen", isOn: $settings.bibleStudyReminderShowsPassage)
                } footer: {
                    Text("Die Mitteilung nennt Buch und nächsten Vers, zum Beispiel „Weiter in Römer ab 3,27“. Sie steht auch auf dem Sperrbildschirm. Ausgeschaltet heißt es nur „Zeit für Bible Study.“")
                }
            }

        }
        .navigationTitle("Bible Study")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { time in
            BibleStudyTimeSheet(time: time, isNew: false)
        }
        .sheet(isPresented: $isAdding) {
            // A new time starts with the weekdays no other time uses; the first is 07:00 on every free day.
            let taken = BibleStudyReminderTimes.takenWeekdays(for: BibleStudyReminderTime(minutes: 0, weekdays: []), in: times)
            BibleStudyTimeSheet(time: BibleStudyReminderTime(minutes: 420, weekdays: Set(1...7).subtracting(taken)), isNew: true)
        }
        .task { await environment.routineNotifications.reschedule() }
    }

    /// Switching on asks for the permission when it was not asked yet; the first time is 06:45 on every day.
    private var reminderBinding: Binding<Bool> {
        Binding(get: { environment.settings.bibleStudyReminderEnabled }, set: { isOn in
            environment.settings.bibleStudyReminderEnabled = isOn
            guard isOn else { return }
            if environment.settings.bibleStudyReminderTimes.isEmpty {
                environment.settings.bibleStudyReminderTimes = [BibleStudyReminderTime(minutes: 405, weekdays: Set(1...7))]
            }
            Task {
                if environment.routineNotifications.authorization == .notDetermined { await environment.notifications.requestAuthorization() }
                await environment.routineNotifications.reschedule()
            }
        })
    }

    @ViewBuilder
    private var notificationHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mitteilungen sind für Tagwerk nicht erlaubt. Ohne Erlaubnis erinnert nur die Zeile in „Planen“.", systemImage: "bell.slash")
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
            .frame(minHeight: 44, alignment: .leading)
        }
    }
}

/// One reminder time: the clock time in steps of five minutes and the weekdays. Days that another time uses are greyed out.
struct BibleStudyTimeSheet: View {
    let isNew: Bool
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var time: BibleStudyReminderTime

    init(time: BibleStudyReminderTime, isNew: Bool) {
        self.isNew = isNew
        _time = State(initialValue: time)
    }

    var body: some View {
        let others = environment.settings.bibleStudyReminderTimes
        let taken = BibleStudyReminderTimes.takenWeekdays(for: time, in: others)
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker("Stunde", selection: Binding(get: { time.minutes / 60 }, set: { time.minutes = $0 * 60 + time.minutes % 60 })) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .pickerStyle(.wheel)
                        Picker("Minute", selection: Binding(get: { time.minutes % 60 / 5 * 5 }, set: { time.minutes = time.minutes / 60 * 60 + $0 })) {
                            ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .pickerStyle(.wheel)
                    }
                    .frame(height: 120)
                }
                Section {
                    weekdayButtons(taken: taken)
                } header: {
                    Text("An diesen Tagen")
                } footer: {
                    if let note = BibleStudyReminderText.takenNote(taken: taken, others: others, own: time, locale: locale) { Text(note) }
                }
                if !isNew {
                    Section {
                        Button("Zeit löschen", role: .destructive) {
                            environment.settings.bibleStudyReminderTimes = others.filter { $0.id != time.id }
                            dismiss()
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
            .navigationTitle("Zeit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        environment.settings.bibleStudyReminderTimes = BibleStudyReminderTimes.saving(time, into: others)
                        dismiss()
                    }
                    .disabled(time.weekdays.subtracting(taken).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func weekdayButtons(taken: Set<Int>) -> some View {
        let names = BibleStudyReminderTimes.weekdayNames(Set(1...7), locale: locale)
        return HStack(spacing: 4) {
            ForEach(Array(BibleStudyReminderTimes.weekdaysFromMonday.enumerated()), id: \.element) { index, weekday in
                let isTaken = taken.contains(weekday)
                let isOn = time.weekdays.contains(weekday) && !isTaken
                Button {
                    if isOn { time.weekdays.remove(weekday) } else { time.weekdays.insert(weekday) }
                } label: {
                    Text(names[index])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isTaken)
                .foregroundStyle(isTaken ? Color.secondaryText : Color.primary)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Texts of the settings page as static functions, so they can be tested.
enum BibleStudyReminderText {
    /// "Mo–Fr sind schon bei 06:45 vergeben und hier nicht wählbar."; `nil` while no other time holds a weekday.
    static func takenNote(taken: Set<Int>, others: [BibleStudyReminderTime], own: BibleStudyReminderTime, locale: Locale) -> String? {
        let parts = others.filter { $0.id != own.id && !$0.weekdays.isEmpty }.map { other -> String in
            let days = weekdayList(other.weekdays, locale: locale)
            let clock = BibleStudyReminderTimes.clock(other.minutes, locale: locale)
            return other.weekdays.count == 1
                ? String(localized: "\(days) ist schon bei \(clock) vergeben und hier nicht wählbar.")
                : String(localized: "\(days) sind schon bei \(clock) vergeben und hier nicht wählbar.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "Mo–Fr", "Sa und So", "Mo, Mi und Fr": runs of three or more days are written as a range.
    static func weekdayList(_ weekdays: Set<Int>, locale: Locale) -> String {
        let names = BibleStudyReminderTimes.weekdayNames(Set(1...7), locale: locale)
        let flags = BibleStudyReminderTimes.weekdaysFromMonday.map { weekdays.contains($0) }
        var items: [String] = []
        var index = 0
        while index < flags.count {
            guard flags[index] else { index += 1; continue }
            var end = index
            while end + 1 < flags.count, flags[end + 1] { end += 1 }
            if end - index >= 2 {
                items.append("\(names[index])–\(names[end])")
            } else {
                items.append(contentsOf: names[index...end])
            }
            index = end + 1
        }
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " " + String(localized: "und") + " " + items[items.count - 1]
    }
}

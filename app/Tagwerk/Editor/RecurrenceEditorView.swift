import SwiftUI
import TagwerkCore

/// The page "Wiederholung" (mockup RK3), shared by the task editor and "Neue Aufgabe": sentence, presets,
/// controls, end, the next occurrences and what the change means. Changes reach the form only after the
/// user's first choice, so opening the page never rewrites a rule.
struct RecurrenceEditorView: View {
    @State private var model: RecurrenceEditorModel
    /// The rule saved at the source, shown as "Bisher" once the user changes it.
    let previous: Recurrence?
    /// The due date the series starts on; `nil` when the form has none yet (it is set with the first rule).
    let dueDay: PlanDay?
    /// Planned blocks that would lie on days without an occurrence (existing series only).
    let blocksOffSeries: ((Recurrence) -> [CalendarEvent])?
    let onChange: (Recurrence?) -> Void
    /// Moves the due date to the suggested day.
    let onMoveDue: (PlanDay) -> Void
    @Environment(\.dismiss) private var dismiss

    init(original: Recurrence?, previous: Recurrence? = nil, start: PlanDay, dueDay: PlanDay?, calendar: Calendar,
         blocksOffSeries: ((Recurrence) -> [CalendarEvent])? = nil,
         onChange: @escaping (Recurrence?) -> Void, onMoveDue: @escaping (PlanDay) -> Void) {
        _model = State(initialValue: RecurrenceEditorModel(original: original, start: start, calendar: calendar))
        self.previous = previous
        self.dueDay = dueDay
        self.blocksOffSeries = blocksOffSeries
        self.onChange = onChange
        self.onMoveDue = onMoveDue
    }

    private var calendar: Calendar { model.calendar }

    var body: some View {
        Form {
            ruleSection
            presetSection
            if model.frequency != nil {
                frequencySection
                endSection
                previewSection
            }
        }
        .navigationTitle("Wiederholung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .onChange(of: model.recurrence) { _, recurrence in
            if model.isChanged { onChange(recurrence) }
        }
    }

    // MARK: Sections

    private var ruleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.isUnsupportedOriginal && !model.isChanged ? String(localized: "Eigene Regel aus Erinnerungen") : model.summary)
                    .font(.headline)
                if model.isChanged, let previous, previous.rule != .unsupported,
                   RecurrenceText.summary(previous, calendar: calendar) != model.summary {
                    Text("Bisher: \(RecurrenceText.summary(previous, calendar: calendar))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let last = model.lastOccurrence {
                    Text("Letzter Termin: \(longDay(last))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("Regel")
        } footer: {
            if model.isUnsupportedOriginal && !model.isChanged {
                Text("Tagwerk kann diese Regel nicht darstellen und reserviert nur am nächsten Fälligkeitstag. Solange hier nichts gewählt wird, bleibt die Regel in Erinnerungen genau so, wie sie ist. Eine Auswahl ersetzt sie vollständig.")
            }
        }
    }

    private var presetSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(String(localized: "Nie"), isSelected: model.isNever) { model.selectNever() }
                    ForEach(RecurrencePreset.allCases, id: \.self) { preset in
                        chip(Self.title(of: preset), isSelected: model.selectedPreset == preset) { model.apply(preset: preset) }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        } footer: {
            if model.isNever || model.frequency == nil {
                EmptyView()
            } else {
                Text("Wochentag und Tag des Monats kommen vom Fälligkeitsdatum.")
            }
        }
    }

    private var frequencySection: some View {
        Section {
            Picker("Häufigkeit", selection: frequency) {
                Text("Tag").tag(RecurrenceEditorModel.Frequency.day)
                Text("Woche").tag(RecurrenceEditorModel.Frequency.week)
                Text("Monat").tag(RecurrenceEditorModel.Frequency.month)
                Text("Jahr").tag(RecurrenceEditorModel.Frequency.year)
            }
            .pickerStyle(.segmented)
            Stepper(intervalText, value: interval, in: model.intervalRange)
            if model.frequency == .week { weekdayCircles }
            if model.frequency == .month { monthOptions }
        } footer: {
            if model.skipsShortMonths {
                Text("Monate ohne den \(model.monthDay). werden übersprungen.")
            }
        }
    }

    private var weekdayCircles: some View {
        let symbols = DateText.shortStandaloneWeekdaySymbols(calendar: calendar)
        let names = DateText.fullWeekdaySymbols(calendar: calendar)
        let weekdays = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return HStack(spacing: 6) {
            ForEach(Array(weekdays.enumerated()), id: \.element) { index, weekday in
                let isOn = model.weekdays.contains(weekday)
                Button {
                    model.toggleWeekday(weekday)
                } label: {
                    Text(symbols[index])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Circle().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[index])
                .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var monthOptions: some View {
        optionRow(String(localized: "Am \(model.monthDay). des Monats"), isSelected: !usesWeekdayOfMonth) {
            model.setMonthOption(.dayOfMonth)
        }
        if model.canUseWeekdayOfMonth {
            optionRow(String(localized: "Am \(ordinalText(model.ordinal)) \(weekdayName(model.ordinalWeekday))"), isSelected: usesWeekdayOfMonth) {
                model.setMonthOption(.weekdayOfMonth)
            }
        }
    }

    private var endSection: some View {
        Section("Ende") {
            Picker("Ende", selection: endKind) {
                Text("Nie").tag(RecurrenceEditorModel.EndKind.never)
                Text("Bis Datum").tag(RecurrenceEditorModel.EndKind.date)
                Text("Nach Anzahl").tag(RecurrenceEditorModel.EndKind.count)
            }
            .pickerStyle(.segmented)
            if model.endKind == .date {
                DatePicker("Bis", selection: endDate, in: model.start.startDate(in: calendar)..., displayedComponents: .date)
                    .environment(\.calendar, calendar)
                    .environment(\.timeZone, calendar.timeZone)
            }
            if model.endKind == .count {
                Stepper(String(localized: "Anzahl: \(model.count) Mal"), value: count, in: 1...999)
            }
        }
    }

    private var previewSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.nextOccurrences(5), id: \.self) { day in
                        Text(DateText.shortWeekday(day, calendar: calendar) + " " + DateText.numericDay(day, calendar: calendar))
                            .font(.subheadline.monospacedDigit())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if let suggested = model.suggestedDue {
                Button("Fälligkeit auf \(longDay(suggested)) setzen") {
                    model.updateStart(suggested)
                    onMoveDue(suggested)
                }
            }
        } header: {
            Text("Nächste Termine")
        } footer: {
            consequences
        }
    }

    /// "Gilt ab …", the due-date notes and blocks that end up off the series.
    @ViewBuilder private var consequences: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dueDay == nil {
                Text("Fällig am \(longDay(model.start)). Eine Serie braucht ein Fälligkeitsdatum. Es ist der erste Termin.")
            } else {
                Text("Gilt ab \(longDay(model.start)).")
            }
            if model.suggestedDue != nil {
                Text("Das Fälligkeitsdatum ist kein Termin dieser Regel.")
            }
            if model.isChanged, let recurrence = model.recurrence, let blocks = blocksOffSeries?(recurrence), !blocks.isEmpty {
                Text("Geplante Blöcke an Tagen ohne Termin der Serie bleiben im Kalender: \(BlockListText.text(blocks, calendar: calendar))")
            }
        }
    }

    // MARK: Pieces

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15)))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func optionRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var usesWeekdayOfMonth: Bool { model.monthOption == .weekdayOfMonth && model.canUseWeekdayOfMonth }

    private var intervalText: String {
        let value = model.interval
        return switch model.frequency {
        case .week: String(localized: "Alle \(value) Wochen")
        case .month: String(localized: "Alle \(value) Monate")
        case .year: String(localized: "Alle \(value) Jahre")
        case .day, nil: String(localized: "Alle \(value) Tage")
        }
    }

    /// "3." in German, "3rd" in English.
    private func ordinalText(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)."
    }

    private func weekdayName(_ weekday: Int) -> String {
        var localized = calendar
        localized.locale = .current
        return localized.standaloneWeekdaySymbols[(weekday - 1) % 7]
    }

    private func longDay(_ day: PlanDay) -> String {
        day.startDate(in: calendar).formatted(
            Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
    }

    static func title(of preset: RecurrencePreset) -> String {
        switch preset {
        case .daily: String(localized: "Täglich")
        case .weekdays: String(localized: "Werktags")
        case .weekend: String(localized: "Wochenende")
        case .weekly: String(localized: "Wöchentlich")
        case .biweekly: String(localized: "Alle 2 Wochen")
        case .monthly: String(localized: "Monatlich")
        case .yearly: String(localized: "Jährlich")
        }
    }

    // MARK: Bindings

    private var frequency: Binding<RecurrenceEditorModel.Frequency> {
        Binding(get: { model.frequency ?? .day }, set: { model.setFrequency($0) })
    }

    private var interval: Binding<Int> {
        Binding(get: { model.interval }, set: { model.setInterval($0) })
    }

    private var endKind: Binding<RecurrenceEditorModel.EndKind> {
        Binding(get: { model.endKind }, set: { model.setEndKind($0) })
    }

    private var endDate: Binding<Date> {
        Binding(get: { model.endDate.startDate(in: calendar) },
                set: { model.setEndDate(PlanDay(date: $0, calendar: calendar)) })
    }

    private var count: Binding<Int> {
        Binding(get: { model.count }, set: { model.setCount($0) })
    }
}

/// "Do., 26. Nov., 09:00 bis 10:00" for the blocks named in notices and the save question.
enum BlockListText {
    static func text(_ blocks: [CalendarEvent], calendar: Calendar) -> String {
        blocks.map { block in
            let day = block.start.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated).day().month(.abbreviated))
            let from = DateText.time(block.start, calendar: calendar)
            let to = DateText.time(block.end, calendar: calendar)
            return String(localized: "\(day), \(from) bis \(to)")
        }
        .formatted(.list(type: .and))
    }
}

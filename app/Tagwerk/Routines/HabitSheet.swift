import SwiftUI
import TagwerkCore

/// Create or edit a habit (design §7.2): name, symbol, what fulfils it, days per week, start, pause, delete.
struct HabitSheet: View {
    let model: HabitsModel
    let habit: Habit?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = HabitText.symbols[0]
    @State private var source = HabitSource.manual
    @State private var daysPerWeek = 7
    @State private var start = Date()
    @State private var isPaused = false
    @State private var confirmsDeletion = false
    @State private var isLoaded = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && (habit != nil || model.canAddHabit) }
    private var sources: [HabitSource] { [.manual, .movement, .water, .workout, .steps, .eveningClosed, .journal, .bibleStudy] }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _, value in
                            if value.count > HabitRules.nameLimit { name = String(value.prefix(HabitRules.nameLimit)) }
                        }
                }
                Section("Symbol") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(HabitText.symbols, id: \.self) { candidate in
                            Button { symbol = candidate } label: {
                                Image(systemName: candidate)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(symbol == candidate ? Color.accentColor.opacity(0.2) : Color.clear, in: .rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(HabitText.symbolName(candidate))
                            .accessibilityAddTraits(symbol == candidate ? .isSelected : [])
                        }
                    }
                }
                Section {
                    let taken = model.takenSources(excluding: habit?.id)
                    ForEach(sources, id: \.self) { candidate in
                        Button { source = candidate } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(HabitText.sourceTitle(candidate))
                                    if let subtitle = HabitText.sourceSubtitle(candidate) {
                                        Text(subtitle).font(.footnote).foregroundStyle(.secondaryText)
                                    }
                                }
                                Spacer()
                                if source == candidate { Image(systemName: "checkmark") }
                            }
                        }
                        .tint(.primary)
                        .disabled(taken.contains(candidate))
                    }
                } header: {
                    Text("Erfüllt durch")
                } footer: {
                    Text(HabitText.sourceFooter)
                }
                Section {
                    ValueStepper("Tage pro Woche", value: $daysPerWeek, in: 1...7) { "\($0)" }
                    DatePicker("Zählt ab", selection: $start, in: startRange, displayedComponents: .date)
                } footer: {
                    Text("7 bedeutet täglich. Quote: erfüllte Tage ÷ Zieltage, höchstens 100 %. Serie bei weniger als 7: Wochen in Folge mit erreichtem Ziel.")
                }
                if habit != nil {
                    Section {
                        Toggle("Pausieren", isOn: $isPaused)
                        Button("Gewohnheit löschen", role: .destructive) { confirmsDeletion = true }
                    } footer: {
                        Text("Pausierte Tage zählen weder in die Quote noch brechen sie eine Serie.")
                    }
                } else if !model.canAddHabit {
                    Section {} footer: {
                        Text("Höchstens \(HabitRules.maximumActive) aktive Gewohnheiten. Pausiere oder lösche eine, um eine neue anzulegen.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(habit == nil ? "Neue Gewohnheit" : "Gewohnheit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig", action: save).disabled(!canSave) }
            }
            .confirmationDialog("Gewohnheit löschen?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let habit { model.delete(habit.id) }
                    dismiss()
                }
            } message: {
                Text("Die Gewohnheit und ihre Häkchen werden gelöscht.")
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    /// The first day the habit can count from: at most the window back, at most today.
    private var startRange: ClosedRange<Date> {
        let window = HabitRules.window(today: model.today, calendar: model.calendar)
        return window.lowerBound.startDate(in: model.calendar)...model.today.startDate(in: model.calendar)
    }

    private func load() {
        guard !isLoaded else { return }
        isLoaded = true
        let calendar = model.calendar
        guard let habit else {
            start = model.today.startDate(in: calendar)
            return
        }
        name = habit.name
        symbol = habit.symbol
        source = habit.source
        daysPerWeek = habit.daysPerWeek
        start = max(habit.start.startDate(in: calendar), startRange.lowerBound)
        isPaused = habit.pausedSince != nil
    }

    private func save() {
        let day = PlanDay(date: start, calendar: model.calendar)
        var value = habit ?? Habit(name: trimmedName, symbol: symbol, order: model.habits.count, start: day)
        value.name = trimmedName
        value.symbol = symbol
        value.source = source
        value.daysPerWeek = daysPerWeek
        value.start = day
        model.save(value)
        if habit != nil, isPaused != (habit?.pausedSince != nil) { model.setPaused(value.id, isPaused) }
        dismiss()
    }
}

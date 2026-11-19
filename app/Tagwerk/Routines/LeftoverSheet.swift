import SwiftUI
import TagwerkCore

/// "Unerledigtes verschieben" (#163): what is left from today, moved with one tap. Three ways: everything to the next
/// working day, each task into the next free block, or one by one. A bulk action closes the sheet and reports what
/// happened to `onFinished`; "Planen" then shows its "Rückgängig" capsule, the evening wrap-up its own result line.
struct LeftoverSheet: View {
    /// What a bulk action did, with what is needed to take it back.
    struct Report: Equatable {
        var moved: Int
        var late: Int
        var unplaced: Int
        var moves: [PlanningModel.DayMove]
    }

    let planning: PlanningModel
    let taskList: TaskListModel
    let onFinished: (Report) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isDeciding = false
    @State private var isWorking = false
    @State private var pickingDateFor: DateTarget?

    /// The task a date is picked for.
    struct DateTarget: Identifiable {
        let id = UUID()
        let taskID: TaskID
    }

    /// The tasks left from today; a snapshot of the model, which refreshes after every change.
    private var tasks: [TaskItem] { planning.leftFromToday }

    var body: some View {
        NavigationStack {
            List {
                if isDeciding {
                    individualSection
                } else {
                    optionsSection
                }
            }
            .navigationTitle("Unerledigtes verschieben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isDeciding {
                        Button("Zurück") { isDeciding = false }
                    } else {
                        Button("Schließen") { dismiss() }
                    }
                }
            }
            // On the list, not on a row: a row would present the sheet once per row.
            .sheet(item: $pickingDateFor) { target in
                BulkDateSheet(title: "Datum wählen", calendar: planning.calendar) { date in
                    let day = PlanDay(date: date, calendar: planning.calendar)
                    Task { await move(target.taskID, to: day) }
                }
            }
            .disabled(isWorking)
            .onChange(of: tasks.isEmpty) { _, isEmpty in if isEmpty && isDeciding { dismiss() } }
        }
    }

    // MARK: Options

    private var optionsSection: some View {
        let next = planning.nextPlanDay
        return Section {
            Button { Task { await moveAll() } } label: {
                optionLabel(title: next.map { LeftoverSheetText.moveAllTitle(day: $0, today: planning.today, calendar: planning.calendar) }
                                ?? String(localized: "Alles auf den nächsten Arbeitstag"),
                            subtitle: nil, symbol: "arrow.right.circle")
            }
            .disabled(next == nil)
            Button { Task { await placeAll() } } label: {
                optionLabel(title: String(localized: "In den nächsten freien Block"),
                            subtitle: LeftoverSheetText.freeBlockSubtitle(day: next, today: planning.today, calendar: planning.calendar),
                            symbol: "calendar.badge.clock")
            }
            Button { isDeciding = true } label: {
                optionLabel(title: String(localized: "Einzeln entscheiden"), subtitle: nil, symbol: "list.bullet")
            }
        } header: {
            Text(LeftoverSheetText.countLabel(tasks.count))
        } footer: {
            if next == nil {
                Text("In den nächsten fünf Tagen ist kein Arbeitstag. Wähle ein Datum unter „Einzeln entscheiden“.")
            }
        }
    }

    private func optionLabel(title: String, subtitle: String?, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: One by one

    private var individualSection: some View {
        Section {
            ForEach(tasks) { task in
                HStack {
                    Text(task.title).lineLimit(2)
                    Spacer()
                    Menu {
                        if let next = planning.nextPlanDay {
                            Button(LeftoverSheetText.singleMoveTitle(day: next, today: planning.today, calendar: planning.calendar),
                                   systemImage: "arrow.right.circle") { Task { await move(task.id, to: next) } }
                        }
                        Button("Nächster freier Block", systemImage: "calendar.badge.clock") { Task { await place(task.id) } }
                        Button("Datum …", systemImage: "calendar") { pickingDateFor = DateTarget(taskID: task.id) }
                        Button("Erledigt", systemImage: "checkmark.circle") { Task { await taskList.complete(task.id); await planning.reload() } }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                    .accessibilityLabel("Verschieben")
                }
            }
        } header: {
            Text(LeftoverSheetText.countLabel(tasks.count))
        }
    }

    // MARK: Actions

    private func moveAll() async {
        guard let next = planning.nextPlanDay else { return }
        let ids = tasks.map(\.id)
        isWorking = true
        await planning.moveTasks(ids, to: next)
        finish(Report(moved: planning.lastMoveGroup?.count ?? 0, late: 0, unplaced: 0, moves: planning.lastMoveGroup ?? []))
    }

    private func placeAll() async {
        let ids = tasks.map(\.id)
        isWorking = true
        let outcome = await planning.placeInFreeBlocks(ids)
        finish(Report(moved: outcome.placed, late: outcome.late, unplaced: outcome.unplaced, moves: planning.lastMoveGroup ?? []))
    }

    /// One task from the list: the list shrinks, the sheet stays; the last one closes it.
    private func move(_ id: TaskID, to day: PlanDay) async {
        isWorking = true
        await planning.moveTask(id, to: day)
        isWorking = false
    }

    private func place(_ id: TaskID) async {
        isWorking = true
        _ = await planning.placeInFreeBlocks([id])
        isWorking = false
    }

    private func finish(_ report: Report) {
        isWorking = false
        onFinished(report)
        dismiss()
    }
}

/// Texts of the sheet and of its entry rows as static functions, so they can be tested.
enum LeftoverSheetText {
    /// "Alles auf morgen" / "Alles auf Montag".
    static func moveAllTitle(day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        String(localized: "Alles auf \(dayName(day, today: today, calendar: calendar))")
    }

    /// "Morgen" / "Montag" for the menu of one task.
    static func singleMoveTitle(day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        DayPanelText.relation(of: day, today: today, calendar: calendar) == .tomorrow
            ? String(localized: "Morgen") : dayName(day, today: today, calendar: calendar)
    }

    static func freeBlockSubtitle(day: PlanDay?, today: PlanDay, calendar: Calendar) -> String? {
        guard let day else { return nil }
        return String(localized: "Ab \(dayName(day, today: today, calendar: calendar)), vor der Fälligkeit, ohne Überschneidung")
    }

    /// "1 Aufgabe" / "3 Aufgaben".
    static func countLabel(_ count: Int) -> String {
        count == 1 ? String(localized: "1 Aufgabe") : String(localized: "\(count) Aufgaben")
    }

    /// "Unerledigtes verschieben · 3 Aufgaben", the row in the capacity card and in the wrap-up.
    static func lineTitle(count: Int) -> String {
        String(localized: "Unerledigtes verschieben · \(countLabel(count))")
    }

    /// "3 verschoben · 1 nach Fälligkeit · 1 ohne freien Platz".
    static func outcome(moved: Int, late: Int, unplaced: Int) -> String {
        var parts: [String] = []
        if moved > 0 || unplaced == 0 { parts.append(String(localized: "\(moved) verschoben")) }
        if late > 0 { parts.append(String(localized: "\(late) nach Fälligkeit")) }
        if unplaced > 0 { parts.append(String(localized: "\(unplaced) ohne freien Platz")) }
        return parts.joined(separator: " · ")
    }

    /// "morgen" for the next day, else the weekday ("Montag").
    private static func dayName(_ day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        if DayPanelText.relation(of: day, today: today, calendar: calendar) == .tomorrow { return String(localized: "morgen") }
        let style = Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone)
        return day.startDate(in: calendar).formatted(style.weekday(.wide))
    }
}

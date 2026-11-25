import SwiftUI
import TagwerkCore

/// The evening wrap-up (mockup GS·B, design §7.5): the day in numbers, the checklist, "Morgen planen". Everything is
/// optional; "Abschließen" marks the day as closed, swiping the sheet away keeps what was checked.
struct EveningSheet: View {
    let model: RoutinesModel
    let day: PlanDay
    @Environment(AppEnvironment.self) private var environment
    @State private var review: RoutinesModel.DayReview?
    @State private var note: NoteFieldModel
    @State private var journalSheet: JournalSheetTarget?
    @State private var isStartingBibleStudy = false
    @State private var bibleSheet: JournalSheetTarget?
    @State private var isMovingLeftovers = false
    /// The task of the result list whose date is being chosen.
    @State private var pickingDateFor: TaskID?
    /// What the last bulk action did, with what is needed to take it back; the capsule of "Planen" is behind this sheet.
    @State private var leftoverReport: LeftoverSheet.Report?

    init(model: RoutinesModel, day: PlanDay, notes: NoteStore, isSignedIn: @escaping () -> Bool,
         isConcealed: @escaping @MainActor (NoteRecord) -> Bool = { _ in false }) {
        self.model = model
        self.day = day
        // The wrap-up note belongs to the day the sheet was opened for (rule 10).
        _note = State(initialValue: NoteFieldModel(store: notes, kind: .evening, day: day, isSignedIn: isSignedIn,
                                                   isConcealed: isConcealed))
    }

    var body: some View {
        let items = model.checklist()
        let value = model.value(day)
        let reminding = model.settings.eveningRemindersEnabled ? Set(RoutineSchedule.reminderItems(items).map(\.id)) : []
        NavigationStack {
            Form {
                Section {
                    if let review {
                        LabeledContent("Aufgaben erledigt", value: String(localized: "\(review.tasksDone) von \(review.tasksTotal)"))
                        if let habits = review.habits {
                            LabeledContent("Gewohnheiten", value: String(localized: "\(habits.done) von \(habits.total)"))
                        }
                        if let focus = review.focus {
                            LabeledContent("★ Fokus", value: String(localized: "\(focus.done) von \(focus.total)"))
                        }
                    } else {
                        ProgressView()
                    }
                } header: {
                    Text("Heute")
                        .foregroundStyle(.secondaryText)
                } footer: {
                    Text(RoutinesModel.reviewFooter(review?.gitHub ?? .notConnected, isToday: day == model.today))
                        .foregroundStyle(.secondaryText)
                }

                leftoverSection

                Section {
                    if items.isEmpty {
                        Text("Punkte in den Einstellungen anlegen").foregroundStyle(.secondaryText)
                    }
                    ForEach(items) { item in
                        let isChecked = value.checkedItemIDs.contains(item.id)
                        let reminds = reminding.contains(item.id)
                        Button { model.toggleItem(item.id, on: day) } label: {
                            ChecklistRow(title: item.title, isChecked: isChecked, reminds: reminds,
                                         clock: ChecklistText.clock(item, bedtime: model.settings.bedtimeMinutes, calendar: model.calendar),
                                         detail: ChecklistText.sheetDetail(item, isChecked: isChecked, reminds: reminds))
                        }
                        .tint(.primary)
                        .accessibilityValue(isChecked ? String(localized: "erledigt") : String(localized: "offen"))
                    }
                } header: {
                    Text("Abend-Checkliste · Schlafzeit \(DateText.time(minutes: model.settings.bedtimeMinutes, calendar: model.calendar))")
                        .foregroundStyle(.secondaryText)
                } footer: {
                    if !items.isEmpty {
                        Text("\(Image(systemName: "bell")) erinnert zur Uhrzeit. Die Zeiten folgen der Schlafzeit. Höchstens vier Punkte erinnern.").foregroundStyle(.secondaryText)
                    }
                }

                NoteField(model: note)

                TimeWithGodSection(day: day, showsJournal: true,
                                   showsBibleStudy: model.settings.bibleStudyOffer.isOffered(in: .routineEvening),
                                   onJournal: { openJournal() }, onBibleStudy: { openBibleStudy(environment: environment) })

                // Sundays: the weekly planning is one tap away (it contains the reflection).
                if UITestMode.weekday(of: day, calendar: model.calendar) == 1 {
                    Section {
                        Button {
                            model.closeSheet()
                            // A sheet that opens in the same update in which another one closes is dropped.
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                model.openWeek()
                            }
                        } label: {
                            HStack {
                                Label("Wochenplanung starten", systemImage: "calendar.badge.checkmark")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                }

                if let next = model.planning.nextPlanDay {
                    Section {
                        Button {
                            environment.planning.scope = .day
                            environment.planning.jump(to: next)
                            environment.requestedTab = 0
                            model.closeSheet()
                        } label: {
                            HStack {
                                Label(DayPanelText.eveningTitle(day: next, today: model.planning.today, calendar: model.calendar),
                                      systemImage: "moon.stars")
                                Spacer()
                                Text(DateText.numericDay(next, calendar: model.calendar)).foregroundStyle(.secondaryText)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Tagesabschluss")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Abschließen") { note.flush(); model.finishEvening(day) } } }
            .task {
                // The local numbers show at once; the closed GitHub issues follow when GitHub answered.
                let local = await model.dayReview(day)
                review = local
                review = await model.addingClosedIssues(to: local, day: day)
            }
            .sheet(item: $journalSheet) { target in NoteEditorSheet(noteID: target.id) }
            .sheet(isPresented: $isStartingBibleStudy) {
                BibleStudyStartSheet(store: environment.notes) { noteID in bibleSheet = JournalSheetTarget(id: noteID) }
            }
            .sheet(item: $bibleSheet) { target in NoteEditorSheet(noteID: target.id) }
            .sheet(item: Binding(get: { pickingDateFor.map(DateRequest.init) }, set: { pickingDateFor = $0?.id })) { request in
                BulkDateSheet(title: "Datum wählen", calendar: model.calendar) { date in
                    resolve(request.id) { await model.planning.moveTask(request.id, to: PlanDay(date: date, calendar: model.calendar)) }
                }
            }
            .sheet(isPresented: $isMovingLeftovers) {
                LeftoverSheet(planning: model.planning, taskList: model.taskList) { report in leftoverReport = report }
            }
        }
    }

    /// "Unerledigt von heute": the way to move what is left, and after a bulk action its result with "Rückgängig". Only for
    /// the wrap-up of today (rule 10: after midnight it belongs to yesterday and offers nothing).
    @ViewBuilder
    private var leftoverSection: some View {
        if model.offersLeftover(for: day) {
            Section {
                LeftoverLine(count: model.planning.leftFromToday.count) { isMovingLeftovers = true }
            } header: {
                Text("Unerledigt von heute")
                    .foregroundStyle(.secondaryText)
            }
        }
        if let report = leftoverReport {
            Section {
                HStack {
                    // The tasks without a place are listed below with their reason, so the count is not repeated here (RO11b).
                    Label(LeftoverSheetText.outcome(moved: report.moved, late: report.late,
                                                    unplaced: report.unplacedTasks.isEmpty ? report.unplaced : 0), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                    Spacer()
                    if !report.moves.isEmpty {
                        Button("Rückgängig") { undoLeftover(report) }.buttonStyle(.borderless)
                    }
                }
                ForEach(report.unplacedTasks) { task in unplacedRow(task) }
            }
        }
    }

    /// A task that found no free place: its reason and the ways out (RO11b). "Erledigt" only for sources that can be checked off
    /// without a network (a GitHub issue needs one).
    private func unplacedRow(_ task: LeftoverSheet.Report.Unplaced) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).lineLimit(2)
                Text(LeftoverSheetText.unplacedReason(due: task.due, calendar: model.calendar)).font(.caption).foregroundStyle(.secondaryText)
            }
            Spacer()
            Menu {
                Button("Datum …", systemImage: "calendar") { pickingDateFor = task.id }
                if let next = model.planning.nextPlanDay {
                    Button("Trotzdem auf morgen", systemImage: "arrow.right.circle") { resolve(task.id) { await model.planning.moveTask(task.id, to: next) } }
                }
                Button("Erledigt", systemImage: "checkmark.circle") {
                    resolve(task.id) { await model.taskList.complete(task.id); await model.planning.reload() }
                }
                .disabled(task.id.source == .github)
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Verschieben")
        }
    }

    /// Runs the action for a task of the result list and takes the task out of the list.
    private func resolve(_ id: TaskID, _ action: @escaping () async -> Void) {
        Task {
            await action()
            leftoverReport?.unplacedTasks.removeAll { $0.id == id }
        }
    }

    private func undoLeftover(_ report: LeftoverSheet.Report) {
        leftoverReport = nil
        Task {
            for move in report.moves.reversed() { await model.planning.undo(move) }
            // The same group may still be offered by the capsule of "Planen".
            if model.planning.lastMoveGroup == report.moves { model.planning.clearMoveGroupUndo() }
        }
    }

    /// "Bible Study starten", or the open session of the latest study when there is one.
    private func openBibleStudy(environment: AppEnvironment) {
        if let last = environment.notes.lastSession, last.completedAt == nil {
            bibleSheet = JournalSheetTarget(id: last.noteID)
        } else {
            isStartingBibleStudy = true
        }
    }

    /// The journal entry of the day this wrap-up belongs to, created from the template when there is none.
    private func openJournal() {
        let entry = environment.notes.openJournalEntry(dayKey: NoteDayKey.string(day))
        journalSheet = JournalSheetTarget(id: entry.id)
    }
}

/// The task a date is picked for in the result list.
private struct DateRequest: Identifiable {
    let id: TaskID
}

/// The journal entry shown in a sheet over the wrap-up.
struct JournalSheetTarget: Identifiable {
    let id: UUID
}

/// The section "Routinen" of "Erfassen": one row per routine for the shown day; past days stay readable and fillable.
struct RoutinesSection: View {
    let model: RoutinesModel
    let day: PlanDay

    var body: some View {
        Section {
            Button { model.openStart(day) } label: {
                HStack {
                    Label("Tagesstart", systemImage: "sun.max")
                    Spacer()
                    Text(model.captureStartDetail(day)).font(.subheadline).foregroundStyle(.secondaryText).multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
            Button { model.openEvening(day) } label: {
                HStack {
                    Label("Tagesabschluss", systemImage: "bed.double")
                    Spacer()
                    Text(model.captureEveningDetail(day)).font(.subheadline).foregroundStyle(.secondaryText).multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        } header: {
            Text("Routinen")
                .foregroundStyle(.secondaryText)
        }
    }
}

/// One point of the evening checklist: check mark, name, and at the end the time it reminds with a bell (RO7b). A checked point
/// that would remind says that it does not remind any more tonight. With the largest text sizes the time moves below the name.
private struct ChecklistRow: View {
    let title: String
    let isChecked: Bool
    let reminds: Bool
    let clock: String?
    let detail: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isChecked ? Color.green : Color.secondaryText)
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondaryText) }
                }
                if dynamicTypeSize.isAccessibilitySize { EmptyView() } else { Spacer() }
                if let clock { ChecklistClock(clock: clock, reminds: reminds) }
            }
        }
    }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
    }
}

/// "🔔 22:00": the time of a point, with the bell when it reminds. The bell is named for VoiceOver.
struct ChecklistClock: View {
    let clock: String
    let reminds: Bool

    var body: some View {
        HStack(spacing: 4) {
            if reminds { Image(systemName: "bell").accessibilityLabel("erinnert") }
            Text(clock).monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(Color.secondaryText)
    }
}

/// Texts of the checklist rows as static functions, so they can be tested.
enum ChecklistText {
    /// "abgehakt, erinnert heute nicht mehr" for a checked point that would remind; otherwise `nil`.
    static func sheetDetail(_ item: ChecklistItem, isChecked: Bool, reminds: Bool) -> String? {
        item.offsetMinutes != nil && isChecked && reminds ? String(localized: "abgehakt, erinnert heute nicht mehr") : nil
    }

    /// "22:00": the time the point is anchored to; `nil` without an offset.
    static func clock(_ item: ChecklistItem, bedtime: Int, calendar: Calendar) -> String? {
        item.offsetMinutes.map {
            DateText.time(minutes: RoutineSchedule.anchorMinutes(bedtimeMinutes: bedtime, offsetMinutes: $0), calendar: calendar)
        }
    }

    /// "60 min vorher · 22:00"; `nil` without an offset.
    static func settingsDetail(_ item: ChecklistItem, bedtime: Int, calendar: Calendar) -> String? {
        guard let offset = item.offsetMinutes, let clock = clock(item, bedtime: bedtime, calendar: calendar) else { return nil }
        return String(localized: "\(offset) min vorher · \(clock)")
    }
}

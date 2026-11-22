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
    /// What the last bulk action did, with what is needed to take it back; the capsule of "Planen" is behind this sheet.
    @State private var leftoverReport: LeftoverSheet.Report?

    init(model: RoutinesModel, day: PlanDay, notes: NoteStore, isSignedIn: @escaping () -> Bool) {
        self.model = model
        self.day = day
        // The wrap-up note belongs to the day the sheet was opened for (rule 10).
        _note = State(initialValue: NoteFieldModel(store: notes, kind: .evening, day: day, isSignedIn: isSignedIn))
    }

    var body: some View {
        let items = model.checklist()
        let value = model.value(day)
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
                } footer: {
                    Text(RoutinesModel.reviewFooter(review?.gitHub ?? .notConnected, isToday: day == model.today))
                }

                leftoverSection

                Section {
                    if items.isEmpty {
                        Text("Punkte in den Einstellungen anlegen").foregroundStyle(.secondaryText)
                    }
                    ForEach(items) { item in
                        Button { model.toggleItem(item.id, on: day) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: value.checkedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(value.checkedItemIDs.contains(item.id) ? Color.green : Color.secondaryText)
                                Text(item.title)
                                Spacer()
                                if let offset = item.offsetMinutes {
                                    Text(DateText.time(minutes: RoutineSchedule.anchorMinutes(
                                        bedtimeMinutes: model.settings.bedtimeMinutes, offsetMinutes: offset), calendar: model.calendar))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondaryText)
                                }
                            }
                        }
                        .tint(.primary)
                        .accessibilityValue(value.checkedItemIDs.contains(item.id) ? String(localized: "erledigt") : String(localized: "offen"))
                    }
                } header: {
                    Text("Abend-Checkliste · Schlafzeit \(DateText.time(minutes: model.settings.bedtimeMinutes, calendar: model.calendar))")
                }

                NoteField(model: note)

                Section {
                    Button { openJournal() } label: {
                        HStack {
                            Label("Tagebuch schreiben", systemImage: "book.closed")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                } footer: {
                    Text("Der Eintrag bleibt auf deinem iPhone und geht nie an ChatGPT.")
                }

                // Always offered, with or without a habit that Bible Study fulfils: one tap to the start of a session.
                Section {
                    Button { isStartingBibleStudy = true } label: {
                        HStack {
                            Label("Bible Study starten", systemImage: "book.pages")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }

                // Sundays: the weekly planning is one tap away (it contains the reflection).
                if day.weekday(in: model.calendar) == 1 {
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
            }
        }
        if let report = leftoverReport {
            Section {
                HStack {
                    Text(LeftoverSheetText.outcome(moved: report.moved, late: report.late, unplaced: report.unplaced))
                    Spacer()
                    if !report.moves.isEmpty {
                        Button("Rückgängig") { undoLeftover(report) }.buttonStyle(.borderless)
                    }
                }
            }
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

    /// The journal entry of the day this wrap-up belongs to, created from the template when there is none.
    private func openJournal() {
        let entry = environment.notes.openJournalEntry(dayKey: NoteDayKey.string(day))
        journalSheet = JournalSheetTarget(id: entry.id)
    }
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
        Section("Routinen") {
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
        }
    }
}

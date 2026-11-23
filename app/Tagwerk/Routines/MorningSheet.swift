import SwiftUI
import TagwerkCore

/// The morning start (design §7.4): a gentle start, from the most fleeting to the most elaborate thing: the dream log, up to
/// three things to be grateful for, the brain dump (RO1b). The last row points to the daily focus, which is chosen in "Planen"
/// (RO3b). Everything is optional. "Abschließen" saves and marks the start as done; swiping the sheet away saves the input
/// without completing.
struct MorningSheet: View {
    let model: RoutinesModel
    let day: PlanDay
    @Environment(AppEnvironment.self) private var environment

    init(model: RoutinesModel, day: PlanDay, notes: NoteStore, isSignedIn: @escaping () -> Bool,
         isConcealed: @escaping @MainActor (NoteRecord) -> Bool = { _ in false }) {
        self.model = model
        self.day = day
        _note = State(initialValue: NoteFieldModel(store: notes, kind: .morning, day: day, isSignedIn: isSignedIn,
                                                   isConcealed: isConcealed))
        // The dream log is never sent anywhere, so it gets no sign-in check to begin with.
        _dream = State(initialValue: NoteFieldModel(store: notes, kind: .dream, day: day, isConcealed: isConcealed))
    }
    @State private var gratitude: [String] = ["", "", ""]
    @State private var isLoaded = false
    @State private var note: NoteFieldModel
    @State private var dream: NoteFieldModel
    @State private var isStartingBibleStudy = false
    @State private var bibleSheet: JournalSheetTarget?
    @State private var isEnteringWeight = false
    @State private var weight = WeightOverview()

    /// The first field, then one more each time the previous one is filled (at most three).
    private var visibleFields: Int {
        let filled = gratitude.prefix(RoutineDayValue.maximumGratitude).lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return min(RoutineDayValue.maximumGratitude, (filled ?? -1) + 2)
    }

    /// "In „Planen“ setzen · 1 von 3 gewählt": the row below the fields sends the user to the place where the focus is chosen.
    static func focusHint(chosen: Int, maximum: Int) -> String {
        String(localized: "In „Planen“ setzen · \(chosen) von \(maximum) gewählt")
    }

    var body: some View {
        NavigationStack {
            Form {
                NoteField(model: dream)
                Section {
                    ForEach(0..<visibleFields, id: \.self) { index in
                        HStack(spacing: 10) {
                            Text(verbatim: "\(index + 1)").font(.body.monospacedDigit()).foregroundStyle(.secondaryText)
                                .accessibilityHidden(true)
                            TextField("Dankbar für", text: $gratitude[index])
                        }
                    }
                } header: {
                    FolderSectionHeader(title: "Dankbar für", symbol: NotesFoldersView.symbol(for: .morningRoutine), role: .morningRoutine)
                }
                NoteField(model: note)
                if model.settings.bibleStudyOffer.isOffered(in: .routineStart) {
                    TimeWithGodSection(day: day, showsJournal: false, showsBibleStudy: true, onJournal: {}, onBibleStudy: { openBibleStudy() })
                }
                if Self.showsWeightRow(enabled: model.settings.morningWeightEnabled, day: day, today: model.today) { weightSection }
                if day == model.today { focusSection }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Tagesstart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Abschließen") {
                        note.flush()
                        dream.flush()
                        model.setGratitude(gratitude, on: day)
                        model.finishStart(day)
                    }
                }
            }
            .task {
                if !isLoaded {
                    isLoaded = true
                    let stored = model.value(day).gratitude
                    gratitude = stored + Array(repeating: "", count: max(0, RoutineDayValue.maximumGratitude - stored.count))
                }
            }
            // Swiping the sheet away: what was typed stays, the start is not marked as done.
            .onDisappear { if isLoaded { model.setGratitude(gratitude, on: day) } }
            .sheet(isPresented: $isStartingBibleStudy) {
                BibleStudyStartSheet(store: environment.notes) { noteID in bibleSheet = JournalSheetTarget(id: noteID) }
            }
            .sheet(item: $bibleSheet) { target in NoteEditorSheet(noteID: target.id) }
            // At the level of the stack, like the other sheets: a sheet on a row inside a Form does not present reliably.
            .sheet(isPresented: $isEnteringWeight) {
                WeightSheet(model: environment.capture, existing: nil) { Task { await loadWeight() } }
            }
            .task { await loadWeight() }
        }
    }

    /// The weight row appears on today's start when it is switched on (settings › Routinen); it is a reminder without a notification
    /// (decision KG5a).
    static func showsWeightRow(enabled: Bool, day: PlanDay, today: PlanDay) -> Bool { enabled && day == today }

    private func loadWeight() async {
        let today = model.today
        let end = today.adding(days: 1, calendar: .tagwerk).startDate(in: .tagwerk)
        let days = await environment.capture.weights.dayValues(in: DateInterval(start: end.addingTimeInterval(-45 * 86_400), end: end))
        weight = WeightOverview.make(days, today: today, calendar: .tagwerk)
    }

    /// "Körper · Gewicht": today's value (a dash before the first weighing), with yesterday's value and the 7-day mean below.
    private var weightSection: some View {
        Section {
            Button { isEnteringWeight = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gewicht")
                        if let caption = WeightFormat.morningCaption(yesterday: weight.yesterday, mean: weight.mean) {
                            Text(caption).font(.subheadline).foregroundStyle(.secondaryText)
                        }
                    }
                    Spacer()
                    Text(weight.today.map { WeightFormat.kilograms($0) } ?? "–").monospacedDigit().foregroundStyle(.secondaryText)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
            .accessibilityIdentifier(AccessibilityID.Capture.morningWeight)
        } header: {
            Text("Körper")
        }
    }

    /// "Bible Study starten", or the open session of the latest study when there is one.
    private func openBibleStudy() {
        note.flush()
        if let last = environment.notes.lastSession, last.completedAt == nil {
            bibleSheet = JournalSheetTarget(id: last.noteID)
        } else {
            isStartingBibleStudy = true
        }
    }

    /// "★ Fokus für heute": closes the sheet and shows "Planen" on today. Neither marks the start as done; what was typed is saved.
    private var focusSection: some View {
        Section {
            Button { openPlan() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Fokus für heute", systemImage: "star")
                        Text(Self.focusHint(chosen: model.focusMarks(day).count, maximum: FocusRules.maximumMarks))
                            .font(.subheadline).foregroundStyle(.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        }
    }

    private func openPlan() {
        note.flush()
        dream.flush()
        model.setGratitude(gratitude, on: day)
        environment.planning.scope = .day
        environment.planning.jump(to: model.today)
        environment.requestedTab = 0
        model.closeSheet()
    }
}

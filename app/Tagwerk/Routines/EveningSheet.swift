import SwiftUI
import TagwerkCore

/// The evening wrap-up (mockup GS·B, design §7.5): the day in numbers, the checklist, "Morgen planen". Everything is
/// optional; "Fertig" marks the day as closed, swiping the sheet away keeps what was checked.
struct EveningSheet: View {
    let model: RoutinesModel
    let day: PlanDay
    @Environment(AppEnvironment.self) private var environment
    @State private var review: RoutinesModel.DayReview?
    @State private var note: NoteFieldModel

    init(model: RoutinesModel, day: PlanDay, notes: NoteStore) {
        self.model = model
        self.day = day
        // The wrap-up note belongs to the day the sheet was opened for (rule 10).
        _note = State(initialValue: NoteFieldModel(store: notes, kind: .evening, day: day))
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
                    Text("Erledigt: Erinnerungen und lokale Aufgaben, ohne GitHub.")
                }

                Section {
                    if items.isEmpty {
                        Text("Punkte in den Einstellungen anlegen").foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        Button { model.toggleItem(item.id, on: day) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: value.checkedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(value.checkedItemIDs.contains(item.id) ? Color.green : Color.secondary)
                                Text(item.title)
                                Spacer()
                                if let offset = item.offsetMinutes {
                                    Text(DateText.time(minutes: RoutineSchedule.anchorMinutes(
                                        bedtimeMinutes: model.settings.bedtimeMinutes, offsetMinutes: offset), calendar: model.calendar))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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

                if let next = model.planning.nextPlanDay {
                    Section {
                        Button {
                            environment.planning.anchor = next
                            environment.planning.scope = .day
                            environment.requestedTab = 0
                            model.closeSheet()
                        } label: {
                            HStack {
                                Label(DayPanelText.eveningTitle(day: next, today: model.planning.today, calendar: model.calendar),
                                      systemImage: "moon.stars")
                                Spacer()
                                Text(DateText.numericDay(next, calendar: model.calendar)).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle("Tagesabschluss")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { note.flush(); model.finishEvening(day) } } }
            .task { review = await model.dayReview(day) }
        }
    }
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
                    Text(model.captureStartDetail(day)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
            Button { model.openEvening(day) } label: {
                HStack {
                    Label("Tagesabschluss", systemImage: "bed.double")
                    Spacer()
                    Text(model.captureEveningDetail(day)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        }
    }
}

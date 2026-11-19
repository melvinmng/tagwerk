import SwiftUI
import TagwerkCore

/// All habits, paused ones too (design §7.1 "Bearbeiten"): sorting, creating, opening the sheet.
struct HabitListView: View {
    let model: HabitsModel
    @State private var sheet: Habit?
    @State private var creating = false
    @State private var adoptingSuggestions = false

    var body: some View {
        List {
            Section {
                ForEach(model.habits) { habit in
                    Button { sheet = habit } label: {
                        HStack(spacing: 12) {
                            Image(systemName: habit.symbol).frame(width: 28).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.name)
                                Text(caption(habit)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }
                .onMove { source, destination in
                    var ids = model.habits.map(\.id)
                    ids.move(fromOffsets: source, toOffset: destination)
                    model.reorder(ids)
                }
                Button { creating = true } label: { Label("Gewohnheit anlegen", systemImage: "plus.circle") }
                    .disabled(!model.canAddHabit)
                if !model.missingSuggestions.isEmpty {
                    Button { adoptingSuggestions = true } label: { Label("Vorschlag übernehmen", systemImage: "sparkles") }
                        .disabled(!model.canAddHabit)
                }
            } footer: {
                if !model.canAddHabit {
                    Text("Höchstens \(HabitRules.maximumActive) aktive Gewohnheiten. Pausiere oder lösche eine, um eine neue anzulegen.")
                }
            }
        }
        .navigationTitle("Gewohnheiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(item: $sheet) { habit in HabitSheet(model: model, habit: habit) }
        .sheet(isPresented: $creating) { HabitSheet(model: model, habit: nil) }
        .sheet(isPresented: $adoptingSuggestions) { HabitSuggestionSheet(model: model) }
    }

    /// "Täglich · Wasserziel erreicht · pausiert".
    private func caption(_ habit: Habit) -> String {
        var parts = [HabitText.rhythm(habit.daysPerWeek)]
        if habit.source != .manual { parts.append(HabitText.sourceTitle(habit.source)) }
        if habit.pausedSince != nil { parts.append(String(localized: "pausiert")) }
        return parts.joined(separator: " · ")
    }
}

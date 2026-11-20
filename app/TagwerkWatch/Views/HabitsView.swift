import SwiftUI
import TagwerkCore

/// The habits of today. Habits that their source fulfils by itself are shown but cannot be tapped.
struct HabitsView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let snapshot = store.display()
        List {
            UndoRow()
            if let snapshot, !snapshot.habits.isEmpty {
                ForEach(snapshot.habits) { habit in
                    HabitRow(habit: habit)
                }
            } else if snapshot != nil {
                Text("Keine Gewohnheiten heute").foregroundStyle(.secondary)
            }
            SyncHint().listRowBackground(Color.clear)
        }
        .navigationTitle("Gewohnheiten")
    }
}

private struct HabitRow: View {
    @Environment(WatchStore.self) private var store
    let habit: WatchHabit

    var body: some View {
        Button {
            store.setHabit(habit)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: habit.symbol).frame(width: 24).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name).lineLimit(2)
                    if habit.isAutomatic { Text("automatisch").font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: habit.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(habit.done ? Color.green : Color.secondary)
            }
        }
        .disabled(habit.isAutomatic)
        .accessibilityValue(habit.done ? Text("erledigt") : Text("offen"))
    }
}

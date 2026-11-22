import SwiftUI
import TagwerkCore

/// The page of a day in "Tagesstart" that only has gratitude and no note (design NO14). It is a display of the routine
/// record: no text field, nothing is created here. The gratitude is changed in the morning routine of that day.
struct MorningDayView: View {
    @Environment(AppEnvironment.self) private var environment
    let day: PlanDay

    var body: some View {
        let gratitude = environment.routines.value(day).gratitude
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if gratitude.isEmpty {
                    Text("Für diesen Tag ist keine Dankbarkeit eingetragen.").foregroundStyle(.secondaryText)
                } else {
                    GratitudeCard(entries: gratitude) { environment.routines.openStart(day) }
                }
                Text("Kein Brain Dump an diesem Tag.").foregroundStyle(.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(NotesListView.routineTitle(day: day, calendar: environment.planning.calendar))
        .navigationBarTitleDisplayMode(.inline)
    }
}

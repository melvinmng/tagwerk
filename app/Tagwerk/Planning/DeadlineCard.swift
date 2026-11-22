import SwiftUI
import TagwerkCore

/// Important deadlines of the coming days (mockup a, DL2): rows open the deadline, holding offers its menu; marks
/// whose event vanished appear as rows to check. Hidden when there is nothing to show.
struct DeadlineCard: View {
    let model: PlanningModel
    let actions: DeadlineActions
    /// Set in the preview of a neighbour page: the deadlines of that day.
    @Environment(\.dayPageExtras) private var pageExtras

    var body: some View {
        let deadlines = pageExtras?.upcomingDeadlines ?? model.upcomingDeadlines
        let orphans = model.orphanedMarks
        if !deadlines.isEmpty || !orphans.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Deadlines", systemImage: "flag.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.redText)
                ForEach(deadlines) { deadline in
                    DeadlineRowLabel(deadline: deadline, model: model)
                        .deadlineInteractions(deadline, model: model, actions: actions)
                }
                ForEach(orphans) { orphan in OrphanedMarkRow(orphan: orphan, model: model) }
            }
            .padding(12)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

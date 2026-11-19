import SwiftUI
import TagwerkCore

/// The morning start (design §7.4). Filled in by the following tasks; for now only the frame.
struct MorningSheet: View {
    let model: RoutinesModel
    let day: PlanDay

    var body: some View {
        NavigationStack {
            Form {}
                .navigationTitle("Tagesstart")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { model.closeSheet() } } }
        }
    }
}

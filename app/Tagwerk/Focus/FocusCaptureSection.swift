import SwiftUI
import TagwerkCore

/// The section "Fokus-Timer" at the end of the "Erfassen" list: a free start, the running session and the collection.
struct FocusCaptureSection: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let focus = environment.focus
        Section {
            if let session = focus.session {
                Button { focus.isPresented = true } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack {
                            Label(session.title.isEmpty ? String(localized: "Fokus läuft") : session.title, systemImage: "timer")
                            Spacer()
                            if let snapshot = focus.snapshot(at: context.date) {
                                Text(snapshot.phase == .finished ? FocusTimerText.phaseName(.finished) : FocusTimerText.clock(snapshot.remainingSeconds))
                                    .monospacedDigit().foregroundStyle(.secondaryText)
                            }
                        }
                    }
                }
                .foregroundStyle(.primary)
            } else {
                Button { Task { await focus.requestStart(task: nil, block: nil) } } label: {
                    Label("Frei starten", systemImage: "timer")
                }
            }
            NavigationLink {
                FocusCollectionView()
            } label: {
                LabeledContent("Sammlung", value: FocusTimerText.collectionSummary(summary))
            }
        } header: {
            Text("Fokus-Timer")
        }
    }

    private var summary: FocusCollectionSummary {
        FocusReward.summary(of: environment.focusStore.finishedSessions().compactMap(\.piece))
    }
}

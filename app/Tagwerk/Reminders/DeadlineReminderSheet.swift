import RemindersKit
import SwiftUI
import TagwerkCore

/// The Tagwerk reminders of a deadline event (plan P4, Task 10). The question for a repeating deadline hangs on the form,
/// not on a section (see PR #202).
struct DeadlineReminderSheet: View {
    let event: CalendarEvent
    let calendar: Calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var model: DeadlineReminderModel?
    @State private var asksReach = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let model {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                    Section {
                        ReminderSelectionRows(model: model.list, subject: .deadline, calendar: calendar)
                    } header: {
                        Text("Erinnerungen")
                    } footer: {
                        Text("Tagwerk erinnert mit Mitteilungen. Ruhezeiten und Fokus-Filter gelten dafür.")
                    }
                }
            }
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        guard let model else { return }
                        if model.asksReach { asksReach = true } else { save(.allFollowing) }
                    }
                    .disabled(model?.hasChanges != true)
                }
            }
            .confirmationDialog("Diese Deadline wiederholt sich", isPresented: $asksReach, titleVisibility: .visible) {
                Button("Nur diese Deadline") { save(.onlyThis) }
                Button("Diese und alle folgenden") { save(.allFollowing) }
            }
            .task {
                guard model == nil else { return }
                model = DeadlineReminderModel(event: event, overrides: environment.reminderOverrides,
                                              defaults: environment.settings.reminderDefaults, calendar: calendar)
            }
        }
    }

    private func save(_ reach: DeadlineReminderModel.Reach) {
        guard let model else { return }
        do {
            try model.save(reach: reach)
            environment.notifications.scheduleSoon()
            dismiss()
        } catch {
            errorMessage = TaskListModel.message(for: error)
        }
    }
}

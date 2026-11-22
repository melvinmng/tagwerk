import RemindersKit
import SwiftUI
import TagwerkCore

/// The Tagwerk reminders of a deadline event (plan P4, Task 10). The question for a repeating deadline hangs on the form,
/// not on a section (see PR #202).
struct DeadlineReminderSheet: View {
    let event: CalendarEvent
    let calendar: Calendar
    let planning: PlanningModel
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
                    let quietContext: (anchor: Date, quietHours: QuietHours?) = (event.start, environment.settings.quietHours)
                    Section {
                        ReminderSelectionRows(model: model.list, subject: .deadline, calendar: calendar, quietContext: quietContext)
                    } header: {
                        Label("Tagwerk-Mitteilungen", systemImage: "bell")
                    } footer: {
                        let base = String(localized: "Kommen als Mitteilung von Tagwerk. Ruhezeiten und Fokus-Filter gelten.")
                        if let note = ReminderSelectionRows.quietNote(model: model.list, quietContext: quietContext, calendar: calendar) {
                            Text(base + " " + note)
                        } else {
                            Text(base)
                        }
                    }
                    Section {
                        if model.canEditCalendarAlarms {
                            ReminderSelectionRows(model: model.calendarAlarms, subject: .deadline, defaultSwitchTitle: nil,
                                                  customTitle: "Hinweis hinzufügen", calendar: calendar)
                        } else {
                            ForEach(model.calendarAlarms.offsets, id: \.self) { offset in
                                Text(ReminderText.describe(offset, subject: .deadline, isAllDay: event.isAllDay, locale: .current,
                                                           calendar: calendar))
                            }
                            if model.calendarAlarms.offsets.isEmpty { Text("Keine").foregroundStyle(.secondary) }
                        }
                    } header: {
                        Label("Hinweise im Kalender (Apple)", systemImage: "alarm")
                    } footer: {
                        if let reason = model.calendarAlarmsReadOnlyReason {
                            Text(reason)
                        } else {
                            Text("Gehören zum Kalendertermin und erscheinen auf allen Geräten. Ruhezeiten gelten dafür nicht.")
                        }
                    }
                    if !model.duplicates.isEmpty {
                        Section {
                            ForEach(Array(model.duplicates.enumerated()), id: \.offset) { _, duplicate in
                                Label(ReminderDuplicates.notice(duplicate, subject: .deadline, isAllDay: event.isAllDay, locale: .current,
                                                                calendar: calendar), systemImage: "exclamationmark.triangle")
                            }
                            .listRowBackground(Color.yellow.opacity(0.25))
                        }
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
            .confirmationDialog(ReminderReachText.title(.deadline), isPresented: $asksReach, titleVisibility: .visible) {
                let day = PlanDay(date: event.start, calendar: calendar)
                Button(ReminderReachText.onlyThis(day, calendar: calendar)) { save(.onlyThis) }
                Button(ReminderReachText.fromThis(day, calendar: calendar)) { save(.allFollowing) }
            }
            .task {
                guard model == nil else { return }
                model = DeadlineReminderModel(event: event, overrides: environment.reminderOverrides,
                                              defaults: environment.settings.reminderDefaults, calendar: calendar,
                                              calendarAlarms: planning.alarms(ofEvent: event.id))
            }
        }
    }

    private func save(_ reach: DeadlineReminderModel.Reach) {
        guard let model else { return }
        Task {
            do {
                try await model.saveAll(reach: reach) { alarms, span in
                    var draft = EventDraft(event)
                    draft.alarms = alarms
                    _ = try await planning.updateEventReportingErrors(event, with: draft, span: span)
                }
                environment.notifications.scheduleSoon()
                dismiss()
            } catch {
                errorMessage = TaskListModel.message(for: error)
            }
        }
    }
}

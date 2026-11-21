import SwiftUI
import TagwerkCore

/// "Standard-Erinnerungen" (plan P4, ER7b): when Tagwerk reminds by default. The page is the overview with one row per kind
/// (calendar events, Apple reminders, GitHub issues, local tasks, deadlines) and the short form of its list with a time of day;
/// a kind opens a page with its two lists, each opening the selection page. Opening the pages writes nothing; only a change is stored.
struct ReminderDefaultsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ReminderDefaultsModel?

    var body: some View {
        Form {
            if let model {
                Section {
                    ForEach(ReminderKind.allCases, id: \.self) { kind in
                        NavigationLink {
                            ReminderDefaultsKindPage(model: model, kind: kind)
                        } label: {
                            LabeledContent(ReminderDefaultsModel.kindTitle(kind),
                                           value: model.rowSummary(for: .init(kind: kind, isAllDay: false)))
                        }
                    }
                } footer: {
                    Text("Gilt für alles ohne eigene Erinnerungen. Für Kalendertermine nur beim Anlegen in Tagwerk.")
                }
            }
        }
        .navigationTitle("Standard-Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = ReminderDefaultsModel(defaults: environment.settings.reminderDefaults) }
        }
        .onChange(of: model?.defaults) { old, defaults in
            // The first value, when the model is created, is not a change.
            if old != nil, let defaults { environment.settings.reminderDefaults = defaults }
        }
    }
}

/// The two lists of one kind: with and without a time of day (all-day for events and deadlines).
struct ReminderDefaultsKindPage: View {
    let model: ReminderDefaultsModel
    let kind: ReminderKind

    var body: some View {
        Form {
            Section {
                ForEach([false, true], id: \.self) { isAllDay in
                    let slot = ReminderDefaultsModel.Slot(kind: kind, isAllDay: isAllDay)
                    NavigationLink {
                        ReminderSelectionPage(model: model.list(slot), subject: kind.subject, defaultSwitchTitle: nil, calendar: .tagwerk)
                    } label: {
                        LabeledContent(ReminderDefaultsModel.slotTitle(slot), value: model.rowSummary(for: slot))
                    }
                }
            } footer: {
                Text(Self.footer(for: kind))
            }
        }
        .navigationTitle(ReminderDefaultsModel.kindTitle(kind))
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func footer(for kind: ReminderKind) -> LocalizedStringKey {
        switch kind {
        case .event: "Wird beim Anlegen eines Termins in Tagwerk übernommen. Bestehende Termine bleiben unverändert."
        case .appleReminder: "Gilt für alle Apple Erinnerungen ohne eigene Erinnerungen."
        case .githubIssue: "Gilt für alle GitHub-Issues ohne eigene Erinnerungen."
        case .localTask: "Gilt für alle lokalen Aufgaben ohne eigene Erinnerungen."
        case .deadline: "Gilt für alle Deadline-Termine ohne eigene Erinnerungen."
        }
    }
}

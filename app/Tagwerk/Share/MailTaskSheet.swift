import SwiftUI
import TagwerkCore

/// The first step of "Mail zu Aufgabe": what was shared, a proposal for the task, and the optional summary from ChatGPT.
struct MailTaskSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let model: MailTaskModel
    let onContinue: () -> Void
    /// Offered by shared items; the clipboard route has nothing to discard.
    var onDiscard: (() -> Void)?

    private var calendar: Calendar { environment.planning.calendar }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                summarySection
                taskSection
                dueSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Mail zu Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        model.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Weiter", action: onContinue).disabled(!model.canContinue)
                }
                if let onDiscard {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Verwerfen", role: .destructive) {
                            model.cancel()
                            onDiscard()
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: Bindable(model).showsConsent) {
                MailSummaryConsentSheet(onAgree: { model.consentGiven() }, onDecline: { model.showsConsent = false })
            }
        }
        .onDisappear { model.cancel() }
    }

    // MARK: Sections

    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.subject.isEmpty ? String(localized: "Ohne Betreff") : model.subject).font(.headline)
                if let sender = model.senderLine { Text(sender).font(.subheadline).foregroundStyle(.secondary) }
                if let date = model.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            if environment.ai.isSignedIn {
                Button {
                    model.summarize()
                } label: {
                    HStack {
                        Label("Mit ChatGPT zusammenfassen", systemImage: "sparkles")
                        if model.phase == .loading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(model.phase == .loading || model.bodyText.isEmpty)
            } else {
                Text("Für die Zusammenfassung melde dich unter Einstellungen › KI bei ChatGPT an.")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if case .failed(let message) = model.phase {
                Text(message).foregroundStyle(.red)
            } else if environment.settings.mailSummaryConsent {
                Text("Gesendet werden nur Betreff, Absendername und Text, nur auf dein Tippen.")
            }
        }
    }

    private var taskSection: some View {
        Section {
            suggestionRow(.title) {
                TextField("Titel", text: Binding(get: { model.title }, set: { model.editTitle($0) }))
            }
            suggestionRow(.notes) {
                TextField("Notiz", text: Binding(get: { model.notes }, set: { model.editNotes($0) }), axis: .vertical)
                    .keyboardDoneButton()
            }
        } header: {
            Text("Aufgabe")
        }
    }

    private var dueSection: some View {
        Section {
            Toggle("Fällig", isOn: Binding(
                get: { model.due != nil },
                set: { on in model.editDue(on ? (model.due ?? defaultDue) : nil) }))
            if let due = model.due {
                suggestionRow(.due) {
                    DatePicker("Datum", selection: Binding(
                        get: { due.startDate(in: calendar) },
                        set: { model.editDue(DueDate(date: $0, includeTime: due.hasTime, calendar: calendar)) }),
                               displayedComponents: due.hasTime ? [.date, .hourAndMinute] : [.date])
                        .environment(\.calendar, calendar)
                        .environment(\.timeZone, calendar.timeZone)
                }
                Toggle("Uhrzeit", isOn: Binding(
                    get: { due.hasTime },
                    set: { on in
                        let moment = due.startDate(in: calendar)
                        model.editDue(DueDate(date: on ? moment.addingTimeInterval(9 * 3600) : moment, includeTime: on, calendar: calendar))
                    }))
            }
        }
    }

    /// The row with the mark "Vorschlag" while the value comes from ChatGPT and was not yet changed; a tap on the mark keeps it.
    private func suggestionRow<Content: View>(_ field: MailTaskModel.Field, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
            if model.suggestedFields.contains(field) {
                Button("Vorschlag") { model.confirm(field) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityHint("Übernimmt den Vorschlag")
            }
        }
    }

    private var defaultDue: DueDate {
        DueDate(date: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now, includeTime: false, calendar: calendar)
    }
}

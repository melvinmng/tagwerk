import SwiftUI
import TagwerkCore

/// The first step of "Mail zu Aufgabe": the mail as a card, a proposal for the task, and the optional summary from ChatGPT.
/// Fields that carry a proposal of ChatGPT are tinted and marked with a symbol until the user changes them.
struct MailTaskSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let model: MailTaskModel
    let onContinue: () -> Void
    /// Offered by shared items; the clipboard route has nothing to discard.
    var onDiscard: (() -> Void)?
    /// The mail text is expanded in the card ("mehr").
    @State private var showsFullBody = false

    private var calendar: Calendar { environment.planning.calendar }
    /// Light purple behind a proposed field; a fill, so it does not carry any text.
    private static let suggestionTint = Color.purple.opacity(0.12)

    var body: some View {
        NavigationStack {
            Form {
                mailCard
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

    // MARK: Mail card

    /// One section: subject, sender and date, the first lines of the mail, and the button for the summary.
    private var mailCard: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.subject.isEmpty ? String(localized: "Ohne Betreff") : model.subject).font(.headline)
                if let byline {
                    Text(byline).font(.subheadline).foregroundStyle(.secondaryText)
                }
                if !model.bodyText.isEmpty { bodyText }
            }
            summaryControl
        } footer: {
            if case .failed(let message) = model.phase {
                Text(message).foregroundStyle(.redText)
            } else if environment.settings.mailSummaryConsent {
                Text("Gesendet werden nur Betreff, Absendername und Text, nur auf dein Tippen.")
            }
        }
    }

    /// "Absender · Datum", whichever of the two exist.
    private var byline: String? {
        let parts = [model.senderLine, model.date?.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The start of the mail, an ellipsis and the word "mehr" in bold.
    private var truncatedBody: AttributedString {
        var text = AttributedString(model.bodyPreview + "… ")
        var more = AttributedString(String(localized: "mehr"))
        more.inlinePresentationIntent = .stronglyEmphasized
        text.append(more)
        return text
    }

    @ViewBuilder
    private var bodyText: some View {
        if showsFullBody || !model.bodyIsTruncated {
            // The card does not scroll; a long mail ends with an ellipsis after twelve lines.
            Text(showsFullBody ? model.bodyText : model.bodyPreview)
                .font(.footnote)
                .lineLimit(12)
                .padding(.top, 4)
        } else {
            Text(truncatedBody)
                .font(.footnote)
                .padding(.top, 4)
                .onTapGesture { showsFullBody = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("mehr")) { showsFullBody = true }
        }
    }

    @ViewBuilder
    private var summaryControl: some View {
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
                .foregroundStyle(.secondaryText)
        }
    }

    // MARK: Task

    private var taskSection: some View {
        Section {
            suggestionRow(.title) {
                TextField("Titel", text: Binding(get: { model.title }, set: { model.editTitle($0) }))
            }
            suggestionRow(.notes) {
                TextField("Notiz", text: Binding(get: { model.notes }, set: { model.editNotes($0) }), axis: .vertical)
                    .keyboardDoneButton()
            }
            if let reference {
                // Sender and link go into the notes of the task as before; here they are only shown.
                Text(reference).font(.footnote).foregroundStyle(.secondaryText)
            }
        } header: {
            Text("Aufgabe")
        }
    }

    /// "Von: …  · Link zur Mail"; nil when the mail has neither.
    private var reference: String? {
        let parts = [model.senderNote, model.hasMailLink ? String(localized: "Link zur Mail") : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Fällig" is one row with the switch and the date; a proposed date is tinted like the other fields. "Uhrzeit" stays a row.
    private var dueSection: some View {
        Section {
            suggestionRow(.due) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { dueLabel; Spacer(minLength: 8); dueDatePicker; dueToggle }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { dueLabel; Spacer(minLength: 8); dueToggle }
                        dueDatePicker
                    }
                }
            }
            if let due = model.due {
                Toggle("Uhrzeit", isOn: Binding(
                    get: { due.hasTime },
                    set: { on in
                        let moment = due.startDate(in: calendar)
                        model.editDue(DueDate(date: on ? moment.addingTimeInterval(9 * 3600) : moment, includeTime: on, calendar: calendar))
                    }))
            }
        } footer: {
            if !model.suggestedFields.isEmpty {
                Text("✦ Vorschlag von ChatGPT. Ändern oder so lassen; gesichert wird erst im nächsten Schritt.")
            }
        }
    }

    private var dueLabel: some View { Text("Fällig") }

    private var dueToggle: some View {
        Toggle("Fällig", isOn: Binding(
            get: { model.due != nil },
            set: { on in model.editDue(on ? (model.due ?? defaultDue) : nil) }))
            .labelsHidden()
    }

    @ViewBuilder
    private var dueDatePicker: some View {
        if let due = model.due {
            DatePicker("Datum", selection: Binding(
                get: { due.startDate(in: calendar) },
                set: { model.editDue(DueDate(date: $0, includeTime: due.hasTime, calendar: calendar)) }),
                       displayedComponents: due.hasTime ? [.date, .hourAndMinute] : [.date])
                .labelsHidden()
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
        }
    }

    /// A row with a proposal of ChatGPT: a symbol on the left and a tinted background until the user changes the value. The
    /// structure stays the same in both states, so a focused field keeps its focus when the mark goes. VoiceOver gets the
    /// action "Vorschlag übernehmen" instead of a button.
    private func suggestionRow<Content: View>(_ field: MailTaskModel.Field, @ViewBuilder content: () -> Content) -> some View {
        let isSuggested = model.suggestedFields.contains(field)
        return HStack(spacing: 8) {
            if isSuggested {
                Image(systemName: "sparkles").foregroundStyle(.purple).accessibilityHidden(true)
            }
            content()
                .accessibilityHint(isSuggested ? Text("Vorschlag von ChatGPT") : Text(verbatim: ""))
                .accessibilityActions {
                    if isSuggested { Button("Vorschlag übernehmen") { model.confirm(field) } }
                }
        }
        .listRowBackground(isSuggested ? Self.suggestionTint : nil)
    }

    private var defaultDue: DueDate {
        DueDate(date: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now, includeTime: false, calendar: calendar)
    }
}

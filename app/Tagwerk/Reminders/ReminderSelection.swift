import SwiftUI
import TagwerkCore

/// The rows of a reminder list for a `Section` (plan g1, ER2b): the default switch, the usual distances and every reminder
/// that is set, each with a checkmark, and "Eigene …". A tap sets or removes a reminder. While the default applies the
/// rows are grey and show the checkmarks of the default; a tap then starts an own list from the default.
/// "Eigene …" opens as a page in the surrounding `NavigationStack`, so no sheet hangs on a section or a row (see PR #202).
struct ReminderSelectionRows: View {
    @Bindable var model: ReminderListModel
    /// What the reminders count from; decides the wording of the distance 0.
    let subject: ReminderSubject
    /// Title of the switch for the default list; `nil` for lists that have no default behind them.
    var defaultSwitchTitle: LocalizedStringKey? = "Standard verwenden"
    /// Title of the row that opens the page for an own distance.
    var customTitle: LocalizedStringKey = "Eigene …"
    var calendar: Calendar = .tagwerk
    /// The moment the reminders count from and the quiet hours; without them no hint is shown (default settings, alarms of
    /// Calendar and Reminders, where quiet hours do not apply). Plan g1, RH6c.
    var quietContext: (anchor: Date, quietHours: QuietHours?)? = nil

    /// When quiet hours deliver the reminder `offset` later than its own moment: "kommt 07:00".
    private func quietDelivery(of offset: ReminderOffset) -> Date? {
        Self.quietDelivery(of: offset, model: model, quietContext: quietContext, calendar: calendar)
    }

    private static func quietDelivery(of offset: ReminderOffset, model: ReminderListModel,
                                      quietContext: (anchor: Date, quietHours: QuietHours?)?, calendar: Calendar) -> Date? {
        guard let quietContext, model.isSelected(offset) else { return nil }
        return ReminderQuietHint.delivery(of: offset, anchor: quietContext.anchor, isAllDay: model.isAllDay,
                                          quietHours: quietContext.quietHours, calendar: calendar)
    }

    /// The sentence under the list when a row carries "kommt …"; `nil` when no reminder is held back.
    static func quietNote(model: ReminderListModel, quietContext: (anchor: Date, quietHours: QuietHours?)?,
                          calendar: Calendar = .tagwerk) -> String? {
        guard let window = quietContext?.quietHours,
              model.choiceRows.contains(where: { quietDelivery(of: $0, model: model, quietContext: quietContext, calendar: calendar) != nil })
        else { return nil }
        let start = DateText.time(minutes: window.startMinutes, calendar: calendar)
        let end = DateText.time(minutes: window.endMinutes, calendar: calendar)
        return String(localized: "Fällt in die Ruhezeit (\(start)–\(end)) und wird bis zu deren Ende zurückgehalten.")
    }

    var body: some View {
        if let defaultSwitchTitle {
            Toggle(defaultSwitchTitle, isOn: usesDefault.animation())
        }
        ForEach(model.choiceRows, id: \.self) { offset in
            let isSelected = model.isSelected(offset)
            Button {
                model.toggle(offset)
            } label: {
                HStack {
                    Text(ReminderText.describe(offset, subject: subject, isAllDay: model.isAllDay, locale: .current, calendar: calendar))
                    Spacer()
                    if let delivery = quietDelivery(of: offset) {
                        Text("kommt \(DateText.time(delivery, calendar: calendar, locale: .current))")
                            .font(.footnote)
                            .foregroundStyle(.secondaryText)
                    }
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(model.isUsingDefault ? AnyShapeStyle(.secondaryText) : AnyShapeStyle(.tint))
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(model.isUsingDefault ? AnyShapeStyle(.secondaryText) : AnyShapeStyle(.primary))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(model.isUsingDefault ? Text("Standard") : Text(verbatim: ""))
        }
        NavigationLink {
            ReminderOffsetPicker(isAllDay: model.isAllDay, subject: subject, calendar: calendar) { model.add($0) }
        } label: {
            Text(customTitle)
        }
    }

    private var usesDefault: Binding<Bool> {
        Binding(get: { model.isUsingDefault },
                set: { if $0 { model.useDefault() } else { model.customize() } })
    }
}

/// The same rows as a page of the navigation stack with the title "Erinnerungen" and an optional footer.
struct ReminderSelectionPage: View {
    @Bindable var model: ReminderListModel
    let subject: ReminderSubject
    var defaultSwitchTitle: LocalizedStringKey? = "Standard verwenden"
    var calendar: Calendar = .tagwerk
    var footer: String?
    /// See `ReminderSelectionRows.quietContext`.
    var quietContext: (anchor: Date, quietHours: QuietHours?)? = nil

    var body: some View {
        Form {
            Section {
                ReminderSelectionRows(model: model, subject: subject, defaultSwitchTitle: defaultSwitchTitle, calendar: calendar,
                                      quietContext: quietContext)
            } footer: {
                Text(footerText)
            }
        }
        .navigationTitle("Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footerText: String {
        var parts = [String(localized: "Antippen setzt oder entfernt eine Erinnerung.")]
        if let note = ReminderSelectionRows.quietNote(model: model, quietContext: quietContext, calendar: calendar) { parts.append(note) }
        if let footer { parts.append(footer) }
        return parts.joined(separator: " ")
    }
}

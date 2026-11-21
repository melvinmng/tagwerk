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
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(model.isUsingDefault ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(model.isUsingDefault ? .secondary : .primary)
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

    var body: some View {
        Form {
            Section {
                ReminderSelectionRows(model: model, subject: subject, defaultSwitchTitle: defaultSwitchTitle, calendar: calendar)
            } footer: {
                Text(footerText)
            }
        }
        .navigationTitle("Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footerText: String {
        let hint = String(localized: "Antippen setzt oder entfernt eine Erinnerung.")
        guard let footer else { return hint }
        return hint + " " + footer
    }
}

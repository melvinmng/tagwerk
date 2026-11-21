import SwiftUI
import TagwerkCore

/// The rows of a reminder list: the default switch, one row per reminder (swipe to delete) and "Erinnerung hinzufügen".
/// It delivers rows only, to be put into a `Section` of a `Form`. The picker opens as a page in the surrounding
/// `NavigationStack`, so no sheet is attached to a section or a row (see PR #202).
struct ReminderListEditor: View {
    @Bindable var model: ReminderListModel
    /// What the reminders count from; decides the wording of the distance 0.
    let subject: ReminderSubject
    /// Title of the switch for the default list; `nil` for lists that have no default behind them.
    var defaultSwitchTitle: LocalizedStringKey? = "Standard verwenden"
    var calendar: Calendar = .tagwerk

    var body: some View {
        if let defaultSwitchTitle {
            Toggle(defaultSwitchTitle, isOn: usesDefault.animation())
        }
        ForEach(Array(model.displayed.enumerated()), id: \.offset) { index, offset in
            Text(ReminderText.describe(offset, subject: subject, isAllDay: model.isAllDay, locale: .current, calendar: calendar))
                .foregroundStyle(model.isUsingDefault ? .secondary : .primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: !model.isUsingDefault) {
                    if !model.isUsingDefault {
                        Button(role: .destructive) { withAnimation { model.remove(at: index) } } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
                .accessibilityHint(model.isUsingDefault ? Text("Standard") : Text("Zum Löschen nach links wischen"))
        }
        if model.displayed.isEmpty {
            Text("Keine Erinnerungen").foregroundStyle(.secondary)
        }
        if !model.isUsingDefault {
            NavigationLink {
                ReminderOffsetPicker(isAllDay: model.isAllDay, subject: subject, calendar: calendar) { model.add($0) }
            } label: {
                Label("Erinnerung hinzufügen", systemImage: "plus.circle")
            }
        }
    }

    private var usesDefault: Binding<Bool> {
        Binding(get: { model.isUsingDefault },
                set: { if $0 { model.useDefault() } else { model.customize() } })
    }
}

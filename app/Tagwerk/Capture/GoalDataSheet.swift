import SwiftUI
import TagwerkCore

extension GoalDataGroup {
    /// The title of the group in the selection sheet.
    var title: String {
        switch self {
        case .body: String(localized: "Körper")
        case .weight: String(localized: "Gewicht und Trend")
        case .nutrition: String(localized: "Ernährung")
        case .activity: String(localized: "Aktivität")
        case .water: String(localized: "Wasser")
        case .goals: String(localized: "Geltende Ziele")
        }
    }

    /// The short name of the group in the line "Gelesen: …" of the chat.
    var activityName: String {
        switch self {
        case .body: String(localized: "Körperdaten")
        case .weight: String(localized: "Gewicht")
        case .nutrition: String(localized: "Ernährung")
        case .activity: String(localized: "Aktivität")
        case .water: String(localized: "Wasser")
        case .goals: String(localized: "Ziele")
        }
    }
}

/// The selection sheet before the goal planning chat (decision PV2a, mockup PV2a): every group of the data package with its values and a
/// switch. What the sheet shows is exactly what is sent; nothing leaves the iPhone before "Gespräch beginnen" and a message. The sheet hangs on the root
/// view, never on a row (a sheet on a list row does not open reliably).
struct GoalDataSheet: View {
    let draft: GoalPlanningSession
    /// "Gespräch beginnen" with the groups that are switched on.
    let onBegin: (Set<GoalDataGroup>) -> Void
    let onCancel: () -> Void
    @State private var selected: Set<GoalDataGroup>
    @Environment(\.dismiss) private var dismiss

    /// - Parameter initiallyOn: the groups that start switched on (the choice of the last conversation).
    init(draft: GoalPlanningSession, initiallyOn: Set<GoalDataGroup>, onBegin: @escaping (Set<GoalDataGroup>) -> Void,
         onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onBegin = onBegin
        self.onCancel = onCancel
        _selected = State(initialValue: initiallyOn)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Das geht an ChatGPT, wenn du das Gespräch beginnst. Schalte aus, was nicht mitgehen soll.")
                        .font(.subheadline)
                }
                ForEach(draft.package.groups, id: \.self) { group in
                    Section {
                        Toggle(group.title, isOn: Binding(get: { selected.contains(group) },
                                                          set: { if $0 { selected.insert(group) } else { selected.remove(group) } }))
                            .accessibilityIdentifier(AccessibilityID.GoalPlanning.groupSwitch(group.rawValue))
                        if selected.contains(group) {
                            ForEach(draft.package.lines(for: group), id: \.self) { line in
                                Text(line).font(.subheadline).foregroundStyle(.secondaryText)
                            }
                        }
                    }
                }
                Section {
                    DisclosureGroup("Genau diese Werte senden") {
                        Text(draft.package.keeping(selected).json)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .accessibilityIdentifier(AccessibilityID.GoalPlanning.packageJSON)
                    }
                } footer: {
                    Text("Durchschnitte über \(draft.package.periodDays) Tage; Tage ohne Eintrag zählen nicht mit. Tagwerk gibt keine medizinische Beratung.")
                }
            }
            // Always in reach, whatever the length of the list above it: the user decides on this sheet, so the button must not sit
            // below the fold.
            .safeAreaInset(edge: .bottom) {
                Button {
                    onBegin(selected)
                    dismiss()
                } label: {
                    Text("Gespräch beginnen").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal).padding(.vertical, 8)
                .background(.bar)
                .accessibilityIdentifier(AccessibilityID.GoalPlanning.begin)
            }
            .navigationTitle("Ziele planen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .modifier(UITestAppearance())
    }
}

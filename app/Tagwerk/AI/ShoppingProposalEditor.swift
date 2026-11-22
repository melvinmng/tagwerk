import AIKit
import Observation
import SwiftUI
import TagwerkCore

/// Editor for `update_shopping` (plan ki-vorschlaege-anpassen, task B3): name and quantity of each item to add, and
/// which of the listed items are checked off. The function limits both lists to 30 entries; the editor says so
/// instead of letting the call fail.
@MainActor
@Observable
final class ShoppingProposalEditor: ProposalEditor {
    nonisolated static let toolNames: Set<String> = ["update_shopping"]

    static let maximum = 30

    struct Addition: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var quantity: String
        /// The entry as the model wrote it; `nil` for an item the user added.
        fileprivate var original: [String: Any]?

        static func == (lhs: Addition, rhs: Addition) -> Bool { lhs.id == rhs.id && lhs.name == rhs.name && lhs.quantity == rhs.quantity }
    }

    /// An item the call checks off, with its name as the list shows it.
    struct CheckOff: Identifiable, Equatable {
        let id: String
        let name: String
        var isOn = true
    }

    let call: ToolCall
    let context: ProposalEditorContext
    var additions: [Addition]
    var checkOffs: [CheckOff]

    @ObservationIgnored private let base: [String: Any]
    @ObservationIgnored private let initialAdditions: [Addition]
    @ObservationIgnored private let initialCheckOffs: [CheckOff]

    required init?(call: ToolCall, context: ProposalEditorContext) {
        guard Self.toolNames.contains(call.name), let base = ProposalArguments.decode(call.arguments) else { return nil }
        self.call = call
        self.context = context
        self.base = base
        let entries = base["add"] as? [[String: Any]] ?? []
        let additions = entries.map { entry in
            Addition(name: entry["name"] as? String ?? "", quantity: entry["quantity"] as? String ?? "", original: entry)
        }
        let checkOffs = (base["check_off"] as? [String] ?? []).map { CheckOff(id: $0, name: context.shoppingItemName($0) ?? $0) }
        self.additions = additions
        self.checkOffs = checkOffs
        initialAdditions = additions
        initialCheckOffs = checkOffs
    }

    func addItem() {
        guard additions.count < Self.maximum else { return }
        additions.append(Addition(name: "", quantity: "", original: nil))
    }

    func removeAdditions(at offsets: IndexSet) { additions.remove(atOffsets: offsets) }

    // MARK: ProposalEditor

    /// The items to add: named ones only, like the function reads them.
    private var namedAdditions: [Addition] { additions.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var checkedOff: [CheckOff] { checkOffs.filter(\.isOn) }

    var isValid: Bool {
        (!namedAdditions.isEmpty || !checkedOff.isEmpty) && additions.count <= Self.maximum
    }

    func arguments() -> Data {
        var result = base
        if additions != initialAdditions {
            result["add"] = namedAdditions.map { addition -> [String: Any] in
                let name = addition.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let quantity = addition.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
                var entry = addition.original ?? [:]
                entry["name"] = name
                entry["quantity"] = quantity.isEmpty ? NSNull() : quantity
                return entry
            }
        }
        if checkOffs != initialCheckOffs { result["check_off"] = checkedOff.map(\.id) }
        return ProposalArguments.encode(result)
    }

    var fields: AnyView { AnyView(ShoppingProposalFields(editor: self)) }

    func load() async {}
}

private struct ShoppingProposalFields: View {
    @Bindable var editor: ShoppingProposalEditor

    var body: some View {
        Section {
            ForEach($editor.additions) { $addition in
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Artikel", text: $addition.name)
                    TextField("Menge", text: $addition.quantity).font(.subheadline).foregroundStyle(.secondaryText)
                }
            }
            .onDelete { editor.removeAdditions(at: $0) }
            Button("Artikel hinzufügen") { editor.addItem() }
                .disabled(editor.additions.count >= ShoppingProposalEditor.maximum)
        } header: {
            Text("Hinzufügen")
        } footer: {
            if editor.additions.count >= ShoppingProposalEditor.maximum { Text("Höchstens 30 Artikel je Aufruf.") }
        }
        if !editor.checkOffs.isEmpty {
            Section("Abhaken") {
                ForEach($editor.checkOffs) { $item in Toggle(item.name, isOn: $item.isOn) }
            }
        }
    }
}

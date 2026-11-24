import Foundation

/// Decides whether the shopping page offers to translate the existing items after the language of the list changed. Pure.
public enum ShoppingTranslationOffer {
    public enum Step: Equatable, Sendable {
        case none
        /// Store `language` as the settled one without asking (first run, empty list).
        case adopt(VoiceLanguage)
        case offer(VoiceLanguage)
    }

    /// `settled` is the stored raw value of the language the open items were last translated into or kept in; `nil` before the
    /// first run. A stored value that is no supported language counts as a different one.
    public static func step(current: VoiceLanguage, settled: String?, openItemCount: Int) -> Step {
        guard let settled else { return .adopt(current) }
        if settled == current.rawValue { return Step.none }
        return openItemCount > 0 ? .offer(current) : .adopt(current)
    }
}

/// The request for translating the names of open shopping items and the check of its answer. Pure.
///
/// Only names go out: one per name key, in list order, at most `maximumItems` of them and `maximumCharacters` characters. The
/// answer is a proposal: it must carry exactly the requested indices, and every single entry is checked before the user sees it.
public struct ShoppingTranslationPlan: Sendable, Equatable {
    public static let maximumItems = 100
    public static let maximumCharacters = 4_000

    /// One name that goes out, with every open item that carries it.
    public struct Entry: Sendable, Equatable {
        public var index: Int
        public var name: String
        public var itemIDs: [String]
    }

    /// Why a translated name is not applied.
    public enum Blocked: Sendable, Equatable {
        /// The new name is the name of another open item.
        case alreadyOnList
        /// An earlier entry of the same answer already got this name.
        case sameTranslationTwice
    }

    public struct Change: Sendable, Equatable, Identifiable {
        public var itemID: String
        public var oldName: String
        public var newName: String
        /// Shown only, never sent or written.
        public var quantity: String?
        /// `nil`: can be applied.
        public var blocked: Blocked?
        public var id: String { itemID }

        public init(itemID: String, oldName: String, newName: String, quantity: String? = nil, blocked: Blocked? = nil) {
            self.itemID = itemID
            self.oldName = oldName
            self.newName = newName
            self.quantity = quantity
            self.blocked = blocked
        }
    }

    public enum Failure: Error, Equatable { case indexMismatch }

    public private(set) var entries: [Entry] = []
    /// Open items beyond the limits; they are not part of the request.
    public private(set) var leftOut = 0

    private struct Source: Sendable, Equatable {
        var oldNames: [String: String]
        var quantities: [String: String?]
    }
    private var source = Source(oldNames: [:], quantities: [:])
    /// Name keys of every open item, also of those left out: a new name must not equal any of them.
    private var openKeys: Set<String> = []

    /// `openItems` in list order. Items with the same name key form one entry; completed items are ignored by the caller.
    public init(openItems: [ShoppingItem]) {
        var indexByKey: [String: Int] = [:]
        var order: [String] = []
        var grouped: [String: Entry] = [:]
        for item in openItems {
            let key = ShoppingName.key(item.name)
            guard !key.isEmpty else { continue }
            openKeys.insert(key)
            source.oldNames[item.id] = item.name
            source.quantities[item.id] = item.quantity
            if grouped[key] != nil {
                grouped[key]?.itemIDs.append(item.id)
            } else {
                indexByKey[key] = order.count
                order.append(key)
                grouped[key] = Entry(index: order.count - 1, name: item.name.trimmingCharacters(in: .whitespacesAndNewlines), itemIDs: [item.id])
            }
        }
        var characters = 0
        var sent = 0
        for key in order {
            guard let entry = grouped[key] else { continue }
            if entries.count < Self.maximumItems, characters + entry.name.count <= Self.maximumCharacters {
                characters += entry.name.count
                entries.append(entry)
                sent += entry.itemIDs.count
            } else {
                // The first names that fit go out; everything after the first one that does not fit stays for the next run.
                break
            }
        }
        leftOut = openItems.filter { !ShoppingName.key($0.name).isEmpty }.count - sent
    }

    /// What goes to ChatGPT: the index and the name of every entry.
    public var request: [(index: Int, text: String)] {
        entries.map { (index: $0.index, text: $0.name) }
    }

    /// The items whose name changes. Throws when the answer does not carry exactly the requested indices, each once. An entry
    /// that fails its own check (empty, a line break, longer than a name may be, other numbers than the original) is dropped
    /// and its items stay as they are, as does an entry whose new name has the same key as the old one. A new name that
    /// is the name of another open item, or that an earlier entry of the answer got already, is returned as blocked.
    public func changes(translations: [(index: Int, text: String)]) throws(Failure) -> [Change] {
        let requested = Set(entries.map(\.index))
        guard translations.count == entries.count, Set(translations.map(\.index)) == requested else { throw Failure.indexMismatch }
        let byIndex = Dictionary(uniqueKeysWithValues: translations.map { ($0.index, $0.text) })
        var claimed = Set<String>()
        var result: [Change] = []
        for entry in entries {
            guard let text = byIndex[entry.index] else { continue }
            let newName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isAcceptable(newName, replacing: entry.name) else { continue }
            let newKey = ShoppingName.key(newName)
            let oldKey = ShoppingName.key(entry.name)
            guard newKey != oldKey else { continue }
            var blocked: Blocked?
            if openKeys.contains(newKey) {
                blocked = .alreadyOnList
            } else if !claimed.insert(newKey).inserted {
                blocked = .sameTranslationTwice
            }
            for id in entry.itemIDs {
                result.append(Change(itemID: id, oldName: source.oldNames[id] ?? entry.name, newName: newName,
                                     quantity: source.quantities[id] ?? nil, blocked: blocked))
            }
        }
        return result
    }

    /// The per-entry check: not empty, one line, not longer than a name may be (it is not cut), and the same digit sequences
    /// in the same order as the original ("Cola 0,5 l" must not become "Cola 0.33 l").
    private static func isAcceptable(_ name: String, replacing original: String) -> Bool {
        guard !name.isEmpty, !name.contains(where: \.isNewline), name.count <= ShoppingInputParser.maxNameLength else { return false }
        return digitRuns(name) == digitRuns(original)
    }

    private static func digitRuns(_ text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in text {
            if character.isASCII, character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}

import Foundation
import Observation
import TagwerkCore

/// State of the sheet "Mail zu Aufgabe" (plan P6, #166): the proposal for title, notes and due date, with or without the
/// summary from ChatGPT. The summary is fetched only after consent and a tap on "Mit ChatGPT zusammenfassen". A proposal
/// never overwrites a field the user already changed, and nothing is saved here: "Weiter" hands the fields to "Neue Aufgabe".
@MainActor
@Observable
final class MailTaskModel {
    enum Phase: Equatable {
        case idle
        case loading
        case failed(String)
    }

    /// Fields handed to "Neue Aufgabe".
    struct Prefill: Equatable {
        var title: String
        var notes: String
        var due: DueDate?
    }

    private(set) var title: String
    private(set) var notes: String
    private(set) var due: DueDate?
    private(set) var phase: Phase = .idle
    /// The consent sheet is open; the call follows when the user agrees.
    var showsConsent = false
    /// Fields that carry a proposal of ChatGPT until the user changes or confirms them ("Vorschlag").
    private(set) var suggestedFields: Set<Field> = []

    enum Field: Hashable { case title, notes, due }

    let subject: String
    /// The name that is sent with the summary request; never the address.
    let senderName: String?
    /// What the sheet and the notes show: the name, else the address.
    let senderLine: String?
    let date: Date?
    /// The text the summary is made from.
    let bodyText: String
    let mailLink: URL?

    @ObservationIgnored private let summarizer: MailSummarizer
    @ObservationIgnored private let hasConsent: @MainActor () -> Bool
    @ObservationIgnored private let grantConsent: @MainActor () -> Void
    @ObservationIgnored private var summary = ""
    @ObservationIgnored private var edited: Set<Field> = []
    @ObservationIgnored private var request: Task<Void, Never>?

    /// A shared mail.
    init(mail: MailMessage, summarizer: MailSummarizer, hasConsent: @escaping @MainActor () -> Bool,
         grantConsent: @escaping @MainActor () -> Void) {
        let subject = mail.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subject = subject
        self.senderName = mail.senderName
        self.senderLine = mail.senderName ?? mail.senderAddress
        self.date = mail.date
        self.bodyText = mail.bodyText
        self.mailLink = mail.messageID.flatMap { MailLink.url(messageID: $0) }
        self.title = subject.isEmpty ? Self.firstLine(of: mail.bodyText) : subject
        self.summarizer = summarizer
        self.hasConsent = hasConsent
        self.grantConsent = grantConsent
        self.notes = ""
        self.notes = composeNotes()
    }

    /// Plain text (selected in Mail, or pasted): the first line is the title.
    init(text: String, summarizer: MailSummarizer, hasConsent: @escaping @MainActor () -> Bool,
         grantConsent: @escaping @MainActor () -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subject = Self.firstLine(of: trimmed)
        self.senderName = nil
        self.senderLine = nil
        self.date = nil
        self.bodyText = trimmed
        self.mailLink = nil
        self.title = Self.firstLine(of: trimmed)
        self.summarizer = summarizer
        self.hasConsent = hasConsent
        self.grantConsent = grantConsent
        self.notes = ""
        self.notes = composeNotes()
    }

    var prefill: Prefill { Prefill(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes, due: due) }
    var canContinue: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .loading }

    // MARK: Editing

    func editTitle(_ value: String) {
        title = value
        edited.insert(.title)
        suggestedFields.remove(.title)
    }

    func editNotes(_ value: String) {
        notes = value
        edited.insert(.notes)
        suggestedFields.remove(.notes)
    }

    func editDue(_ value: DueDate?) {
        due = value
        edited.insert(.due)
        suggestedFields.remove(.due)
    }

    /// Keeps a proposed value as it is: the mark "Vorschlag" goes, a later proposal does not replace it.
    func confirm(_ field: Field) {
        suggestedFields.remove(field)
        edited.insert(field)
    }

    // MARK: Summary

    /// "Mit ChatGPT zusammenfassen". Without consent the consent sheet opens and nothing is sent.
    func summarize() {
        guard phase != .loading else { return }
        guard hasConsent() else {
            showsConsent = true
            return
        }
        // The state changes before the task starts, so a second tap right away finds the request running.
        phase = .loading
        request = Task { await fetch() }
    }

    /// The user agreed in the consent sheet.
    func consentGiven() {
        grantConsent()
        showsConsent = false
        guard phase != .loading else { return }
        phase = .loading
        request = Task { await fetch() }
    }

    func cancel() {
        request?.cancel()
        request = nil
        if phase == .loading { phase = .idle }
    }

    private func fetch() async {
        do {
            let result = try await summarizer.summarize(subject: subject, senderName: senderName, body: bodyText)
            apply(result)
            phase = .idle
        } catch is CancellationError {
            phase = .idle
        } catch let failure as MailSummarizer.Failure {
            phase = .failed(failure.message)
        } catch {
            phase = .failed(MailSummarizer.Failure.failed.message)
        }
    }

    private func apply(_ result: MailTaskSuggestion.Normalized) {
        if !edited.contains(.title) {
            title = result.title
            suggestedFields.insert(.title)
        }
        if !edited.contains(.notes) {
            summary = result.summary
            notes = composeNotes()
            if !summary.isEmpty { suggestedFields.insert(.notes) }
        }
        if !edited.contains(.due), let due = result.due {
            self.due = due
            suggestedFields.insert(.due)
        }
    }

    // MARK: Helpers

    /// The summary (when fetched), the sender and the link back to the mail.
    private func composeNotes() -> String {
        var lines: [String] = []
        if let senderLine, !senderLine.isEmpty { lines.append(String(localized: "Von: \(senderLine)")) }
        if let mailLink { lines.append(mailLink.absoluteString) }
        let details = lines.joined(separator: "\n")
        return [summary, details].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return String(line.prefix(120))
    }
}

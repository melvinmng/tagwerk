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

    /// The characters of the mail the card shows before "mehr".
    static let previewLength = 160

    private(set) var title: String
    /// The summary or what the user wrote; sender and link are not part of it, `prefill` adds them.
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
    @ObservationIgnored private var edited: Set<Field> = []
    @ObservationIgnored private var request: Task<Void, Never>?
    /// The follow-up about the proposal (plan ki-vorschlaege-anpassen, task E1): the request that is running or failed, the
    /// sentence of the last answer, and the fields before it for one step of "Rückgängig".
    private(set) var followUpState: FollowUpState = .ready
    private(set) var followUpReply = ""
    private(set) var lastFollowUpMessage = ""
    private(set) var canUndoRevision = false
    @ObservationIgnored private var undoSnapshot: Snapshot?
    /// Counts follow-ups and cancellations; an answer for an older count is dropped.
    @ObservationIgnored private var followUpGeneration = 0

    private struct Snapshot {
        var title: String
        var notes: String
        var due: DueDate?
        var suggestedFields: Set<Field>
        var edited: Set<Field>
    }

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
    }

    /// The fields of the task that is created: the notes, then the sender line and the link to the mail.
    var prefill: Prefill {
        Prefill(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: composeNotes(), due: due)
    }

    /// "Von: Erika Muster"; only the name, never the address, because the notes can reach other places (an issue, the assistant).
    var senderNote: String? {
        guard let senderName, !senderName.isEmpty else { return nil }
        return String(localized: "Von: \(senderName)")
    }
    var hasMailLink: Bool { mailLink != nil }

    /// The first lines of the mail for the card: at most `previewLength` characters, cut at a word boundary.
    var bodyPreview: String {
        guard bodyText.count > Self.previewLength else { return bodyText }
        let limit = bodyText.index(bodyText.startIndex, offsetBy: Self.previewLength)
        // The cut is clean when the next character is white space; otherwise step back to the last space.
        if bodyText[limit].isWhitespace { return String(bodyText[..<limit]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let space = bodyText[..<limit].lastIndex(where: \.isWhitespace) {
            let cut = String(bodyText[..<space]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cut.isEmpty { return cut }
        }
        return String(bodyText[..<limit])
    }
    var bodyIsTruncated: Bool { bodyPreview.count < bodyText.count }
    var canContinue: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .loading }

    // MARK: Editing

    func editTitle(_ value: String) {
        dropUndo()
        title = value
        edited.insert(.title)
        suggestedFields.remove(.title)
    }

    func editNotes(_ value: String) {
        dropUndo()
        notes = value
        edited.insert(.notes)
        suggestedFields.remove(.notes)
    }

    func editDue(_ value: DueDate?) {
        dropUndo()
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
        // A follow-up that is still running is dropped with the sheet: its answer must not arrive anywhere.
        followUpGeneration += 1
        if followUpState == .sending { followUpState = .ready }
    }

    // MARK: Follow-up

    /// "Mit ChatGPT besprechen" is offered with the consent of the summary and while the mail has a text.
    var canFollowUp: Bool { hasConsent() && !bodyText.isEmpty }

    /// One more request about the proposal: the mail again (subject, sender name, text), the fields as they are now with the ones
    /// the user set by hand, and the message. A field the answer changes carries the mark "Vorschlag" again, also when the
    /// user had set it (the message was about it); a field it repeats stays as it is. A due date the answer leaves out stays:
    /// removing one is done by hand. One step of "Rückgängig" brings the fields from before back.
    func revise(_ comment: String) async {
        let comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canFollowUp, followUpState != .sending, phase != .loading, !comment.isEmpty else { return }
        lastFollowUpMessage = comment
        followUpState = .sending
        followUpGeneration += 1
        let mine = followUpGeneration
        let current = MailTaskSuggestion.Normalized(title: title.trimmingCharacters(in: .whitespacesAndNewlines), summary: notes, due: due)
        var fixed: [String] = []
        if edited.contains(.title) { fixed.append("title") }
        if edited.contains(.notes) { fixed.append("summary") }
        if edited.contains(.due) { fixed.append("due") }
        do {
            let answer = try await summarizer.revise(subject: subject, senderName: senderName, body: bodyText, current: current,
                                                     fixed: fixed, comment: comment)
            guard mine == followUpGeneration else { return }
            applyRevision(answer, current: current)
            followUpState = .ready
        } catch is CancellationError {
            if mine == followUpGeneration { followUpState = .ready }
        } catch let failure as MailSummarizer.Failure {
            guard mine == followUpGeneration else { return }
            followUpState = .failed(failure.message)
        } catch {
            guard mine == followUpGeneration else { return }
            followUpState = .failed(MailSummarizer.Failure.failed.message)
        }
    }

    private func applyRevision(_ answer: MailTaskSuggestion.Normalized, current: MailTaskSuggestion.Normalized) {
        let before = Snapshot(title: title, notes: notes, due: due, suggestedFields: suggestedFields, edited: edited)
        var changed = false
        if answer.title != current.title {
            title = answer.title
            suggestedFields.insert(.title)
            edited.remove(.title)
            changed = true
        }
        if answer.summary != current.summary {
            notes = answer.summary
            if notes.isEmpty { suggestedFields.remove(.notes) } else { suggestedFields.insert(.notes) }
            edited.remove(.notes)
            changed = true
        }
        if let newDue = answer.due, newDue != current.due {
            due = newDue
            suggestedFields.insert(.due)
            edited.remove(.due)
            changed = true
        }
        if changed {
            undoSnapshot = before
            canUndoRevision = true
            followUpReply = String(localized: "Vorschlag überarbeitet.")
        } else {
            followUpReply = String(localized: "Keine Änderung.")
        }
    }

    /// "Rückgängig": the fields as they were before the last answer, with their marks.
    func undoRevision() {
        guard let before = undoSnapshot else { return }
        title = before.title
        notes = before.notes
        due = before.due
        suggestedFields = before.suggestedFields
        edited = before.edited
        dropUndo()
        followUpReply = ""
    }

    private func dropUndo() {
        undoSnapshot = nil
        canUndoRevision = false
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
            notes = result.summary
            if !notes.isEmpty { suggestedFields.insert(.notes) }
        }
        if !edited.contains(.due), let due = result.due {
            self.due = due
            suggestedFields.insert(.due)
        }
    }

    // MARK: Helpers

    /// The notes of the task: what the user sees in the field, the sender and the link back to the mail.
    private func composeNotes() -> String {
        var lines: [String] = []
        if let senderNote { lines.append(senderNote) }
        if let mailLink { lines.append(mailLink.absoluteString) }
        let details = lines.joined(separator: "\n")
        return [notes, details].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return String(line.prefix(120))
    }
}

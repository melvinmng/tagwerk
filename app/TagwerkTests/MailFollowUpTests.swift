import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// The follow-up about the proposal of "Mail zu Aufgabe" (plan ki-vorschlaege-anpassen, task E1). All data is invented;
/// addresses use example.com.
@MainActor
final class MailFollowUpTests {
    let responder = FakePlanResponder()
    var consent = true
    var modelCalls = 0
    static let first = #"{"title":"Angebot bis Freitag senden","summary":"Erika bittet um das Angebot.","due":"2026-11-27"}"#

    let mail = MailMessage(subject: "Angebot", senderName: "Erika Muster", senderAddress: "erika@example.com",
                           date: Date(timeIntervalSince1970: 1_800_000_000), messageID: "abc123@mail.example.com",
                           bodyText: "Hallo Max, bitte schick mir das Angebot bis Freitag. Rückfragen an erika@example.com.")

    static var now: Date { makeTestCalendar().date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12))! }

    private func summarizer(_ responder: any ResponseStreaming? = nil) -> MailSummarizer {
        MailSummarizer(responder: responder ?? self.responder, model: { [unowned self] in modelCalls += 1; return "gpt-test" },
                       hasConsent: { [unowned self] in consent }, timeout: .seconds(30), language: { .german },
                       calendar: { makeTestCalendar() }, now: { Self.now })
    }

    private func makeModel(responder: (any ResponseStreaming)? = nil) -> MailTaskModel {
        MailTaskModel(mail: mail, summarizer: summarizer(responder), hasConsent: { [unowned self] in consent }, grantConsent: {})
    }

    /// A model with the first proposal in place.
    private func summarized() async -> MailTaskModel {
        responder.enqueue(Self.first)
        let model = makeModel()
        model.summarize()
        for _ in 0..<300 where model.phase != .idle || model.suggestedFields.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return model
    }

    private func sentText(_ index: Int) -> String {
        responder.calls[index].input.compactMap { item -> String? in if case .user(let text) = item { text } else { nil } }.joined()
    }

    private func answer(title: String = "Angebot bis Freitag senden", summary: String = "Erika bittet um das Angebot.", due: String? = "2026-11-27") -> String {
        let object: [String: Any] = ["title": title, "summary": summary, "due": due as Any? ?? NSNull()]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    // MARK: Summarizer

    @Test func revise_requiresMailConsent() async {
        consent = false
        let current = MailTaskSuggestion.Normalized(title: "A", summary: "B", due: nil)
        await #expect(throws: MailSummarizer.Failure.consentMissing) {
            _ = try await summarizer().revise(subject: "Angebot", senderName: "Erika", body: "Text", current: current, fixed: [], comment: "Kürzer")
        }
        #expect(modelCalls == 0 && responder.calls.isEmpty)
    }

    @Test func revise_sendsRedactedMailFieldsAndComment() async throws {
        responder.enqueue(answer())
        let current = MailTaskSuggestion.Normalized(title: "Angebot an erika@example.com", summary: "Rückruf unter max@example.com", due: DueDate(year: 2026, month: 11, day: 27))

        _ = try await summarizer().revise(subject: "Angebot", senderName: "Erika Muster", body: "Hallo erika@example.com, bitte das Angebot.",
                                          current: current, fixed: ["title"], comment: "Schreib an lea@example.com")

        let text = sentText(0)
        #expect(!text.contains("@example.com") && text.contains("[Adresse]"))
        #expect(text.contains("Betreff: Angebot") && text.contains("Von: Erika Muster") && text.contains("2026-11-27"))
        #expect(text.contains("Fields the user set by hand: title") && text.contains("Message from the user:"))
        #expect(responder.calls[0].schema == "mail_task" && responder.schemas[0] == MailTaskSuggestion.schema)
        #expect(responder.instructions[0].hasPrefix(MailTaskSuggestion.instructions(language: .german, today: Self.now, calendar: makeTestCalendar())))
    }

    @Test func revise_cutsTheMailLikeSummarize() async throws {
        responder.enqueue(answer())
        let body = String(repeating: "q", count: MailTaskSuggestion.maximumInputLength + 500)
        _ = try await summarizer().revise(subject: "S", senderName: nil, body: body, current: .init(title: "A", summary: "", due: nil), fixed: [], comment: "k")
        #expect(sentText(0).filter { $0 == "q" }.count == MailTaskSuggestion.maximumInputLength)
    }

    // MARK: Model

    @Test func revise_answerMarksChangedFieldsAsSuggested() async {
        let model = await summarized()
        model.confirm(.title)
        #expect(!model.suggestedFields.contains(.title))
        responder.enqueue(answer(title: "Angebot senden", summary: "Erika bittet um das Angebot.", due: "2026-11-27"))

        await model.revise("Titel kürzer")

        #expect(model.title == "Angebot senden" && model.suggestedFields.contains(.title))
        // Notes and due date were repeated: they keep their state.
        #expect(model.notes == "Erika bittet um das Angebot." && model.due == DueDate(year: 2026, month: 11, day: 27))
        #expect(model.followUpState == .ready && model.canUndoRevision)
    }

    @Test func revise_editedFields_sentAsFixed_andChangedOnlyWhenTheAnswerChangesThem() async {
        let model = await summarized()
        model.editNotes("Meine Notiz")
        responder.enqueue(answer(summary: "Meine Notiz"))

        await model.revise("Frist prüfen")

        #expect(sentText(1).contains("Fields the user set by hand: summary"))
        #expect(model.notes == "Meine Notiz" && !model.suggestedFields.contains(.notes))
        #expect(model.followUpReply == String(localized: "Keine Änderung.") && !model.canUndoRevision)
    }

    @Test func revise_answerThatChangesAnEditedField_marksItAgain() async {
        let model = await summarized()
        model.editNotes("Meine Notiz")
        responder.enqueue(answer(summary: "Kurz."))
        await model.revise("Notiz kürzer")
        #expect(model.notes == "Kurz." && model.suggestedFields.contains(.notes))
    }

    @Test func revise_aDueDateTheAnswerLeavesOut_stays() async {
        let model = await summarized()
        responder.enqueue(answer(due: nil))
        await model.revise("Anders")
        #expect(model.due == DueDate(year: 2026, month: 11, day: 27))
    }

    @Test func undo_restoresFields() async {
        let model = await summarized()
        let titleBefore = model.title
        let marksBefore = model.suggestedFields
        responder.enqueue(answer(title: "Neuer Titel", summary: "Neu.", due: "2026-12-01"))
        await model.revise("Alles anders")
        #expect(model.title == "Neuer Titel" && model.due == DueDate(year: 2026, month: 12, day: 1))

        model.undoRevision()

        #expect(model.title == titleBefore && model.notes == "Erika bittet um das Angebot." && model.due == DueDate(year: 2026, month: 11, day: 27))
        #expect(model.suggestedFields == marksBefore && !model.canUndoRevision)
    }

    @Test func undo_isDroppedByAnEditByHand() async {
        let model = await summarized()
        responder.enqueue(answer(title: "Neuer Titel"))
        await model.revise("Anders")
        #expect(model.canUndoRevision)
        model.editTitle("Mein Titel")
        #expect(!model.canUndoRevision)
    }

    @Test func revise_failure_keepsTheFields() async {
        let model = await summarized()
        let title = model.title
        responder.enqueueFailure(.network)
        await model.revise("Anders")
        #expect(model.followUpState == .failed(MailSummarizer.Failure.network.message) && model.title == title)
    }

    @Test func cancel_dropsRunningFollowUp() async {
        let model = await summarized()
        let gate = Gate()
        let slow = GatedMailResponder(answer: answer(title: "Zu spät"), gate: gate)
        let other = MailTaskModel(mail: mail, summarizer: summarizer(slow), hasConsent: { true }, grantConsent: {})
        other.editTitle("Mein Titel")
        let revising = Task { await other.revise("Anders") }
        while other.followUpState != .sending { await Task.yield() }

        other.cancel()
        gate.open()
        await revising.value

        #expect(other.title == "Mein Titel" && other.followUpState == .ready && !other.canUndoRevision)
        _ = model
    }

    @Test func withoutConsent_orWithoutText_noFollowUp() async {
        consent = false
        let model = makeModel()
        #expect(!model.canFollowUp)
        await model.revise("Kürzer")
        #expect(responder.calls.isEmpty)
    }
}

private final class GatedMailResponder: ResponseStreaming, @unchecked Sendable {
    let answer: String
    let gate: Gate
    init(answer: String, gate: Gate) { self.answer = answer; self.gate = gate }
    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await gate.wait()
                continuation.yield(.textDelta(answer))
                continuation.yield(.completed(usage: nil))
                continuation.finish()
            }
        }
    }
}

/// Gregorian calendar in Berlin, like the app's own.
private func makeTestCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}

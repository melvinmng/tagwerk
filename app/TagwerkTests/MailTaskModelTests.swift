import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// A responder whose stream never ends, for the timeout.
private final class HangingResponder: ResponseStreaming, @unchecked Sendable {
    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { _ in }
    }
}

/// All data is invented; addresses use example.com.
@MainActor
final class MailTaskModelTests {
    let responder = FakePlanResponder()
    var consent = true
    var consentGrants = 0
    var modelCalls = 0
    static let answer = #"{"title":"Angebot bis Freitag senden","summary":"Erika bittet um das Angebot.","due":"2026-11-27"}"#

    let mail = MailMessage(subject: "Angebot", senderName: "Erika Muster", senderAddress: "erika@example.com",
                           date: Date(timeIntervalSince1970: 1_800_000_000), messageID: "abc123@mail.example.com",
                           bodyText: "Hallo Max, bitte schick mir das Angebot bis Freitag, den 27.11.2026.")

    private func makeSummarizer(_ responder: any ResponseStreaming, timeout: Duration = .seconds(30)) -> MailSummarizer {
        MailSummarizer(responder: responder, model: { [unowned self] in modelCalls += 1; return "gpt-test" },
                       hasConsent: { [unowned self] in consent }, timeout: timeout, language: { .german },
                       calendar: { makeTestCalendar() }, now: { Self.now })
    }

    static var now: Date { makeTestCalendar().date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12))! }

    private func makeModel(mail: MailMessage? = nil, text: String? = nil, responder: (any ResponseStreaming)? = nil,
                           timeout: Duration = .seconds(30)) -> MailTaskModel {
        let summarizer = makeSummarizer(responder ?? self.responder, timeout: timeout)
        let hasConsent: @MainActor () -> Bool = { [unowned self] in consent }
        let grant: @MainActor () -> Void = { [unowned self] in consent = true; consentGrants += 1 }
        if let text { return MailTaskModel(text: text, summarizer: summarizer, hasConsent: hasConsent, grantConsent: grant) }
        return MailTaskModel(mail: mail ?? self.mail, summarizer: summarizer, hasConsent: hasConsent, grantConsent: grant)
    }

    /// Waits until the request of the model is done (it runs in a task).
    private func settle(_ model: MailTaskModel) async {
        for _ in 0..<200 where model.phase == .loading || model.phase == .idle && responder.calls.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<50 where model.phase == .loading { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func withoutConsent_neverCallsTheResponder() async {
        consent = false
        let model = makeModel()
        model.summarize()
        #expect(model.showsConsent)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(responder.calls.isEmpty)
        #expect(modelCalls == 0)
        // The sheet shows the subject as the title and the link back to the mail.
        #expect(model.title == "Angebot")
        #expect(model.notes.contains("message://%3Cabc123@mail.example.com%3E"))
    }

    @Test func withConsent_callsOnce() async throws {
        responder.enqueue(Self.answer)
        let model = makeModel()
        model.summarize()
        model.summarize()  // a second tap while loading changes nothing
        await settle(model)
        #expect(responder.calls.count == 1)
        #expect(model.title == "Angebot bis Freitag senden")
        #expect(model.due == DueDate(year: 2026, month: 11, day: 27))
        #expect(model.notes.hasPrefix("Erika bittet um das Angebot."))
        #expect(model.suggestedFields == [.title, .notes, .due])
        #expect(try #require(responder.calls.first).schema == "mail_task")
    }

    @Test func consentGiven_storesTheConsentAndCallsOnce() async {
        consent = false
        responder.enqueue(Self.answer)
        let model = makeModel()
        model.summarize()
        #expect(responder.calls.isEmpty)
        model.consentGiven()
        await settle(model)
        #expect(consentGrants == 1)
        #expect(!model.showsConsent)
        #expect(responder.calls.count == 1)
    }

    @Test func userEditedTitle_isNotOverwritten() async {
        responder.enqueue(Self.answer)
        let model = makeModel()
        model.editTitle("Mein Titel")
        model.summarize()
        await settle(model)
        #expect(model.title == "Mein Titel")
        #expect(!model.suggestedFields.contains(.title))
        #expect(model.suggestedFields.contains(.notes))
    }

    @Test func confirmedSuggestion_losesItsMark() async {
        responder.enqueue(Self.answer)
        let model = makeModel()
        model.summarize()
        await settle(model)
        model.confirm(.due)
        #expect(!model.suggestedFields.contains(.due))
        model.editNotes("Eigene Notiz")
        #expect(!model.suggestedFields.contains(.notes))
        #expect(model.notes == "Eigene Notiz")
    }

    @Test func invalidAnswer_showsNotRecognized() async {
        responder.enqueue("das ist kein JSON")
        let model = makeModel()
        model.summarize()
        await settle(model)
        #expect(model.phase == .failed(MailSummarizer.Failure.notRecognized.message))
        #expect(model.title == "Angebot")
    }

    @Test func emptyTitleAnswer_showsNotRecognized() async {
        responder.enqueue(#"{"title":"  ","summary":"x","due":null}"#)
        let model = makeModel()
        model.summarize()
        await settle(model)
        #expect(model.phase == .failed(MailSummarizer.Failure.notRecognized.message))
    }

    @Test func timeout_showsTimeout() async {
        let model = makeModel(responder: HangingResponder(), timeout: .milliseconds(50))
        model.summarize()
        for _ in 0..<100 where model.phase == .loading || model.phase == .idle { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(model.phase == .failed(MailSummarizer.Failure.timeout.message))
        #expect(model.canContinue)
    }

    @Test func networkFailure_showsNetwork() async {
        responder.enqueueFailure(.network)
        let model = makeModel()
        model.summarize()
        await settle(model)
        #expect(model.phase == .failed(MailSummarizer.Failure.network.message))
    }

    @Test func notesContainMailLinkWhenMessageIDPresent() {
        let model = makeModel()
        #expect(model.notes == "Von: Erika Muster\nmessage://%3Cabc123@mail.example.com%3E")
        var withoutID = mail
        withoutID.messageID = nil
        #expect(makeModel(mail: withoutID).notes == "Von: Erika Muster")
    }

    @Test func sentInput_excludesAddressesAndMessageID() async throws {
        responder.enqueue(Self.answer)
        var long = mail
        long.bodyText = "Kontakt: erika@example.com. " + String(repeating: "x", count: 13_000)
        let model = makeModel(mail: long)
        model.summarize()
        await settle(model)
        let call = try #require(responder.calls.first)
        guard case .user(let sent) = try #require(call.input.first) else {
            Issue.record("Expected a user item")
            return
        }
        #expect(sent.hasPrefix("Betreff: Angebot\nVon: Erika Muster\nText:\n"))
        #expect(!sent.contains("abc123@mail.example.com"))
        #expect(!sent.contains("message://"))
        // The sender's address is not sent as a header; the cut text is limited.
        #expect(!sent.contains("Von: Erika Muster <"))
        #expect(sent.count <= 12_000 + 80)
        #expect(responder.instructions.first == MailTaskSuggestion.instructions(language: .german, today: Self.now, calendar: makeTestCalendar()))
    }

    @Test func pastedText_usesFirstLineAsTitle() {
        let model = makeModel(text: "\n  Rechnung 4711 offen\nBitte bis Montag zahlen.")
        #expect(model.title == "Rechnung 4711 offen")
        #expect(model.mailLink == nil)
        #expect(model.notes.isEmpty)
        #expect(model.prefill == .init(title: "Rechnung 4711 offen", notes: "", due: nil))
    }

    @Test func prefill_carriesTheFieldsToTheNewTaskSheet() async {
        responder.enqueue(Self.answer)
        let model = makeModel()
        model.summarize()
        await settle(model)
        #expect(model.prefill.title == "Angebot bis Freitag senden")
        #expect(model.prefill.due == DueDate(year: 2026, month: 11, day: 27))
        #expect(model.prefill.notes.contains("message://"))
    }
}

/// Gregorian calendar in Berlin, like the app's own.
private func makeTestCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}

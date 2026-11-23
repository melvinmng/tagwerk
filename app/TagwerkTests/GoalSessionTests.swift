import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The stored form of the goal chat and the end of the session (task G7). All data is invented.
@MainActor
struct GoalSessionTests: GoalChatSuite {
    let h: GoalChatHarness

    init() throws { h = try GoalChatHarness() }

    @Test func storedHistory_containsNoValuesFromGoalData() async {
        let (model, tools, store) = await makeModel()
        openGoals(model, tools)
        responder.enqueueEvents([Self.readCall, .completed(usage: nil)])
        responder.enqueue("Ich habe deine Daten gelesen.")
        await model.send("Plane meine Ziele")
        let memory = model.conversation?.history.map { "\($0)" }.joined() ?? ""
        #expect(memory.contains("2350") && memory.contains("height_cm"), "in memory the model keeps the package")
        let stored = storedText(store)
        for value in ["82.1", "82.0", "2350", "7240", "height_cm", "1700", "112"] { #expect(!stored.contains(value), "\(value) is stored") }
        // The output is a JSON text inside the stored JSON, so its quotes are escaped.
        #expect(stored.contains(#"\"groups\""#) && stored.contains(#"\"days\":28"#))
    }

    @Test func storedForm_proposals_keepArguments() async {
        let (model, tools, store) = await makeModel()
        openGoals(model, tools)
        responder.enqueueEvents([Self.nutritionCall(), .completed(usage: nil)])
        await model.send("Plane")
        #expect(storedText(store).contains("\"kcal\":1800") || storedText(store).contains(#"\"kcal\":1800"#))
    }

    @Test func leavingChat_reloadsStoredForm_andEndsTheSession() async {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        responder.enqueueEvents([Self.readCall, .completed(usage: nil)])
        responder.enqueue("Gelesen.")
        await model.send("Plane")
        #expect(tools.session != nil)
        model.open(context: .settings)
        #expect(tools.session == nil)
        model.openGoals(session: session)
        let memory = model.conversation?.history.map { "\($0)" }.joined() ?? ""
        #expect(!memory.contains("2350") && !memory.contains("height_cm"), "the chat starts from its stored form")
    }

    @Test func revokeConsent_reducesHistoryAndEndsSelection() async {
        let (model, tools, store) = await makeModel()
        openGoals(model, tools)
        responder.enqueueEvents([Self.readCall, .completed(usage: nil)])
        responder.enqueue("Gelesen.")
        await model.send("Plane")
        #expect(model.conversation?.history.map { "\($0)" }.joined().contains("2350") == true)
        settings.goalPlanningConsent = false
        await waitUntil { tools.session == nil }
        #expect(tools.session == nil)
        let memory = model.conversation?.history.map { "\($0)" }.joined() ?? ""
        #expect(!memory.contains("2350") && !memory.contains("height_cm"))
        #expect(!storedText(store).contains("2350"))
    }

    @Test func revokeConsent_whileTurnRuns_reducesAfterTurn() async {
        let gate = TurnGate()
        let (model, tools, store) = await makeModel(responder: gate)
        openGoals(model, tools)
        gate.enqueue([Self.readCall, .completed(usage: nil)], blocked: true)
        gate.enqueue([.textDelta("Gelesen."), .completed(usage: nil)], blocked: false)
        let sending = Task { await model.send("Plane") }
        while !gate.isHolding { await Task.yield() }
        settings.goalPlanningConsent = false
        await waitUntil { tools.session == nil }
        gate.release()
        await sending.value
        let memory = model.conversation?.history.map { "\($0)" }.joined() ?? ""
        #expect(!memory.contains("2350") && !memory.contains("height_cm"), "the reduction follows when the turn ends")
        #expect(!storedText(store).contains("2350"))
    }

    // MARK: Opening

    @Test func appEnvironment_endsTheGoalSessionWithItsConsent() async throws {
        let environment = try AppEnvironment(modelContainer: h.container, notificationCenter: FakeNotificationCenter(), health: FakeHealthStore())
        let tools = try #require(environment.assistant.goalTools)
        tools.begin(session)
        #expect(environment.settings.goalPlanningConsent, "switched on by the set-up of this suite")
        environment.settings.goalPlanningConsent = false
        await waitUntil { tools.session == nil }
        #expect(tools.session == nil, "the way a backup restore or the settings withdraw the consent")
    }

    @Test func reopeningTheChat_dropsThePackageOfTheEarlierSession() async {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        responder.enqueueEvents([Self.readCall, .completed(usage: nil)])
        responder.enqueue("Gelesen.")
        await model.send("Plane")
        #expect(model.conversation?.history.map { "\($0)" }.joined().contains("height_cm") == true)
        // The sheet is only closed; the chat stays loaded. The user begins again and switches the body data off.
        model.isPresented = false
        var narrowed = session
        narrowed.package = session.package.keeping([.weight])
        model.openGoals(session: narrowed)
        responder.enqueue("Okay.")
        await model.send("Und weiter?")
        let sent = responder.calls.last?.input.map { "\($0)" }.joined() ?? ""
        #expect(!sent.contains("height_cm") && !sent.contains("2350"), "the earlier package must not go out after the user switched groups off")
        #expect(tools.session?.package.groups == [.weight])
    }

    @Test func reopeningTheChat_whileATurnRuns_keepsTheSession_andOnlyShowsTheChat() async {
        let gate = TurnGate()
        let (model, tools, _) = await makeModel(responder: gate)
        openGoals(model, tools)
        gate.enqueue([.textDelta("Hallo."), .completed(usage: nil)], blocked: true)
        let sending = Task { await model.send("Hallo") }
        while !gate.isHolding { await Task.yield() }
        model.isPresented = false
        var narrowed = session
        narrowed.package = session.package.keeping([.weight])
        model.openGoals(session: narrowed)
        #expect(model.isPresented)
        #expect(tools.session?.package.groups == session.package.groups, "the running turn belongs to the earlier session")
        gate.release()
        await sending.value
    }
}

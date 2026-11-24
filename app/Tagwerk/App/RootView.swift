import SwiftUI
import TagwerkCore

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var editingTask: TaskItem?
    @State private var openEvent: CalendarEvent?
    @State private var recurringEdit: RecurringEdit?
    @State private var shareOffer: Task<Void, Never>?
    /// "Abschließen" of the session capsule asks "Bis wohin gelesen?" in a sheet.
    @State private var endingBibleSession: BibleSessionEndModel?

    /// K1 (the separate place of the tab bar) did not hold on iOS 27: the search tab sits inside the bar.
    /// The fallback K2 puts the button top right in every tab (`AssistantButton`).
    private var tabSelection: Binding<Int> { $selectedTab }

    private var assistantPresented: Binding<Bool> {
        Binding(get: { environment.assistant.isPresented }, set: { environment.assistant.isPresented = $0 })
    }

    private var focusPresented: Binding<Bool> {
        Binding(get: { environment.focus.isPresented }, set: { environment.focus.isPresented = $0 })
    }

    private var startRequest: Binding<FocusTimerModel.StartRequest?> {
        Binding(get: { environment.focus.pendingStart }, set: { environment.focus.pendingStart = $0 })
    }

    private var routinesSheet: Binding<RoutinesModel.Sheet?> {
        Binding(get: { environment.routines.sheet }, set: { environment.routines.sheet = $0 })
    }

    private var searchPresented: Binding<Bool> {
        Binding(get: { environment.isSearchPresented }, set: { environment.isSearchPresented = $0 })
    }

    private var shareItem: Binding<ShareInboxItem?> {
        Binding(get: { environment.shareInbox.current }, set: { if $0 == nil { environment.shareInbox.dismissCurrent() } })
    }

    /// Any sheet over the tabs; shared items wait until none is open (no sheet over a sheet).
    private var hasOpenSheet: Bool {
        editingTask != nil || openEvent != nil || recurringEdit != nil || environment.routines.sheet != nil
            || environment.isSearchPresented || environment.assistant.isPresented || environment.focus.isPresented
            || environment.focus.pendingStart != nil
    }

    struct RecurringEdit: Identifiable {
        var id: String { item.id + "\(day)" }
        let item: RecurringItem
        let day: PlanDay
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Planen", systemImage: "calendar", value: 0) {
                PlanView(model: environment.planning,
                         onOpenTask: { id in
                             // The calendar behind the voice mode only scrolls; no second sheet (plan stage 2, point 17).
                             guard !environment.voiceMode.isRunning else { return }
                             editingTask = environment.taskList.items.first { $0.id == id }
                         },
                         onOpenEvent: { event in if !environment.voiceMode.isRunning { openEvent = event } },
                         onShowTask: showTask,
                         onEditRecurring: { item, day in
                             if !environment.voiceMode.isRunning { recurringEdit = RecurringEdit(item: item, day: day) }
                         })
            }

            Tab("Aufgaben", systemImage: "checklist", value: 1) {
                TaskListView(model: environment.taskList, onShowDay: showDay,
                             onEditRecurring: { item, day in recurringEdit = RecurringEdit(item: item, day: day) })
            }

            // Value 3 keeps the existing tab values (0 Planen, 1 Aufgaben, 2 Einstellungen) stable.
            Tab("Erfassen", systemImage: "plus.circle", value: 3) {
                CaptureView(model: environment.capture)
            }

            Tab("Einstellungen", systemImage: "gearshape", value: 2) {
                SettingsView()
            }

        }
        // FO5b: the running focus session sits in the accessory of the tab bar, in every tab. A running Bible Study session takes
        // the place when no focus session runs (the tab bar has one accessory; the focus timer counts down, so it wins).
        .tabViewBottomAccessory(isEnabled: environment.focus.isRunning || sessionCapsule != nil) {
            if environment.focus.isRunning {
                FocusAccessoryBar()
            } else if let session = sessionCapsule {
                BibleSessionAccessoryBar(session: session, store: environment.notes,
                                         onOpen: { environment.openBibleSessionNote(session) },
                                         onComplete: { completeBibleSession(session) })
            }
        }
        .sheet(item: $endingBibleSession) { model in
            BibleSessionEndSheet(model: model) {}
        }
        .overlay(alignment: .topLeading) {
            // UI tests only: tells them that the demo data exists. Never shown outside the UI test mode.
            if UITestMode.isActive && environment.isDemoDataReady {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: "Demo data ready"))
                    .accessibilityIdentifier(AccessibilityID.App.demoReady)
            }
        }
        .sheet(isPresented: assistantPresented) {
            ChatView(assistant: environment.assistant)
        }
        .sheet(isPresented: focusPresented) {
            FocusTimerView()
        }
        // The consent and the data sheet of the goal planning hang here, never on a row; the next step waits until a sheet has left.
        .sheet(item: Binding(get: { environment.goalPlanning.stage }, set: { if $0 == nil { environment.goalPlanning.dismissed() } }),
               onDismiss: { Task { await environment.goalPlanning.finishPresentation() } }) { stage in
            let flow = environment.goalPlanning
            switch stage {
            case .consent:
                GoalConsentSheet(onAgree: { flow.agree() }, onDecline: { flow.decline() })
            case .data(let session):
                GoalDataSheet(draft: session, initiallyOn: flow.initialSelection(for: session.package),
                              onBegin: { flow.begin(selected: $0, draft: session) }, onCancel: { flow.cancel() })
            }
        }
        .sheet(item: startRequest) { request in
            FocusStartSheet(request: request, base: environment.settings.focusTimerSettings,
                            lastMinutes: environment.settings.focusLastStartMinutes)
        }
        .sheet(isPresented: searchPresented, onDismiss: { environment.closeSearch() }) {
            if let model = environment.activeSearch {
                SearchSheet(model: model,
                            onShowDay: { day in environment.closeSearch(); showDay(day) },
                            onShowTask: { id in environment.closeSearch(); showTask(id) },
                            onShowNoteFolder: { scope in environment.closeSearch(); environment.showNotes(scope) },
                            onShowMorningDay: { day in environment.closeSearch(); environment.showMorningDay(day) })
            }
        }
        .background(KeyboardDismissalInstaller())
        // The Return key of every single-line field reads "Fertig" (#188 TA1a); fields with their own value keep it.
        .submitLabel(.done)
        .onChange(of: environment.assistant.isPresented) { _, presented in
            // The chat is its own sheet over the tabs; other sheets close first.
            if presented { editingTask = nil; openEvent = nil; recurringEdit = nil; environment.routines.sheet = nil; environment.closeSearch(); environment.focus.isPresented = false }
        }
        .onChange(of: environment.focus.isPresented) { _, presented in
            // The focus timer is a sheet over the tabs like the chat; other sheets close first.
            if presented { editingTask = nil; openEvent = nil; recurringEdit = nil; environment.routines.sheet = nil; environment.closeSearch(); environment.assistant.isPresented = false }
        }
        .onChange(of: planIsVisible) { _, visible in
            // Returning to the plan after a longer absence aligns the day view to "now" again (PL4b).
            let planning = environment.planning
            if visible { planning.planBecameVisible(at: planning.now()) } else { planning.planBecameHidden(at: planning.now()) }
        }
        .onChange(of: environment.notificationNavigator.receivedCount) { _, _ in openNotificationTarget() }
        .onChange(of: environment.router.receivedCount) { _, _ in openRouterTarget() }
        .onChange(of: environment.settings.setupCompleted) { _, _ in openRouterTarget() }
        .onOpenURL { url in if !environment.focus.open(url: url) { environment.router.open(url) } }
        // An intent may set the route before the first render; then `onChange` never fires.
        .onAppear { openRouterTarget() }
        // A tap on a cold start arrives before the tasks are there. Local tasks load within one update, so the
        // loading set may never visibly change; the items and states do.
        .onChange(of: environment.taskList.loadingSources) { _, _ in openNotificationTarget() }
        .onChange(of: environment.taskList.items) { _, _ in openNotificationTarget() }
        .onChange(of: environment.taskList.sourceStates.mapValues { String(describing: $0) }) { _, _ in openNotificationTarget() }
        .onChange(of: environment.requestedTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
            environment.requestedTab = nil
        }
        .onAppear {
            environment.assistant.tools.onPlanned = {
                environment.assistant.isPresented = false
                selectedTab = 0
            }
        }
        .sheet(item: $editingTask) { task in
            AppTaskEditorSheet(item: task, onShowDay: showDay)
        }
        .sheet(item: $openEvent) { event in
            EventEntrySheet(event: event, onShowTask: showTask)
        }
        .sheet(item: routinesSheet) { sheet in
            switch sheet {
            case .evening(let day):
                // A sheet is a hierarchy of its own: without the modifier the large text audit of "Tagesabschluss" would run in the standard size.
                EveningSheet(model: environment.routines, day: day, notes: environment.notes, isSignedIn: { environment.ai.isSignedIn },
                             isConcealed: { [environment] in environment.noteLock.isConcealed($0, in: environment.notes) })
                    .modifier(UITestAppearance())
            case .start(let day): MorningSheet(model: environment.routines, day: day, notes: environment.notes, isSignedIn: { environment.ai.isSignedIn },
                             isConcealed: { [environment] in environment.noteLock.isConcealed($0, in: environment.notes) })
            case .leftover: LeftoverSheet(planning: environment.planning, taskList: environment.taskList, onFinished: { _ in })
            case .week: WeekPlanningSheet(model: environment.makeWeekPlanningModel())
            }
        }
        .sheet(item: $recurringEdit) { edit in
            RecurringEffortSheet(item: edit.item, day: edit.day, model: environment.planning)
        }
        .sheet(item: shareItem, onDismiss: { offerSharedItems() }) { item in
            ShareImportSheet(item: item)
        }
        .onChange(of: environment.shareInbox.refreshRequests) { _, _ in offerSharedItems() }
        .onChange(of: environment.settings.setupCompleted) { _, _ in offerSharedItems() }
        .onChange(of: hasOpenSheet) { _, open in if !open { offerSharedItems() } }
        // The chat and the focus timer are sheets over the tabs; an open shared item closes first and stays in the inbox.
        .onChange(of: environment.assistant.isPresented) { _, presented in if presented { environment.shareInbox.dismissCurrent() } }
        .onChange(of: environment.focus.isPresented) { _, presented in if presented { environment.shareInbox.dismissCurrent() } }
        .onAppear { offerSharedItems() }
        .fullScreenCover(isPresented: showsSetup) {
            SetupView(model: environment.makeSetupModel(), loginModel: environment.makeGitHubLoginModel(),
                      chatGPTSignIn: ChatGPTSignInModel(ai: environment.ai)) {
                await environment.taskList.reload()
            }
        }
    }

    /// The session the capsule above the tab bar shows: the running Bible Study session, except while its note is the open page of
    /// "Aufgaben" (the bar above the text says it there).
    private var sessionCapsule: BibleStudySessionRecord? {
        guard let session = environment.notes.latestOpenSession else { return nil }
        if selectedTab == 1, environment.tasksPath.last == .note(session.noteID) { return nil }
        return session
    }

    /// "Abschließen" of the capsule: the same question as in the note and in the folder list.
    private func completeBibleSession(_ session: BibleStudySessionRecord) {
        guard let model = BibleSessionEndModel(session: session, store: environment.notes) else {
            environment.notes.completeSession(session.id)
            return
        }
        if model.asksForEnd { endingBibleSession = model } else { model.complete() }
    }

    /// "Aufgabe zeigen": the task list with the task scrolled into view and marked (design §13.8 G3).
    private func showTask(_ id: TaskID) {
        selectedTab = 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))  // let a sheet close and the tab appear first
            environment.taskList.highlight(id)
        }
    }

    /// Opens the task or day of a tapped notification once the task list can show it.
    private func openNotificationTarget() {
        guard environment.settings.setupCompleted,
              let route = environment.notificationNavigator.takeRoute(taskList: environment.taskList) else { return }
        editingTask = nil
        openEvent = nil
        recurringEdit = nil
        environment.routines.sheet = nil
        environment.closeSearch()
        environment.assistant.isPresented = false
        environment.shareInbox.dismissCurrent()
        switch route {
        case .task(let id): showTask(id)
        case .tasksTab: selectedTab = 1
        case .day(let day): showDay(day)
        }
    }

    /// Opens the target of a `tagwerk://` link or shortcut once setup is done; links only navigate.
    private func openRouterTarget() {
        guard let request = environment.router.takeRequest(setupCompleted: environment.settings.setupCompleted) else { return }
        let hadOpenSheet = editingTask != nil || openEvent != nil || recurringEdit != nil || environment.routines.sheet != nil
            || environment.isSearchPresented || environment.assistant.isPresented || environment.shareInbox.current != nil
        environment.shareInbox.dismissCurrent()
        editingTask = nil
        openEvent = nil
        recurringEdit = nil
        environment.routines.sheet = nil
        environment.closeSearch()
        environment.assistant.isPresented = false
        switch request.route {
        case .planToday: showDay(environment.planning.today)
        case .capture, .captureMeal, .captureWorkout, .review: selectedTab = 3
        case .shopping: environment.openShopping()
        case .routineStart:
            showDay(environment.planning.today)
            presentRoutine(afterSheetClosed: hadOpenSheet) { environment.routines.openStart() }
        case .routineEvening:
            showDay(environment.planning.today)
            presentRoutine(afterSheetClosed: hadOpenSheet) { environment.routines.openEvening() }
        case .routineWeek:
            showDay(environment.planning.today)
            presentRoutine(afterSheetClosed: hadOpenSheet) { environment.routines.openWeek() }
        case .notesDictate: environment.openDictatedNote()
        case .bibleStudyStart: environment.openBibleStudyStart()
        case .routineNow: break  // resolved to the start or the wrap-up by `AppRouter.takeRequest`
        }
    }

    /// Opens the next shared item once no other sheet is open. It waits for a closing sheet (like `presentRoutine`), and
    /// nothing is offered before the setup is done (checked by the model).
    private func offerSharedItems() {
        shareOffer?.cancel()
        shareOffer = Task { @MainActor in
            var delay = 350
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(delay))
                if Task.isCancelled { return }
                // Sheets owned by a tab (new task, meal, recipe, camera) close without telling this view; look again shortly.
                let isBlocked = environment.shareInbox.refresh(canPresent: !hasOpenSheet && !PresentedSheet.isShown)
                if !isBlocked { return }
                delay = 1500
            }
        }
    }

    /// SwiftUI drops a sheet that is presented in the same update in which another one is dismissed, so the routine
    /// sheet waits for the closing animation (like `showTask`) when a sheet was open.
    private func presentRoutine(afterSheetClosed: Bool, _ present: @escaping @MainActor () -> Void) {
        guard afterSheetClosed else {
            present()
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            present()
        }
    }

    /// The plan tab is selected and the app is in the foreground.
    private var planIsVisible: Bool { selectedTab == 0 && scenePhase == .active }

    private func showDay(_ day: PlanDay) {
        environment.planning.scope = .day
        environment.planning.jump(to: day)
        selectedTab = 0
    }

    private var showsSetup: Binding<Bool> {
        Binding(get: { !environment.settings.setupCompleted }, set: { _ in })
    }
}

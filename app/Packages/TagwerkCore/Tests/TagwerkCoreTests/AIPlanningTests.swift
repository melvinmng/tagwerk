import Foundation
import Testing
@testable import TagwerkCore

struct AIPlanningTests {
    let calendar = makeCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)
    let tomorrow = PlanDay(year: 2026, month: 11, day: 19)
    /// 10:00 on `today`.
    let nowMinutes = 600

    func event(_ title: String, _ startHour: Int, _ startMinute: Int = 0, to endHour: Int, _ endMinute: Int = 0,
               on day: PlanDay? = nil, busy: Bool = true, calendarID: String = "work") -> CalendarEvent {
        let day = day ?? today
        return CalendarEvent(id: title, externalID: nil, calendarID: calendarID, title: title,
                             start: instant(day.year, day.month, day.day, startHour, startMinute),
                             end: instant(day.year, day.month, day.day, endHour, endMinute),
                             isAllDay: false, url: nil, isBusy: busy, version: "1")
    }

    func planDay(_ day: PlanDay, hours: WorkHours? = WorkHours(startMinutes: 540, endMinutes: 1080),
                 lunch: Range<Int>? = 720..<780, events: [CalendarEvent] = [], blocks: [Range<Int>] = [],
                 recurring: Int = 0, planned: Int = 0, counted: [String: Int] = [:]) -> PlanInputDay {
        PlanInputDay(day: day, hours: hours, lunch: lunch, events: events, linkedEventIDs: [], deadlineCalendarIDs: [],
                     blocks: blocks, recurringMinutes: recurring, plannedMinutes: planned, bufferMinutes: 10,
                     calendar: calendar, countedTaskMinutes: counted)
    }

    func task(_ name: String, due: DueDate? = nil, minutes: Int? = 60, plannedDay: PlanDay? = nil,
              anchor: DueDate? = nil) -> PlanInputTask {
        PlanInputTask(id: "local:\(name)", source: .local, title: name, due: due, priority: nil, minutes: minutes,
                      important: false, plannedDay: plannedDay, anchor: anchor)
    }

    func input(scope: PlanScope = .day, days: [PlanInputDay]? = nil, tasks: [PlanInputTask]) -> PlanInput {
        PlanInput(scope: scope, days: days ?? [planDay(today)], tasks: tasks, today: today, nowMinutes: nowMinutes,
                  timeZoneID: "Europe/Berlin", defaultTaskMinutes: 30)
    }

    func block(_ name: String, _ start: String, _ minutes: Int = 60) -> PlanBlock {
        PlanBlock(taskId: "local:\(name)", start: start, minutes: minutes, reason: "r")
    }

    func dayOutput(_ blocks: [PlanBlock]) -> PlanOutput {
        .day(DayPlanOutput(blocks: blocks, unscheduled: [], risks: [], estimates: []))
    }

    func acceptedBlocks(_ output: PlanOutput) -> [String] {
        guard case .day(let plan) = output else { return [] }
        return plan.blocks.map(\.taskId)
    }

    func acceptedAssignments(_ output: PlanOutput) -> [String] {
        guard case .period(let plan) = output else { return [] }
        return plan.assignments.map(\.taskId)
    }

    // MARK: Day blocks

    @Test func validate_validBlock_accepted() {
        let result = validate(dayOutput([block("a", "14:00")]), input: input(tasks: [task("a")]))
        #expect(acceptedBlocks(result.accepted) == ["local:a"])
        #expect(result.violations.isEmpty)
    }

    @Test func validate_blockOverEvent_rejected() {
        let day = planDay(today, events: [event("Meeting", 14, to: 15)])
        let result = validate(dayOutput([block("a", "14:30", 30)]), input: input(days: [day], tasks: [task("a")]))
        #expect(acceptedBlocks(result.accepted).isEmpty)
        #expect(result.violations == [PlanViolation(taskId: "local:a", reason: PlanViolation.Reason.overlapsEvent)])
    }

    @Test func validate_blockInsideEventBuffer_rejected() {
        let day = planDay(today, events: [event("Meeting", 14, to: 15)])
        let result = validate(dayOutput([block("a", "15:05", 30)]), input: input(days: [day], tasks: [task("a")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.overlapsEvent])
    }

    @Test func validate_blockInFreeEvent_accepted() {
        let day = planDay(today, events: [event("Fokuszeit", 14, to: 16, busy: false)])
        let result = validate(dayOutput([block("a", "14:00")]), input: input(days: [day], tasks: [task("a")]))
        #expect(acceptedBlocks(result.accepted) == ["local:a"])
    }

    @Test func validate_blockInLunchOfThatDay_rejected() {
        let day = planDay(today, lunch: 690..<720)
        let result = validate(dayOutput([block("a", "11:00", 60)]), input: input(days: [day], tasks: [task("a")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.overlapsLunch])
    }

    @Test func validate_blockOverExistingBlock_rejected() {
        let day = planDay(today, blocks: [840..<900])
        let result = validate(dayOutput([block("a", "14:30", 30)]), input: input(days: [day], tasks: [task("a")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.overlapsBlock])
    }

    @Test func validate_twoNewBlocksOverlapping_rejectsSecond() {
        let result = validate(dayOutput([block("a", "14:00"), block("b", "14:30")]),
                              input: input(tasks: [task("a"), task("b")]))
        #expect(acceptedBlocks(result.accepted) == ["local:a"])
        #expect(result.violations == [PlanViolation(taskId: "local:b", reason: PlanViolation.Reason.overlapsBlock)])
    }

    @Test func validate_outsideWorkHours_rejected() {
        let result = validate(dayOutput([block("a", "17:30", 60)]), input: input(tasks: [task("a")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.outsideWorkHours])
    }

    @Test func validate_blockBeforeNow_rejected() {
        let result = validate(dayOutput([block("a", "09:30", 60)]), input: input(tasks: [task("a")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.inThePast])
    }

    @Test func validate_blockOnDayOff_rejected() {
        let day = planDay(today, hours: nil)
        let result = validate(dayOutput([block("a", "14:00")]), input: input(days: [day], tasks: [task("a")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.dayOff])
    }

    @Test func validate_unknownTask_rejected() {
        let result = validate(dayOutput([block("ghost", "14:00")]), input: input(tasks: [task("a")]))
        #expect(result.violations == [PlanViolation(taskId: "local:ghost", reason: PlanViolation.Reason.unknownTask)])
    }

    @Test func validate_invalidTimeOrMinutes_rejected() {
        let result = validate(dayOutput([block("a", "25:00"), block("b", "14:00", 0)]),
                              input: input(tasks: [task("a"), task("b")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.invalidTime, PlanViolation.Reason.invalidMinutes])
    }

    @Test func validate_duplicateTask_keepsFirst() {
        let result = validate(dayOutput([block("a", "14:00"), block("a", "16:00")]), input: input(tasks: [task("a")]))
        #expect(result.accepted == dayOutput([block("a", "14:00")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.duplicate])
    }

    @Test func validate_afterDue_rejected() {
        let dueToday1500 = DueDate(year: 2026, month: 11, day: 18, hour: 15, minute: 0)
        let result = validate(dayOutput([block("a", "14:30", 60), block("b", "13:00", 60)]),
                              input: input(tasks: [task("a", due: dueToday1500), task("b", due: dueToday1500)]))
        #expect(acceptedBlocks(result.accepted) == ["local:b"])
        #expect(result.violations == [PlanViolation(taskId: "local:a", reason: PlanViolation.Reason.afterDue)])
    }

    @Test func validate_dueYesterdayWithoutTime_stillAllowedToday() {
        // Overdue tasks may be planned today; only planning later than the due day is rejected in periods.
        let yesterday = DueDate(year: 2026, month: 11, day: 17)
        let result = validate(dayOutput([block("a", "14:00")]), input: input(tasks: [task("a", due: yesterday)]))
        #expect(acceptedBlocks(result.accepted) == ["local:a"])
    }

    @Test func validate_afterDeadlineAnchor_rejected() {
        let anchor = DueDate(year: 2026, month: 11, day: 18, hour: 14, minute: 0)
        let result = validate(dayOutput([block("a", "14:00")]), input: input(tasks: [task("a", anchor: anchor)]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.afterDeadline])
    }

    @Test func validate_overCapacity_rejectsLatest() {
        // 9–18 minus lunch = 480 min; 300 min recurring and 60 min planned leave 120 min.
        let day = planDay(today, recurring: 300, planned: 60)
        let result = validate(dayOutput([block("b", "16:00", 60), block("a", "14:00", 60), block("c", "11:00", 30)]),
                              input: input(days: [day], tasks: [task("a"), task("b"), task("c")]))
        #expect(Set(acceptedBlocks(result.accepted)) == ["local:a", "local:c"])
        #expect(result.violations == [PlanViolation(taskId: "local:b", reason: PlanViolation.Reason.overCapacity)])
    }

    @Test func validate_blockForTaskAlreadyPlannedThatDay_replacesItsLoad() {
        // The 60 planned minutes are task a itself; giving it a block must not count it twice.
        let day = planDay(today, recurring: 360, planned: 60, counted: ["local:a": 60])
        let result = validate(dayOutput([block("a", "14:00", 60), block("b", "16:00", 60)]),
                              input: input(days: [day], tasks: [task("a", plannedDay: today), task("b")]))
        #expect(Set(acceptedBlocks(result.accepted)) == ["local:a", "local:b"])
    }

    @Test func validate_blockForDueTodayTask_replacesItsLoad() {
        // Due today without assignment: the day counts it already (openToday), plannedDay is nil.
        let day = planDay(today, recurring: 360, planned: 30, counted: ["local:a": 30])
        let result = validate(dayOutput([block("a", "14:00", 60), block("b", "16:00", 60)]),
                              input: input(days: [day], tasks: [task("a", due: DueDate(year: 2026, month: 11, day: 18)), task("b")]))
        #expect(Set(acceptedBlocks(result.accepted)) == ["local:a", "local:b"])
    }

    @Test func validate_blockForUncountedTask_addsFullLoad() {
        // planned 60 belongs to another task; a and b need 120 of 120 free → b no longer fits.
        let day = planDay(today, recurring: 360, planned: 60)
        let result = validate(dayOutput([block("a", "14:00", 60), block("b", "16:00", 60)]),
                              input: input(days: [day], tasks: [task("a", plannedDay: today), task("b")]))
        #expect(acceptedBlocks(result.accepted) == ["local:a"])
    }

    @Test func validate_assignDueTodayTaskToToday_addsOnlyDifference() {
        // Today: 120 free, 90 planned of which 60 are task a (due today) → assigning a adds 0.
        let days = [planDay(today, recurring: 360, planned: 90, counted: ["local:a": 60]), planDay(tomorrow)]
        let result = validate(periodOutput([assign("a", "2026-11-18")]),
                              input: periodInput([task("a", due: DueDate(year: 2026, month: 11, day: 18))], days: days))
        #expect(acceptedAssignments(result.accepted) == ["local:a"])
    }

    @Test func validate_dropsUnknownEstimatesAndUnscheduled() {
        let output = PlanOutput.day(DayPlanOutput(
            blocks: [], unscheduled: [PlanUnscheduled(taskId: "local:ghost", reason: "x"), PlanUnscheduled(taskId: "local:a", reason: "voll")],
            risks: ["knapp"], estimates: [PlanEstimate(taskId: "local:a", minutes: 45), PlanEstimate(taskId: "local:ghost", minutes: 10),
                                          PlanEstimate(taskId: "local:a", minutes: 0)]))
        let result = validate(output, input: input(tasks: [task("a")]))
        #expect(result.accepted == .day(DayPlanOutput(
            blocks: [], unscheduled: [PlanUnscheduled(taskId: "local:a", reason: "voll")], risks: ["knapp"],
            estimates: [PlanEstimate(taskId: "local:a", minutes: 45)])))
    }

    // MARK: Week and month

    func periodInput(_ tasks: [PlanInputTask], days: [PlanInputDay]? = nil) -> PlanInput {
        input(scope: .week, days: days ?? [planDay(today), planDay(tomorrow), planDay(PlanDay(year: 2026, month: 11, day: 21), hours: nil)],
              tasks: tasks)
    }

    func assign(_ name: String, _ day: String) -> PlanAssignment {
        PlanAssignment(taskId: "local:\(name)", day: day, reason: "r")
    }

    func periodOutput(_ assignments: [PlanAssignment]) -> PlanOutput {
        .period(PeriodPlanOutput(assignments: assignments, unscheduled: [], risks: [], estimates: []))
    }

    @Test func validate_assignment_accepted() {
        let result = validate(periodOutput([assign("a", "2026-11-19")]), input: periodInput([task("a")]))
        #expect(acceptedAssignments(result.accepted) == ["local:a"])
    }

    @Test func validate_assignmentOnDayOff_rejected() {
        let result = validate(periodOutput([assign("a", "2026-11-21")]), input: periodInput([task("a")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.dayOff])
    }

    @Test func validate_assignmentOutsidePeriod_rejected() {
        let result = validate(periodOutput([assign("a", "2026-12-01"), assign("b", "2026-11-1x")]),
                              input: periodInput([task("a"), task("b")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.outsidePeriod, PlanViolation.Reason.invalidDay])
    }

    @Test func validate_assignmentBeforeToday_rejected() {
        let yesterday = PlanDay(year: 2026, month: 11, day: 17)
        let result = validate(periodOutput([assign("a", "2026-11-17")]),
                              input: periodInput([task("a")], days: [planDay(yesterday), planDay(today)]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.inThePast])
    }

    @Test func validate_alreadyAssigned_rejected() {
        let result = validate(periodOutput([assign("a", "2026-11-19")]), input: periodInput([task("a", plannedDay: today)]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.alreadyAssigned])
    }

    @Test func validate_assignmentAfterDue_rejected() {
        let result = validate(periodOutput([assign("a", "2026-11-19")]),
                              input: periodInput([task("a", due: DueDate(year: 2026, month: 11, day: 18))]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.afterDue])
    }

    @Test func validate_assignmentOverCapacity_rejectsLatest() {
        let days = [planDay(today), planDay(tomorrow, recurring: 360)]
        let result = validate(periodOutput([assign("a", "2026-11-19"), assign("b", "2026-11-19")]),
                              input: periodInput([task("a", minutes: 90), task("b", minutes: 60)], days: days))
        #expect(acceptedAssignments(result.accepted) == ["local:a"])
        #expect(result.violations == [PlanViolation(taskId: "local:b", reason: PlanViolation.Reason.overCapacity)])
    }

    @Test func validate_assignmentUsesModelEstimate_forCapacity() {
        // 120 min free tomorrow; without effort each task would count 30 min, the model says 90.
        let days = [planDay(today), planDay(tomorrow, recurring: 360)]
        let output = PlanOutput.period(PeriodPlanOutput(
            assignments: [assign("a", "2026-11-19"), assign("b", "2026-11-19")], unscheduled: [], risks: [],
            estimates: [PlanEstimate(taskId: "local:a", minutes: 90), PlanEstimate(taskId: "local:b", minutes: 90)]))
        let result = validate(output, input: periodInput([task("a", minutes: nil), task("b", minutes: nil)], days: days))
        #expect(acceptedAssignments(result.accepted) == ["local:a"])
        #expect(result.violations == [PlanViolation(taskId: "local:b", reason: PlanViolation.Reason.overCapacity)])
    }

    @Test func validate_wrongShapeForScope_rejectsAll() {
        let result = validate(periodOutput([assign("a", "2026-11-18")]), input: input(tasks: [task("a")]))
        #expect(acceptedAssignments(result.accepted).isEmpty)
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.wrongScope])
    }

    // MARK: Longer days and moves

    @Test func dayChange_extendsHours_andMakesRoomForLateBlock() {
        let day = planDay(today, recurring: 360, planned: 60)  // 120 free, 60 planned → 60 left
        let output = PlanOutput.day(DayPlanOutput(
            blocks: [block("a", "18:00", 90)], unscheduled: [], risks: [], estimates: [], summary: "Voll",
            dayChanges: [PlanDayChange(day: "2026-11-18", start: "09:00", end: "20:00", reason: "Frist")]))
        let result = validate(output, input: input(days: [day], tasks: [task("a")]))
        guard case .day(let plan) = result.accepted else { Issue.record("day plan expected"); return }
        #expect(plan.dayChanges.map(\.end) == ["20:00"])
        #expect(plan.blocks.map(\.taskId) == ["local:a"])
        #expect(plan.summary == "Voll")
        #expect(result.violations.isEmpty)
    }

    @Test func dayChange_outsideLimits_rejected() {
        let output = PlanOutput.day(DayPlanOutput(blocks: [], unscheduled: [], risks: [], estimates: [], dayChanges: [
            PlanDayChange(day: "2026-11-18", start: "06:00", end: "18:00", reason: "r"),
            PlanDayChange(day: "2026-11-18", start: "08:00", end: "21:30", reason: "r"),
        ]))
        let result = validate(output, input: input(tasks: [task("a")]))
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.invalidDayChange, PlanViolation.Reason.invalidDayChange])
    }

    @Test func dayChange_twelveHours_allowed_shorterHours_rejected() {
        let output = PlanOutput.day(DayPlanOutput(blocks: [], unscheduled: [], risks: [], estimates: [], dayChanges: [
            PlanDayChange(day: "2026-11-18", start: "10:00", end: "17:00", reason: "r"),
            PlanDayChange(day: "2026-11-18", start: "08:00", end: "20:00", reason: "Notfall"),
        ]))
        let result = validate(output, input: input(tasks: [task("a")]))
        guard case .day(let plan) = result.accepted else { return }
        #expect(plan.dayChanges.map(\.start) == ["08:00"])
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.notAnExtension])
    }

    @Test func move_toLaterDay_relievesToday() {
        // Today: 120 free, 120 planned (task a 60 + b 60) → nothing fits; moving a frees 60.
        var dayInput = input(days: [planDay(today, recurring: 360, planned: 120, counted: ["local:a": 60, "local:b": 60])],
                             tasks: [task("a", plannedDay: today), task("b", plannedDay: today), task("c")])
        dayInput.laterDays = [planDay(tomorrow)]
        let output = PlanOutput.day(DayPlanOutput(blocks: [block("c", "16:00", 60)], unscheduled: [], risks: [], estimates: [],
                                                  moves: [PlanMove(taskId: "local:a", day: "2026-11-19", reason: "kann warten")]))
        let result = validate(output, input: dayInput)
        guard case .day(let plan) = result.accepted else { return }
        #expect(plan.moves.map(\.taskId) == ["local:a"])
        #expect(plan.blocks.map(\.taskId) == ["local:c"])
    }

    @Test func move_rejectedWhenNotPlannedOrTargetFull() {
        var dayInput = input(days: [planDay(today)], tasks: [task("a"), task("b", plannedDay: today)])
        dayInput.laterDays = [planDay(tomorrow, recurring: 480)]
        let output = PlanOutput.day(DayPlanOutput(blocks: [], unscheduled: [], risks: [], estimates: [], moves: [
            PlanMove(taskId: "local:a", day: "2026-11-19", reason: "r"),
            PlanMove(taskId: "local:b", day: "2026-11-19", reason: "r"),
        ]))
        let result = validate(output, input: dayInput)
        #expect(result.violations.map(\.reason) == [PlanViolation.Reason.notPlannedThatDay, PlanViolation.Reason.overCapacity])
    }

    @Test func modelJSON_containsLaterDaysAndLimits() throws {
        var dayInput = input(tasks: [task("a")])
        dayInput.laterDays = [planDay(tomorrow)]
        let json = try #require(try JSONSerialization.jsonObject(with: dayInput.modelJSON()) as? [String: Any])
        #expect((json["laterDays"] as? [[String: Any]])?.first?["day"] as? String == "2026-11-19")
        let limits = try #require(json["workdayLimits"] as? [String: Any])
        #expect(limits["latestEnd"] as? String == "21:00")
        #expect(limits["emergencyMaximumHours"] as? Int == 12)
    }

    @Test func decode_oldAnswerWithoutNewFields_stillWorks() throws {
        let data = Data(#"{"blocks":[],"unscheduled":[],"risks":[],"estimates":[]}"#.utf8)
        #expect(try PlanOutput.decode(data, scope: .day) == .day(DayPlanOutput(blocks: [], unscheduled: [], risks: [], estimates: [])))
    }

    // MARK: Input

    func item(_ name: String, due: DueDate? = nil, priority: Priority? = nil, completed: Bool = false) -> TaskItem {
        var item = makeItem(name, due: due, priority: priority)
        item.isCompleted = completed
        return item
    }

    func makeInput(_ scope: PlanScope = .day, days: [PlanInputDay]? = nil, tasks: [TaskItem],
                   assignments: [TaskID: PlanDay] = [:], lookahead: Set<PlanDay> = []) -> PlanInput {
        makePlanInput(scope: scope, days: days ?? [planDay(today)], tasks: tasks, assignments: assignments, anchors: [:],
                      today: today, nowMinutes: nowMinutes, timeZoneID: "Europe/Berlin", defaultTaskMinutes: 30,
                      lookaheadDays: lookahead, calendar: calendar)
    }

    @Test func makePlanInput_day_coreFirst_overdueThenP1_thenWindow() {
        let tasks = [
            item("später", due: DueDate(year: 2026, month: 11, day: 20)),
            item("p1 ohne Datum", priority: .p1),
            item("uralt", due: DueDate(year: 2026, month: 8, day: 1)),
            item("heute", due: DueDate(year: 2026, month: 11, day: 18), priority: .p3),
        ]
        let result = makeInput(tasks: tasks)
        #expect(result.tasks.map(\.title) == ["uralt", "heute", "p1 ohne Datum", "später"])
        #expect(result.tasks.first { $0.title == "p1 ohne Datum" }?.important == true)
    }

    @Test func makePlanInput_largeEffort_entersBeforeItsDueWindow_withDailyShare() {
        // 20 h due on the 28th at P5: 4 h a day → work must start on the 24th; with 2 h already blocked
        // (18 h left) still on the 24th. A day plan on the 21st (window up to 24th) includes it.
        var big = item("Große Aufgabe", due: DueDate(year: 2026, month: 11, day: 28), priority: .p5)
        big.estimateMinutes = 20 * 60
        let result = makePlanInput(scope: .day, days: [planDay(today)], tasks: [big], assignments: [:], anchors: [:],
                                   today: PlanDay(year: 2026, month: 11, day: 21), nowMinutes: nowMinutes,
                                   timeZoneID: "Europe/Berlin", defaultTaskMinutes: 30,
                                   blockedMinutes: [big.id: 120], calendar: calendar)
        let task = try? #require(result.tasks.first)
        #expect(task?.latestStart == PlanDay(year: 2026, month: 11, day: 24))
        #expect(task?.remainingMinutes == 18 * 60)
        // 1080 min over 7 days → 155 → rounded up to 165 min today.
        #expect(task?.sessionMinutes == 165)
    }

    @Test func makePlanInput_largeEffort_farAway_staysOut() {
        var big = item("Große Aufgabe", due: DueDate(year: 2026, month: 12, day: 20), priority: .p5)
        big.estimateMinutes = 20 * 60
        let result = makeInput(tasks: [big])
        #expect(result.tasks.isEmpty)
    }

    @Test func makePlanInput_day_fillsOnlyUntilBudget() {
        // Free from 10:00: 10–12 and 13–18 = 420 min → budget 840 min; minimum 8 tasks.
        var tasks = (0..<4).map { item("kern\($0)", due: DueDate(year: 2026, month: 11, day: 19)) }
        tasks += (0..<30).map { i in
            var task = item("vorarbeit\(i)", due: DueDate(year: 2026, month: 11, day: 23))
            task.estimateMinutes = 120
            return task
        }
        let result = makeInput(tasks: tasks)
        // 4 core × 30 = 120, then 120-minute tasks until 840 is reached: 6 of them (120 + 720 = 840).
        #expect(result.tasks.filter { $0.title.hasPrefix("kern") }.count == 4)
        #expect(result.tasks.filter { $0.title.hasPrefix("vorarbeit") }.count == 6)
    }

    @Test func makePlanInput_day_workAheadFromNextDays() {
        let next = item("morgen geplant")
        let result = makeInput(tasks: [next], assignments: [next.id: tomorrow], lookahead: [tomorrow])
        #expect(result.tasks.map(\.title) == ["morgen geplant"])
        #expect(result.tasks.first?.plannedDay == tomorrow)
    }

    @Test func makePlanInput_maximum_cutsCoreAndCountsOmitted() {
        let tasks = (0..<30).map { item("überfällig\($0)", due: DueDate(year: 2026, month: 11, day: 1 + $0 % 17)) }
        let result = makeInput(tasks: tasks)
        #expect(result.tasks.count == 25)
        #expect(result.omittedCount == 5)
    }

    @Test func makePlanInput_week_movableFromOverbookedDay() {
        let full = item("voll")
        let calm = item("ruhig")
        let days = [planDay(today, recurring: 470, planned: 60), planDay(tomorrow)]
        let result = makeInput(.week, days: days, tasks: [full, calm],
                               assignments: [full.id: today, calm.id: tomorrow])
        #expect(result.tasks.map(\.title) == ["voll"])
        #expect(result.tasks.first?.plannedDay == today)
    }

    @Test func makePlanInput_week_excludesAssigned_andCompleted() {
        let a = item("a"), b = item("b"), done = item("done", completed: true)
        let result = makePlanInput(scope: .week, days: [planDay(today)], tasks: [a, b, done],
                                   assignments: [a.id: tomorrow], anchors: [:], today: today, nowMinutes: nowMinutes,
                                   timeZoneID: "Europe/Berlin", defaultTaskMinutes: 30)
        #expect(result.tasks.map(\.title) == ["b"])
    }

    @Test func makePlanInput_day_selectsAssignedDueAndImportant() {
        let assigned = item("assigned")
        let dueToday = item("dueToday", due: DueDate(year: 2026, month: 11, day: 18))
        let overdue = item("overdue", due: DueDate(year: 2026, month: 11, day: 10))
        let important = item("important", due: DueDate(year: 2026, month: 11, day: 25), priority: .p1)
        let later = item("later", due: DueDate(year: 2026, month: 11, day: 25))
        let otherDay = item("otherDay")
        let result = makePlanInput(scope: .day, days: [planDay(today)],
                                   tasks: [assigned, dueToday, overdue, important, later, otherDay],
                                   assignments: [assigned.id: today, otherDay.id: tomorrow], anchors: [:],
                                   today: today, nowMinutes: nowMinutes, timeZoneID: "Europe/Berlin", defaultTaskMinutes: 30)
        #expect(Set(result.tasks.map(\.title)) == ["assigned", "dueToday", "overdue", "important"])
        #expect(result.tasks.first { $0.title == "important" }?.important == true)
        #expect(result.tasks.first { $0.title == "assigned" }?.plannedDay == today)
        #expect(result.tasks.first { $0.title == "assigned" }?.id == "local:assigned")
    }

    @Test func makePlanInput_excludesRecurringReminders() {
        let recurring = item("recurring", due: DueDate(year: 2026, month: 11, day: 18))
        let normal = item("normal", due: DueDate(year: 2026, month: 11, day: 18))
        let result = makePlanInput(scope: .day, days: [planDay(today)], tasks: [recurring, normal], assignments: [:],
                                   anchors: [:], today: today, nowMinutes: nowMinutes, timeZoneID: "Europe/Berlin",
                                   defaultTaskMinutes: 30, excluding: [recurring.id])
        #expect(result.tasks.map(\.title) == ["normal"])
    }

    @Test func makePlanInput_focusTask_onlyThatTask() {
        let a = item("a"), b = item("b")
        let result = makePlanInput(scope: .week, days: [planDay(today)], tasks: [a, b], assignments: [:], anchors: [:],
                                   today: today, nowMinutes: nowMinutes, timeZoneID: "Europe/Berlin",
                                   defaultTaskMinutes: 30, only: [b.id])
        #expect(result.tasks.map(\.title) == ["b"])
    }

    @Test func makePlanInput_epicDueBecomesAnchor() {
        var sub = makeItem("sub", source: .github)
        sub.epic = EpicInfo(id: "E", number: 2, title: "Epic", due: DueDate(year: 2026, month: 11, day: 20), isEpic: true)
        let result = makePlanInput(scope: .week, days: [planDay(today)], tasks: [sub], assignments: [:], anchors: [:],
                                   today: today, nowMinutes: nowMinutes, timeZoneID: "Europe/Berlin", defaultTaskMinutes: 30)
        #expect(result.tasks.first?.anchor == DueDate(year: 2026, month: 11, day: 20))
        #expect(result.tasks.first?.important == true)
    }

    @Test func planInputDay_linkedEventCountsNotAsBusy() {
        let day = PlanInputDay(day: today, hours: WorkHours(startMinutes: 540, endMinutes: 1080), lunch: nil,
                               events: [event("Linked", 14, to: 15), event("Other", 16, to: 17)],
                               linkedEventIDs: ["Linked"], deadlineCalendarIDs: [], blocks: [], recurringMinutes: 0,
                               plannedMinutes: 0, bufferMinutes: 0, calendar: calendar)
        #expect(day.busy == [960..<1020])
        #expect(day.availableMinutes == 480)
    }

    @Test func modelJSON_usesReadableStrings() throws {
        let day = planDay(today, events: [event("Meeting", 14, to: 15, calendarID: "deadlines")])
        var withDeadline = day
        withDeadline.events[0].deadline = true
        let json = try #require(try JSONSerialization.jsonObject(
            with: input(days: [withDeadline], tasks: [task("a", due: DueDate(year: 2026, month: 11, day: 20))]).modelJSON()
        ) as? [String: Any])
        #expect(json["now"] as? String == "2026-11-18T10:00")
        #expect(json["timeZone"] as? String == "Europe/Berlin")
        let firstDay = try #require((json["days"] as? [[String: Any]])?.first)
        #expect(firstDay["day"] as? String == "2026-11-18")
        #expect(firstDay["workStart"] as? String == "09:00")
        #expect(firstDay["workEnd"] as? String == "18:00")
        let events = try #require(firstDay["events"] as? [[String: Any]])
        #expect(events.first?["start"] as? String == "14:00")
        #expect(events.first?["deadline"] as? Bool == true)
        let firstTask = try #require((json["tasks"] as? [[String: Any]])?.first)
        #expect(firstTask["due"] as? String == "2026-11-20")
        #expect(firstTask["id"] as? String == "local:a")
    }

    // MARK: Schemas and decoding

    @Test func schemas_areStrictAndParse() throws {
        for schema in [AIPlanSchemas.dayPlanSchema, AIPlanSchemas.periodPlanSchema] {
            let json = try #require(try JSONSerialization.jsonObject(with: schema) as? [String: Any])
            try assertStrict(json)
        }
    }

    private func assertStrict(_ node: [String: Any]) throws {
        if node["type"] as? String == "object" {
            let properties = try #require(node["properties"] as? [String: Any])
            #expect(node["additionalProperties"] as? Bool == false)
            #expect(Set(node["required"] as? [String] ?? []) == Set(properties.keys))
            for case let child as [String: Any] in properties.values { try assertStrict(child) }
        }
        if let items = node["items"] as? [String: Any] { try assertStrict(items) }
    }

    @Test func decode_dayOutput() throws {
        let data = Data(#"{"blocks":[{"taskId":"local:a","start":"14:00","minutes":60,"reason":"r"}],"unscheduled":[],"risks":["knapp"],"estimates":[{"taskId":"local:a","minutes":60}]}"#.utf8)
        #expect(try PlanOutput.decode(data, scope: .day) == .day(DayPlanOutput(
            blocks: [block("a", "14:00")], unscheduled: [], risks: ["knapp"], estimates: [PlanEstimate(taskId: "local:a", minutes: 60)])))
    }

    @Test func decode_periodOutput() throws {
        let data = Data(#"{"assignments":[{"taskId":"local:a","day":"2026-11-19","reason":"r"}],"unscheduled":[],"risks":[],"estimates":[]}"#.utf8)
        #expect(try PlanOutput.decode(data, scope: .month) == periodOutput([assign("a", "2026-11-19")]))
    }
}

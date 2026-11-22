import RemindersKit
import SwiftUI
import TagwerkCore

/// "Planen" settings: working hours per weekday, plan calendar, deadline calendars, default duration.
struct PlanningSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var calendars: [ListInfo] = []
    @State private var calendarError: String?

    /// Calendar weekday numbers (1 = Sunday) with their names, in the order of the app calendar (Monday first).
    private static var weekdays: [(Int, String)] {
        let calendar = Calendar.tagwerk
        let names = DateText.fullWeekdaySymbols(calendar: calendar)
        return names.enumerated().map { index, name in ((calendar.firstWeekday - 1 + index) % 7 + 1, name) }
    }

    var body: some View {
        @Bindable var settings = environment.settings
        Section {
            NavigationLink("Arbeitszeit je Wochentag") { weekScheduleEditor }
            planCalendarRow
            NavigationLink {
                SourceSelectionView(title: "Deadline-Kalender", items: calendars, defaultSelection: [],
                                    selection: $settings.deadlineCalendarIDs)
            } label: {
                LabeledContent("Deadline-Kalender", value: deadlineSummary)
            }
            ValueStepper("Standarddauer", value: $settings.defaultTaskMinutes, in: 15...240, step: 15, kind: .durationMinutes,
                         unit: "min", display: CapacityText.duration)
            NavigationLink {
                TravelSettingsView()
            } label: {
                LabeledContent("Fahrzeit", value: TravelText.settingsSummary(
                    enabled: settings.travelTimeEnabled, transport: settings.travelTransport, hasHome: settings.homePlace != nil))
            }
            Toggle("Termine zusammenfassen (mit Rückfrage)", isOn: $settings.mergeDuplicateEvents)
            NavigationLink("Zusammenfassen-Regeln") { MergeRulesView(model: environment.planning) }
            Button("Zusammenfassungen zurücksetzen") { Task { await environment.planning.resetMergeDecisions() } }
            NavigationLink("Kalender-Diagnose") { CalendarDiagnosticsView(model: environment.planning) }
        } header: {
            Text("Planen")
        } footer: {
            Text("Termine aus Deadline-Kalendern (z. B. Klausuren) gelten als wichtige Deadlines. Einzelne Termine aus anderen Kalendern lassen sich im Termin-Blatt als Deadline markieren; die Markierung liegt nur in Tagwerk auf diesem Gerät, der Kalender bleibt unverändert. Aufgaben ohne Aufwand zählen mit der Standarddauer. Gleiche Termine in mehreren Kalendern fasst Tagwerk erst nach deiner Zustimmung zusammen.")
        }
        .task { calendars = environment.gateway.calendarAccessState == .fullAccess ? environment.gateway.calendars() : [] }
        .onChange(of: settings.deadlineCalendarIDs) { _, _ in Task { await environment.planning.reload() } }
        .onChange(of: settings.mergeDuplicateEvents) { _, _ in Task { await environment.planning.reload() } }
    }

    @ViewBuilder private var planCalendarRow: some View {
        @Bindable var settings = environment.settings
        let writable = calendars.filter { environment.gateway.planCalendar(id: $0.id) != nil }
        if environment.gateway.planCalendar(id: settings.planCalendarID) == nil {
            Button("Plan-Kalender „Tagwerk“ anlegen") {
                do {
                    settings.planCalendarID = try environment.gateway.createPlanCalendar(named: "Tagwerk").id
                    calendars = environment.gateway.calendars()
                } catch {
                    calendarError = TaskListModel.message(for: error)
                }
            }
            if let calendarError { Text(calendarError).font(.caption).foregroundStyle(.redText) }
        }
        Picker("Plan-Kalender", selection: $settings.planCalendarID) {
            Text("Keiner").tag(String?.none)
            ForEach(writable) { Text($0.title).tag(Optional($0.id)) }
        }
    }

    private var weekScheduleEditor: some View {
        Form {
            ForEach(Self.weekdays, id: \.0) { weekday, name in
                WeekdayHoursRow(name: name, hours: hoursBinding(weekday))
            }
        }
        .navigationTitle("Arbeitszeit")
    }

    private func hoursBinding(_ weekday: Int) -> Binding<WorkHours?> {
        Binding(
            get: { environment.settings.weekSchedule.hoursByWeekday[weekday] },
            set: { value in
                var schedule = environment.settings.weekSchedule
                schedule.hoursByWeekday[weekday] = value
                environment.settings.weekSchedule = schedule
                Task { await environment.planning.reload() }
            }
        )
    }

    private var deadlineSummary: String {
        let count = environment.settings.deadlineCalendarIDs?.count ?? 0
        return count == 0 ? String(localized: "Keine") : "\(count)"
    }
}

/// One weekday: working or free, with start and end.
private struct WeekdayHoursRow: View {
    let name: String
    @Binding var hours: WorkHours?

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(name, isOn: Binding(
                get: { hours != nil },
                set: { hours = $0 ? WorkHours(startMinutes: 540, endMinutes: 1080) : nil }
            ))
            if let current = hours {
                HStack {
                    DatePicker("Beginn", selection: time(current.startMinutes) { hours?.startMinutes = $0 }, displayedComponents: .hourAndMinute)
                    DatePicker("Ende", selection: time(current.endMinutes) { hours?.endMinutes = $0 }, displayedComponents: .hourAndMinute)
                }
                .labelsHidden()
            }
        }
    }

    private func time(_ minutes: Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        let calendar = Calendar.tagwerk
        return Binding(
            get: { calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                set((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
        )
    }
}

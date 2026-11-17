import RemindersKit
import SwiftUI
import TagwerkCore

/// "Planen" settings: working hours per weekday, plan calendar, deadline calendars, default duration.
struct PlanningSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var calendars: [ListInfo] = []
    @State private var calendarError: String?

    private static let weekdays: [(Int, String)] = [(2, "Montag"), (3, "Dienstag"), (4, "Mittwoch"), (5, "Donnerstag"),
                                                    (6, "Freitag"), (7, "Samstag"), (1, "Sonntag")]

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
            Stepper("Standarddauer: \(CapacityText.duration(settings.defaultTaskMinutes))",
                    value: $settings.defaultTaskMinutes, in: 15...240, step: 15)
        } header: {
            Text("Planen")
        } footer: {
            Text("Termine aus Deadline-Kalendern (z. B. Klausuren) gelten als wichtige Deadlines. Aufgaben ohne Aufwand zählen mit der Standarddauer.")
        }
        .task { calendars = environment.gateway.calendarAccessState == .fullAccess ? environment.gateway.calendars() : [] }
        .onChange(of: settings.deadlineCalendarIDs) { _, _ in Task { await environment.planning.reload() } }
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
            if let calendarError { Text(calendarError).font(.caption).foregroundStyle(.red) }
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
        return count == 0 ? "Keine" : "\(count)"
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

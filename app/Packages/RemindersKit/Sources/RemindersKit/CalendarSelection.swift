/// Default choice of calendars: subscribed calendars (including holidays) and birthdays are off.
public enum CalendarSelection {
    public static func defaultSelected(_ calendars: [ListInfo]) -> Set<String> {
        Set(calendars.filter { $0.kind != .subscription && $0.kind != .birthday }.map(\.id))
    }
}

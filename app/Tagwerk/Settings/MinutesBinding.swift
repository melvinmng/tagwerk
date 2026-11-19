import SwiftUI

extension Binding where Value == Int {
    /// Bridges "minutes since midnight" to a `Date` for time pickers; only hour and minute of the date count.
    func asTime(calendar: Calendar = .tagwerk) -> Binding<Date> {
        Binding<Date>(
            get: { calendar.date(bySettingHour: wrappedValue / 60, minute: wrappedValue % 60, second: 0, of: .now) ?? .now },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

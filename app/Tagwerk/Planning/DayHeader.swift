import SwiftUI
import TagwerkCore

/// Head of day, week and month (mockup A1): relative caption, large title that opens a month picker, arrows.
struct DayHeader: View {
    @Bindable var model: PlanningModel
    let onShowMonth: () -> Void
    @State private var picking = false
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                Spacer()
                if !isCurrent {
                    Button("Heute") { model.anchor = model.today }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Button { picking = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title).font(.title.bold()).lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Datum wählen")
                .popover(isPresented: $picking) {
                    DatePickerPopover(model: model, onShowMonth: model.scope == .month ? nil : {
                        picking = false
                        onShowMonth()
                    }, onDone: { picking = false })
                }
                Spacer()
                HStack(spacing: 4) {
                    Button { model.step(-1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                        .accessibilityLabel(previousLabel)
                    Button { model.step(1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
                        .accessibilityLabel(nextLabel)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
            }
            if let line = intakeLine {
                Button { environment.router.open(.capture) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text(line).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Öffnet Erfassen")
            }
        }
    }

    /// Phase 4 (mockup P1a): only in today's day view, from the first entry of the day.
    private var intakeLine: String? {
        guard model.scope == .day, model.anchor == model.today else { return nil }
        return environment.capture.planHeaderLine
    }

    /// The shown period contains today.
    private var isCurrent: Bool { model.range.contains(model.today) && (model.scope != .month || model.anchor.month == model.today.month) }

    private var previousLabel: String {
        switch model.scope {
        case .day: String(localized: "Vorheriger Tag")
        case .week: String(localized: "Vorherige Woche")
        case .month: String(localized: "Vorheriger Monat")
        }
    }

    private var nextLabel: String {
        switch model.scope {
        case .day: String(localized: "Nächster Tag")
        case .week: String(localized: "Nächste Woche")
        case .month: String(localized: "Nächster Monat")
        }
    }

    private var title: String {
        let start = model.anchor.startDate(in: model.calendar)
        switch model.scope {
        case .day:
            return start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        case .week:
            // The interval style orders day and month as the language does: "16.–22. Nov." / "Nov 16 – 22".
            let range = model.range
            let first = range.lowerBound.startDate(in: model.calendar), last = range.upperBound.startDate(in: model.calendar)
            return (first..<last).formatted(.interval.day().month(.abbreviated))
        case .month:
            return start.formatted(.dateTime.month(.wide))
        }
    }

    /// Day: "HEUTE · KW 47"; week: "DIESE WOCHE · KW 47"; month: "DIESER MONAT · 2026".
    private var caption: String {
        let week = model.calendar.component(.weekOfYear, from: model.anchor.startDate(in: model.calendar))
        switch model.scope {
        case .day: return dayCaption
        case .week:
            return (isCurrent ? String(localized: "Diese Woche · KW \(week)") : String(localized: "KW \(week)")).uppercased()
        case .month:
            let year = String(model.anchor.year)
            return (isCurrent ? String(localized: "Dieser Monat · \(year)") : year).uppercased()
        }
    }

    /// "HEUTE · KW 47", "MORGEN · KW 47", "VOR 3 TAGEN · KW 46".
    private var dayCaption: String {
        let distance = model.calendar.dateComponents([.day], from: model.today.startDate(in: model.calendar),
                                                     to: model.anchor.startDate(in: model.calendar)).day ?? 0
        let relative: String = switch distance {
        case 0: String(localized: "Heute")
        case 1: String(localized: "Morgen")
        case -1: String(localized: "Gestern")
        case let days where days > 1: String(localized: "In \(days) Tagen")
        default: String(localized: "Vor \(-distance) Tagen")
        }
        let week = model.calendar.component(.weekOfYear, from: model.anchor.startDate(in: model.calendar))
        return "\(relative) · \(String(localized: "KW \(week)"))".uppercased()
    }
}

/// Month calendar to jump to a day (mockup A1, date tapped).
struct DatePickerPopover: View {
    @Bindable var model: PlanningModel
    let onShowMonth: (() -> Void)?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            DatePicker("Datum", selection: date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, model.calendar)
            HStack {
                Button("Heute") {
                    model.anchor = model.today
                    onDone()
                }
                Spacer()
                if let onShowMonth { Button("Monatsansicht ›", action: onShowMonth) }
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
        .frame(minWidth: 320)
        .presentationCompactAdaptation(.popover)
    }

    private var date: Binding<Date> {
        Binding(get: { model.anchor.startDate(in: model.calendar) },
                set: { newValue in
                    model.anchor = PlanDay(date: newValue, calendar: model.calendar)
                    onDone()
                })
    }
}

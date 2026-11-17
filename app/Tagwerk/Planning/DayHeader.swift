import SwiftUI
import TagwerkCore

/// Head of the day view (mockup A1): relative caption, large date that opens a month picker, arrows.
struct DayHeader: View {
    @Bindable var model: PlanningModel
    let onShowMonth: () -> Void
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.anchor == model.today ? Color.accentColor : .secondary)
                Spacer()
                if model.anchor != model.today {
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
                    DatePickerPopover(model: model, onShowMonth: {
                        picking = false
                        onShowMonth()
                    }, onDone: { picking = false })
                }
                Spacer()
                HStack(spacing: 4) {
                    Button { model.step(-1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                        .accessibilityLabel("Vorheriger Tag")
                    Button { model.step(1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
                        .accessibilityLabel("Nächster Tag")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
            }
        }
    }

    private var title: String {
        model.anchor.startDate(in: model.calendar).formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    /// "HEUTE · KW 47", "MORGEN · KW 47", "VOR 3 TAGEN · KW 46".
    private var caption: String {
        let distance = model.calendar.dateComponents([.day], from: model.today.startDate(in: model.calendar),
                                                     to: model.anchor.startDate(in: model.calendar)).day ?? 0
        let relative: String = switch distance {
        case 0: "Heute"
        case 1: "Morgen"
        case -1: "Gestern"
        case let days where days > 1: "In \(days) Tagen"
        default: "Vor \(-distance) Tagen"
        }
        let week = model.calendar.component(.weekOfYear, from: model.anchor.startDate(in: model.calendar))
        return "\(relative) · KW \(week)".uppercased()
    }
}

/// Month calendar to jump to a day (mockup A1, date tapped).
struct DatePickerPopover: View {
    @Bindable var model: PlanningModel
    let onShowMonth: () -> Void
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
                Button("Monatsansicht ›", action: onShowMonth)
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

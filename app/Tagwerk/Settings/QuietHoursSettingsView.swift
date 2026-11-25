import SwiftUI
import TagwerkCore

/// Einstellungen › Benachrichtigungen › Ruhezeiten (plan g1, RH1b): task and deadline notifications that fall into the
/// window move to its end. A 24-hour bar shows the window; two lists say what is held back and what always comes.
struct QuietHoursSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Right side of the row in the settings list: "Aus" or "23:00–07:00".
    static func summary(_ settings: AppSettings) -> String {
        guard let window = settings.quietHours else { return String(localized: "Aus") }
        let start = DateText.time(minutes: window.startMinutes, calendar: .tagwerk)
        let end = DateText.time(minutes: window.endMinutes, calendar: .tagwerk)
        return "\(start)–\(end)"
    }

    var body: some View {
        @Bindable var settings = environment.settings
        let window = settings.quietHours
        Form {
            Section {
                Toggle("Ruhezeiten", isOn: $settings.quietHoursEnabled)
                if settings.quietHoursEnabled {
                    Picker("Beginn", selection: $settings.quietHoursStartsAtBedtime) {
                        Text("Zielschlafzeit · \(DateText.time(minutes: settings.bedtimeMinutes, calendar: .tagwerk))").tag(true)
                        Text("Eigene Uhrzeit").tag(false)
                    }
                    if !settings.quietHoursStartsAtBedtime {
                        DatePicker("Uhrzeit", selection: $settings.quietStartMinutes.asTime(), displayedComponents: .hourAndMinute)
                    }
                    DatePicker("Ende", selection: $settings.quietEndMinutes.asTime(), displayedComponents: .hourAndMinute)
                }
            } footer: {
                if settings.quietHoursEnabled, settings.quietHoursStartsAtBedtime {
                    Text("Die Zielschlafzeit stellst du unter Routinen ein.").foregroundStyle(.secondaryText)
                }
            }

            if let window {
                Section {
                    QuietHoursBar(window: window)
                    Text("In dieser Zeit hält Tagwerk Mitteilungen zurück. Sie kommen um \(DateText.time(minutes: window.endMinutes, calendar: .tagwerk)), nichts entfällt.")
                }
                Section {
                    Text("Aufgaben und Deadline-Termine")
                } header: {
                    Text("Wird zurückgehalten")
                        .foregroundStyle(.secondaryText)
                }
                Section {
                    Text("Routinen (Tagesstart, Abend-Checkliste)")
                    Text("Fokus-Timer: Phasenende")
                    LabeledContent {
                        Text(verbatim: "Apple")
                            .font(.caption)
                            .foregroundStyle(.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(.secondary))
                    } label: {
                        Text("Hinweise aus Kalender und Erinnerungen")
                    }
                } header: {
                    Text("Kommt immer")
                        .foregroundStyle(.secondaryText)
                }
            }

            Section {
                NavigationLink {
                    FocusFilterGuideView()
                } label: {
                    LabeledContent("Bei iOS-Fokus zurückhalten",
                                   value: settings.focusQuietSince == nil ? String(localized: "Einrichten") : String(localized: "Aktiv"))
                }
            } header: {
                Text("Fokus-Filter")
                    .foregroundStyle(.secondaryText)
            } footer: {
                Text("Hält Mitteilungen auch während eines iOS-Fokus zurück, zum Beispiel „Arbeiten“.")
                    .foregroundStyle(.secondaryText)
            }
        }
        .navigationTitle("Ruhezeiten")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A 24-hour bar with ticks at 0, 6, 12, 18 and 24 and the quiet window filled. One VoiceOver element that names the window.
struct QuietHoursBar: View {
    let window: QuietHours

    private static let tickHours = [0, 6, 12, 18, 24]

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    ForEach(Array(window.dayFractions.enumerated()), id: \.offset) { _, part in
                        Rectangle()
                            .fill(.tint)
                            .frame(width: max((part.upperBound - part.lowerBound) * proxy.size.width, 2))
                            .offset(x: part.lowerBound * proxy.size.width)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 14)
            FractionalRow(fractions: Self.tickHours.map { Double($0) / 24 }) {
                ForEach(Self.tickHours, id: \.self) { hour in
                    Text(verbatim: String(hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondaryText)
                }
            }
        }
        // Time runs from left to right in every language.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Ruhezeit von \(DateText.time(minutes: window.startMinutes, calendar: .tagwerk)) bis \(DateText.time(minutes: window.endMinutes, calendar: .tagwerk))"))
    }
}

/// Places each subview with its horizontal centre at a fraction of the width (the first and the last one stay inside the
/// edges). The height is the tallest subview, so the labels follow Dynamic Type.
private struct FractionalRow: Layout {
    let fractions: [Double]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, fraction) in zip(subviews, fractions) {
            let size = subview.sizeThatFits(.unspecified)
            let center = bounds.minX + fraction * bounds.width
            let x = min(max(center - size.width / 2, bounds.minX), bounds.maxX - size.width)
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: .unspecified)
        }
    }
}

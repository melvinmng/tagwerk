import Foundation
import SwiftUI
import Testing
import TagwerkCore
@testable import Tagwerk

/// The date title of the plan header next to the bar buttons (PL16b): it takes the longest form that fits and never touches
/// the buttons, in German and English at Standard, XXXL and AX1. Replaces `PlanHeaderLayoutUITests`, which launched the app
/// six times for the same check.
///
/// What is rendered here is the title as the header builds it (`PageTitleLabel`, hosted with `ImageRenderer`); what is not rendered
/// is the system navigation bar. Its geometry is taken from the measurements of the real bar that the UI test printed (the lines
/// "HEADER ..." of PL16b, iPhone 17e, 18 Pro and 18 Pro Max) and is written down in `RealBar`. If the bar changes (a new
/// iOS version, a fourth button), measure it again with `PlanHeaderLayoutUITests/testTitleNeverTouchesTheBarButtons`, which stays in
/// the nightly run for this reason, and update `RealBar`.
@MainActor
struct PlanHeaderLayoutTests {
    /// Geometry of the real navigation bar, measured with the UI test.
    private enum RealBar {
        /// Distance of the first trailing bar button from the trailing edge: up to 173 pt at the default text size, up to 185 pt above it.
        static func trailingButtonsWidth(_ size: DynamicTypeSize) -> CGFloat { size > .large ? 185 : 173 }
        /// The title starts 16 to 20 pt from the leading edge.
        static let leadingMargin: CGFloat = 20
        /// Smallest distance the title may come to the first bar button.
        static let minimumGap: CGFloat = 8
        /// The bar stops growing the text of its items early: the title is as wide at XXXL and at the accessibility sizes as at XXL.
        static let largestTextSize = DynamicTypeSize.xxLarge
        /// Window widths of the iPhone 17e, 18 Pro and 18 Pro Max.
        static let windowWidths: [CGFloat] = [390, 402, 440]
    }

    private enum Language: CaseIterable {
        case german, english

        var locale: Locale { Locale(identifier: self == .german ? "de_DE" : "en_US") }
    }

    private let calendar = Calendar.tagwerk
    /// A Saturday: five days on from it cover the longest weekday names (Wednesday, Thursday), as in the UI test.
    private let today = PlanDay(year: 2026, month: 11, day: 21)

    /// What the header shows for one day, week or month: the anchor, its range and the day that counts as "today".
    private struct Sample {
        let scope: PlanScope
        let anchor: PlanDay
        let range: ClosedRange<PlanDay>
    }

    private var samples: [Sample] {
        var result: [Sample] = []
        for offset in 0...6 {
            let day = today.adding(days: offset, calendar: calendar)
            result.append(Sample(scope: .day, anchor: day, range: day...day))
        }
        for offset in 0..<5 {
            let first = today.adding(days: -5 + 7 * offset, calendar: calendar)
            result.append(Sample(scope: .week, anchor: first, range: first...first.adding(days: 6, calendar: calendar)))
        }
        // Every month name of the year, including the longest ones.
        for month in 1...12 {
            let first = PlanDay(year: 2026, month: month, day: 1)
            result.append(Sample(scope: .month, anchor: first, range: first...first))
        }
        return result
    }

    /// The caption above the title in the language of the test: the German one from the header code, the English one from the same
    /// catalog entries (the header code has no language parameter, and a test run is German).
    private func caption(_ sample: Sample, _ language: Language) -> String {
        let german = PlanHeaderText.caption(scope: sample.scope, anchor: sample.anchor, today: today, range: sample.range, calendar: calendar)
        guard language == .english else { return german }
        let week = calendar.component(.weekOfYear, from: sample.anchor.startDate(in: calendar))
        func english(_ key: String.LocalizationValue) -> String { Localized.string(key, in: .english, bundle: .main) }
        switch sample.scope {
        case .day:
            let days = calendar.dateComponents([.day], from: today.startDate(in: calendar), to: sample.anchor.startDate(in: calendar)).day ?? 0
            let relative = switch days {
            case 0: english("Heute")
            case 1: english("Morgen")
            default: english("In \(days) Tagen")
            }
            return "\(relative) · \(english("KW \(week)"))".uppercased()
        case .week:
            return english("KW \(week)").uppercased()
        case .month:
            return String(sample.anchor.year)
        }
    }

    /// Width of the header button (caption, title and chevron) at the text size the bar uses.
    private func renderedWidth(caption: String, title: String, isCurrent: Bool, size: DynamicTypeSize) -> CGFloat {
        let label = PageTitleLabel(caption: caption, title: title, isCurrent: isCurrent, titleScales: false)
            .fixedSize()
            .environment(\.dynamicTypeSize, min(size, RealBar.largestTextSize))
        return ImageRenderer(content: label).uiImage?.size.width ?? .infinity
    }

    @Test(arguments: Language.allCases, [DynamicTypeSize.large, .xxxLarge, .accessibility1])
    private func title_neverTouchesTheBarButtons(language: Language, size: DynamicTypeSize) {
        var checked = 0
        for width in RealBar.windowWidths {
            let available = PlanHeaderMetrics.availableTitleWidth(windowWidth: width, typeSize: size)
            for sample in samples {
                let shown = PlanHeaderText.displayedTitle(scope: sample.scope, anchor: sample.anchor, range: sample.range, calendar: calendar,
                                                          largeText: size.isAccessibilitySize, availableWidth: available, locale: language.locale,
                                                          width: { PlanHeaderMetrics.titleWidth($0, typeSize: size) })
                let isCurrent = PlanHeaderText.isCurrent(scope: sample.scope, anchor: sample.anchor, today: today, range: sample.range)
                let buttonWidth = renderedWidth(caption: caption(sample, language), title: shown, isCurrent: isCurrent, size: size)
                let gap = (width - RealBar.trailingButtonsWidth(size)) - (RealBar.leadingMargin + buttonWidth)
                #expect(gap >= RealBar.minimumGap,
                        "\(language) \(size) window \(width) pt \(sample.scope) \(sample.anchor): the title \"\(shown)\" (\(buttonWidth) pt) leaves \(gap) pt to the bar buttons")
                checked += 1
            }
        }
        #expect(checked == RealBar.windowWidths.count * samples.count)
    }

    /// The title must not be made so short that it is never the full form: at the default size a day on a wide window shows the weekday.
    @Test func title_keepsTheLongFormWhereItFits() {
        let saturday = samples[0]
        let shown = PlanHeaderText.displayedTitle(scope: .day, anchor: saturday.anchor, range: saturday.range, calendar: calendar, largeText: false,
                                                  availableWidth: PlanHeaderMetrics.availableTitleWidth(windowWidth: 440, typeSize: .large),
                                                  locale: Language.german.locale, width: { PlanHeaderMetrics.titleWidth($0, typeSize: .large) })
        #expect(shown.contains("21"))
        #expect(shown != "21. Nov.", "the full weekday form is expected on the widest window, got \(shown)")
    }
}

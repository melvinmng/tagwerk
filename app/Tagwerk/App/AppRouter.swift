import Foundation
import Observation
import TagwerkCore

/// What the "Erfassen" tab opens after a link or shortcut. Held only in memory, never stored or logged.
enum CapturePrefill: Equatable {
    /// Only show today (widget or plan header link): their values are today's.
    case today
    case meal(text: String?)
    case workout(activity: WorkoutActivity?, minutes: Int?)
    case review
}

/// Buffers a navigation request from a `tagwerk://` link or an App Intent until the app can show it
/// (cold start, setup still open). Links only navigate; nothing here writes data (phase 4 design §5.5).
@MainActor
@Observable
final class AppRouter {
    struct Request: Equatable {
        var route: AppRoute
        var prefill: CapturePrefill?
    }

    private var pending: Request?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    /// "Notiz diktieren" arrived: the notes list of Brain Dump starts a recording once, see `takeDictationRequest()`.
    private(set) var dictationRequested = false
    /// The Bible Study reminder was tapped: the list of the Bible Study folder opens the start sheet once.
    private(set) var bibleStudyStartRequested = false

    init(now: @escaping () -> Date = Date.init, calendar: Calendar = .tagwerk) {
        self.now = now
        self.calendar = calendar
    }
    /// Counts requests, so views react to every request, also to a second one for the same route.
    private(set) var receivedCount = 0
    /// Prefill for the "Erfassen" tab, consumed once by `CaptureView`.
    private(set) var capturePrefill: CapturePrefill?

    /// Accepts known `tagwerk://` links; returns `false` for anything else.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let route = AppRoute(url: url) else { return false }
        open(route)
        return true
    }

    func open(_ route: AppRoute, prefill: CapturePrefill? = nil) {
        let defaultPrefill: CapturePrefill? = switch route {
        case .captureMeal: .meal(text: nil)
        case .captureWorkout: .workout(activity: nil, minutes: nil)
        case .review: .review
        case .capture: .today
        case .planToday, .shopping, .routineStart, .routineEvening, .routineWeek, .routineNow, .notesDictate, .bibleStudyStart: nil
        }
        pending = Request(route: route, prefill: prefill ?? defaultPrefill)
        receivedCount += 1
    }

    /// The buffered request once setup is done; `nil` before. Hands the prefill on to the capture tab. "Tagesroutine"
    /// is resolved here, at the time the request is shown: the start in the morning, the wrap-up otherwise.
    func takeRequest(setupCompleted: Bool) -> Request? {
        guard setupCompleted, var request = pending else { return nil }
        pending = nil
        if request.route == .routineNow { request.route = RoutineSchedule.currentRoutine(at: now(), calendar: calendar) }
        capturePrefill = request.prefill
        dictationRequested = request.route == .notesDictate
        bibleStudyStartRequested = request.route == .bibleStudyStart
        return request
    }

    /// Whether a recording is to start in the notes list that was just opened; consumed once.
    func takeDictationRequest() -> Bool {
        defer { dictationRequested = false }
        return dictationRequested
    }

    /// Whether the start sheet of Bible Study is to open in the list that was just shown; consumed once.
    func takeBibleStudyStartRequest() -> Bool {
        defer { bibleStudyStartRequested = false }
        return bibleStudyStartRequested
    }

    func takeCapturePrefill() -> CapturePrefill? {
        defer { capturePrefill = nil }
        return capturePrefill
    }
}

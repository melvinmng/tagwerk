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
        case .planToday, .shopping: nil
        }
        pending = Request(route: route, prefill: prefill ?? defaultPrefill)
        receivedCount += 1
    }

    /// The buffered request once setup is done; `nil` before. Hands the prefill on to the capture tab.
    func takeRequest(setupCompleted: Bool) -> Request? {
        guard setupCompleted, let request = pending else { return nil }
        pending = nil
        capturePrefill = request.prefill
        return request
    }

    func takeCapturePrefill() -> CapturePrefill? {
        defer { capturePrefill = nil }
        return capturePrefill
    }
}

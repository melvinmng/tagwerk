import CoreGraphics
import Testing
import UIKit
@testable import Tagwerk

@MainActor
struct KeyboardTapPolicyTests {
    private let point = CGPoint(x: 100, y: 200)

    @Test func tapOnEmptyArea_withVisibleKeyboard_dismisses() {
        #expect(KeyboardTapPolicy.shouldDismiss(isKeyboardVisible: true, touchIsInTextInput: false, point: point, keepZones: []))
    }

    @Test func tap_withoutKeyboard_isIgnored() {
        #expect(!KeyboardTapPolicy.shouldDismiss(isKeyboardVisible: false, touchIsInTextInput: false, point: point, keepZones: []))
    }

    @Test func tapInTextInput_isIgnored_soTheFocusCanMoveToAnotherField() {
        #expect(!KeyboardTapPolicy.shouldDismiss(isKeyboardVisible: true, touchIsInTextInput: true, point: point, keepZones: []))
    }

    @Test func tapInsideKeepZone_isIgnored() {
        let zones = [CGRect(x: 0, y: 150, width: 300, height: 100)]
        #expect(!KeyboardTapPolicy.shouldDismiss(isKeyboardVisible: true, touchIsInTextInput: false, point: point, keepZones: zones))
    }

    @Test func tapOutsideEveryKeepZone_dismisses() {
        let zones = [CGRect(x: 0, y: 0, width: 300, height: 100), CGRect(x: 200, y: 150, width: 50, height: 100)]
        #expect(KeyboardTapPolicy.shouldDismiss(isKeyboardVisible: true, touchIsInTextInput: false, point: point, keepZones: zones))
    }

    @Test func zoneEdge_pointOnTheFarEdge_isOutsideTheZone() {
        // CGRect.contains is half-open: a tap exactly on the bottom edge of an input bar is not a tap on the bar.
        let zones = [CGRect(x: 0, y: 100, width: 300, height: 100)]
        #expect(KeyboardTapPolicy.shouldDismiss(isKeyboardVisible: true, touchIsInTextInput: false, point: CGPoint(x: 100, y: 200), keepZones: zones))
        #expect(!KeyboardTapPolicy.shouldDismiss(isKeyboardVisible: true, touchIsInTextInput: false, point: CGPoint(x: 100, y: 100), keepZones: zones))
    }

    // The keyboard closes after the touch sequence (a control in a sheet that shrinks must still receive its touch-up).

    @Test func dismissal_doesNotCloseTheKeyboardSynchronously_butInTheScheduledTurn() {
        var pending: [@MainActor () -> Void] = []
        var closedWindows: [UIWindow] = []
        let controller = KeyboardDismissalController(keepZones: KeyboardKeepZones(),
                                                     schedule: { pending.append($0) },
                                                     endEditing: { closedWindows.append($0) })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        controller.install(on: window)

        controller.dismissKeyboardAfterTouchSequence()

        #expect(closedWindows.isEmpty, "The keyboard must not close while the touch is still being delivered")
        #expect(pending.count == 1)
        pending.forEach { $0() }
        #expect(closedWindows == [window])
    }

    @Test func dismissal_afterTheWindowIsGone_doesNothing() {
        var pending: [@MainActor () -> Void] = []
        var closedWindows: [UIWindow] = []
        let controller = KeyboardDismissalController(keepZones: KeyboardKeepZones(),
                                                     schedule: { pending.append($0) },
                                                     endEditing: { closedWindows.append($0) })
        var window: UIWindow? = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        controller.install(on: window!)
        controller.dismissKeyboardAfterTouchSequence()

        window = nil
        pending.forEach { $0() }

        #expect(closedWindows.isEmpty)
    }

    @Test func registry_reportsWindowFrames_andSkipsViewsOutsideAWindow() {
        let registry = KeyboardKeepZones()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        // A container offset like a sheet, so the anchor's own frame differs from its window frame.
        let sheet = UIView(frame: CGRect(x: 0, y: 200, width: 400, height: 600))
        window.addSubview(sheet)
        let bar = UIView(frame: CGRect(x: 10, y: 500, width: 380, height: 50))
        sheet.addSubview(bar)
        let detached = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        registry.add(bar)
        registry.add(detached)

        #expect(registry.frames == [CGRect(x: 10, y: 700, width: 380, height: 50)])

        registry.remove(bar)
        #expect(registry.frames.isEmpty)
    }
}

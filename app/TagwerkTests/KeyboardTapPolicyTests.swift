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

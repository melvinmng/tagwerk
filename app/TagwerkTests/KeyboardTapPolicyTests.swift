import CoreGraphics
import Testing
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

    @Test func registry_keepsOneFramePerView_andForgetsRemovedViews() {
        let registry = KeyboardKeepZones()
        registry.update(id: "bar", frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        registry.update(id: "bar", frame: CGRect(x: 0, y: 50, width: 10, height: 10))
        registry.update(id: "header", frame: CGRect(x: 0, y: 100, width: 10, height: 10))
        #expect(registry.frames.count == 2)
        #expect(registry.frames.contains(CGRect(x: 0, y: 50, width: 10, height: 10)))
        registry.remove(id: "bar")
        #expect(registry.frames == [CGRect(x: 0, y: 100, width: 10, height: 10)])
    }
}

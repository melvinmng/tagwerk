import SwiftUI
import UIKit

// App-wide keyboard dismissal (#184, #177).
//
// Building blocks for every screen with text input:
// - A window-wide tap recognizer (installed once through `KeyboardDismissalInstaller`) closes the keyboard on a tap
//   outside of any text input. Sheets live in the same window, so they are covered without extra work.
// - `.keepsKeyboardOnTap()` marks an input bar at the screen edge: a tap on it (for example "send") keeps the keyboard open.
// - `.keyboardDoneButton()` adds a "Fertig" button above the keyboard for fields without a Return key.
// - Scrolling closes the keyboard through `.scrollDismissesKeyboard(.interactively)` on each Form, List and ScrollView
//   that contains inputs or sits above an input bar.

/// Decides whether a tap closes the keyboard. Pure, so the rules are testable without UIKit.
enum KeyboardTapPolicy {
    /// - Parameters:
    ///   - isKeyboardVisible: Whether the keyboard is currently on screen.
    ///   - touchIsInTextInput: Whether the tap landed on a text input (or a view inside one); the focus then moves there.
    ///   - point: The tap location in window coordinates.
    ///   - keepZones: Frames in window coordinates where a tap must keep the keyboard open.
    static func shouldDismiss(isKeyboardVisible: Bool, touchIsInTextInput: Bool, point: CGPoint, keepZones: [CGRect]) -> Bool {
        guard isKeyboardVisible, !touchIsInTextInput else { return false }
        return !keepZones.contains { $0.contains(point) }
    }
}

/// Registry of the frames marked with `.keepsKeyboardOnTap()`, one entry per view.
@MainActor
final class KeyboardKeepZones {
    static let shared = KeyboardKeepZones()

    private var framesByID: [String: CGRect] = [:]

    var frames: [CGRect] { Array(framesByID.values) }

    func update(id: String, frame: CGRect) { framesByID[id] = frame }

    func remove(id: String) { framesByID[id] = nil }
}

/// Owns the window-wide tap recognizer. The recognizer never cancels or delays touches and recognizes
/// together with every other gesture, so rows, buttons, menus and swipe actions behave as before.
@MainActor
final class KeyboardDismissalController: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissalController()

    private let recognizer = UITapGestureRecognizer()
    private let keepZones: KeyboardKeepZones
    private var isKeyboardVisible = false
    private weak var installedWindow: UIWindow?
    private var observers: [any NSObjectProtocol] = []

    init(keepZones: KeyboardKeepZones = .shared) {
        self.keepZones = keepZones
        super.init()
        recognizer.addTarget(self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delegate = self
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isKeyboardVisible = true }
            },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isKeyboardVisible = false }
            },
        ]
    }

    /// Attaches the recognizer to the window; calling it again for the same window does nothing.
    func install(on window: UIWindow) {
        guard installedWindow !== window else { return }
        installedWindow?.removeGestureRecognizer(recognizer)
        window.addGestureRecognizer(recognizer)
        installedWindow = window
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        installedWindow?.endEditing(true)
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        KeyboardTapPolicy.shouldDismiss(isKeyboardVisible: isKeyboardVisible,
                                        touchIsInTextInput: Self.isInTextInput(touch.view),
                                        point: touch.location(in: nil),
                                        keepZones: keepZones.frames)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// Walks up from the touched view: a text input, search bar or any view inside one counts.
    private static func isInTextInput(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UITextField || candidate is UITextView || candidate is UISearchBar { return true }
            current = candidate.superview
        }
        return false
    }
}

/// Zero-size anchor that installs the window-wide recognizer once its window is known.
/// Place it once in the root view; hosted unit tests do not install it.
struct KeyboardDismissalInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> AnchorView { AnchorView() }

    func updateUIView(_ uiView: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            MainActor.assumeIsolated { KeyboardDismissalController.shared.install(on: window) }
        }
    }
}

// MARK: - Modifiers

extension View {
    /// Marks an input bar (chat composer, shopping bar, quick capture): a tap on it keeps the keyboard open.
    func keepsKeyboardOnTap() -> some View { modifier(KeepsKeyboardOnTap()) }

    /// Shows a "Fertig" button above the keyboard while this field has focus. For fields without a Return key
    /// (multi-line fields, number pads). Apply it directly to the field; the focus state is kept internally.
    func keyboardDoneButton() -> some View { modifier(OwnFocusDoneButton()) }

    /// Same as `keyboardDoneButton()` for a field that already tracks its focus.
    func keyboardDoneButton(focus: FocusState<Bool>.Binding) -> some View { modifier(KeyboardDoneButton(focus: focus)) }
}

private struct KeepsKeyboardOnTap: ViewModifier {
    @State private var id = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                KeyboardKeepZones.shared.update(id: id, frame: frame)
            }
            .onDisappear { KeyboardKeepZones.shared.remove(id: id) }
    }
}

private struct KeyboardDoneButton: ViewModifier {
    let focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content.toolbar {
            // Only while this field has focus, so two fields never show two buttons.
            if focus.wrappedValue {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focus.wrappedValue = false }
                }
            }
        }
    }
}

private struct OwnFocusDoneButton: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .modifier(KeyboardDoneButton(focus: $isFocused))
    }
}

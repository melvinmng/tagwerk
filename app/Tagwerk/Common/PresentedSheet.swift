import UIKit

/// Whether the app's window already presents something (a sheet of a tab, a camera, an alert). SwiftUI cannot tell the root
/// view about sheets that child views own, so a shared item waits until nothing is presented.
enum PresentedSheet {
    @MainActor static var isShown: Bool {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        let window = windows.first { $0.isKeyWindow } ?? windows.first
        return window?.rootViewController?.presentedViewController != nil
    }
}

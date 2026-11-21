import SwiftUI
import UIKit

/// Principal class of the extension: hosts the SwiftUI sheet and hands it the extension context.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        configureSheet()
        let model = ShareModel(extensionContext: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The sheet presentation exists once the controller is presented; viewDidLoad can be too early.
        configureSheet()
    }

    /// Half-height sheet with a grabber. Whether the system honors detents for a share extension is only visible on a
    /// device; without it the sheet keeps its full height, with the button at the bottom.
    private func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        sheet.detents = [.medium(), .large()]
        sheet.prefersGrabberVisible = true
    }
}

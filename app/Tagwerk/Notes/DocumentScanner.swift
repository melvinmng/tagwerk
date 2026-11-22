import SwiftUI
import UIKit
import VisionKit

/// The document camera of the system (automatic shutter, several pages, cropping, filters) as a full-screen cover. It
/// reports the scanned pages as pictures, or no pages when the person cancels or the camera fails.
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish([]) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) { onFinish([]) }
    }

    /// Pages the UI tests use instead of the camera, which the simulator does not have: white, numbered, portrait.
    static func testPages(count: Int) -> [UIImage] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 600, height: 800)
        return (1...max(count, 1)).map { number in
            UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                ("Seite \(number)" as NSString).draw(at: CGPoint(x: 60, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black])
            }
        }
    }
}

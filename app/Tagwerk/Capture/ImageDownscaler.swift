import UIKit

/// Prepares a meal photo for ChatGPT: long edge at most 1,024 px, JPEG, re-encoded from pixels so no
/// location or camera metadata survives. Never upscales.
enum ImageDownscaler {
    static func jpeg(from image: UIImage, maxEdge: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let factor = min(1, maxEdge / max(pixelWidth, pixelHeight))
        let target = CGSize(width: (pixelWidth * factor).rounded(), height: (pixelHeight * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}

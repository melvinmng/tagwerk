import CoreGraphics
import Foundation
import TagwerkCore
import UIKit

/// Builds the PDF of a scanned document from the pages the document camera delivers, and names it.
@MainActor
enum ScanPDFBuilder {
    /// One PDF from the scanned pages. Each page is scaled to at most `NoteAttachmentStore.maximumImageEdge` pixels on its
    /// longer side (smaller pages stay as they are) and compressed as JPEG, which the PDF keeps as it is. The page of the PDF
    /// is as large as its picture in points. No pages give no data.
    static func pdf(pages: [UIImage]) -> Data {
        let output = NSMutableData()
        guard !pages.isEmpty, let consumer = CGDataConsumer(data: output as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return Data()
        }
        for page in pages {
            guard let jpeg = ImageDownscaler.jpeg(from: page, maxEdge: NoteAttachmentStore.maximumImageEdge, quality: NoteAttachmentStore.imageQuality),
                  let provider = CGDataProvider(data: jpeg as CFData),
                  let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { continue }
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            context.draw(image, in: box)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    /// "Scan 20.11.2026.pdf"; a second scan of the same day gets " 2", " 3", … before the extension.
    static func fileName(for day: PlanDay, existing: [String]) -> String {
        let base = String(format: "Scan %02d.%02d.%04d", day.day, day.month, day.year)
        let taken = Set(existing.map { $0.lowercased() })
        var candidate = "\(base).pdf"
        var number = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(number).pdf"
            number += 1
        }
        return candidate
    }
}

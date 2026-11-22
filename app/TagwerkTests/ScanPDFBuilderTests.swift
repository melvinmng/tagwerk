import PDFKit
import Testing
import TagwerkCore
import UIKit
@testable import Tagwerk

/// The PDF of a scan and its name. The pages are invented pictures.
@MainActor
struct ScanPDFBuilderTests {
    private func page(width: CGFloat, height: CGFloat, color: UIColor = .white) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func pdf_hasOnePagePerImage() throws {
        let data = ScanPDFBuilder.pdf(pages: [page(width: 300, height: 400), page(width: 300, height: 400, color: .red), page(width: 400, height: 300)])
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 3)
    }

    @Test func pdf_scalesLongEdgeTo2048() throws {
        let data = ScanPDFBuilder.pdf(pages: [page(width: 4000, height: 3000), page(width: 3000, height: 4000), page(width: 100, height: 50)])
        let document = try #require(PDFDocument(data: data))
        let sizes = (0..<document.pageCount).compactMap { document.page(at: $0)?.bounds(for: .mediaBox).size }
        #expect(sizes == [CGSize(width: 2048, height: 1536), CGSize(width: 1536, height: 2048), CGSize(width: 100, height: 50)])
    }

    @Test func pdf_withoutPagesIsEmpty() {
        #expect(ScanPDFBuilder.pdf(pages: []).isEmpty)
    }

    @Test func pdf_firstPageShowsThePicture() throws {
        let data = ScanPDFBuilder.pdf(pages: [page(width: 200, height: 300, color: .red), page(width: 200, height: 300, color: .blue)])
        let document = try #require(PDFDocument(data: data))
        let thumbnail = try #require(document.page(at: 0)?.thumbnail(of: CGSize(width: 20, height: 30), for: .mediaBox))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cgImage = try #require(thumbnail.cgImage)
        context.draw(cgImage, in: CGRect(x: -CGFloat(cgImage.width) / 2, y: -CGFloat(cgImage.height) / 2, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        #expect(pixel[0] > 200 && pixel[2] < 60)
    }

    @Test func fileName_countsUpOnSameDay() {
        let day = PlanDay(year: 2026, month: 11, day: 20)
        #expect(ScanPDFBuilder.fileName(for: day, existing: []) == "Scan 20.11.2026.pdf")
        #expect(ScanPDFBuilder.fileName(for: day, existing: ["Scan 20.11.2026.pdf"]) == "Scan 20.11.2026 2.pdf")
        #expect(ScanPDFBuilder.fileName(for: day, existing: ["Scan 20.11.2026.pdf", "Scan 20.11.2026 2.pdf"]) == "Scan 20.11.2026 3.pdf")
        // A scan that was renamed leaves the name free again; other days and other files do not count.
        #expect(ScanPDFBuilder.fileName(for: day, existing: ["Mietvertrag.pdf", "Scan 19.11.2026.pdf", "Foto.jpg"]) == "Scan 20.11.2026.pdf")
    }

    @Test func fileName_padsDayAndMonth() {
        #expect(ScanPDFBuilder.fileName(for: PlanDay(year: 2026, month: 3, day: 5), existing: []) == "Scan 05.03.2026.pdf")
    }
}

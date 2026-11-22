import SwiftUI
import UIKit

/// Contrast helpers for tests: the WCAG 2 formula, named colours per appearance and a measurement on a rendered view.
enum ContrastMath {
    /// WCAG 2 contrast ratio of two opaque sRGB colours, 1...21.
    static func ratio(_ first: UIColor, _ second: UIColor) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The opaque colour that results when `foreground` (with its own alpha) is drawn over the opaque `background`.
    static func composited(_ foreground: UIColor, over background: UIColor) -> UIColor {
        var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (backgroundRed, backgroundGreen, backgroundBlue, backgroundAlpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        foreground.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        background.getRed(&backgroundRed, green: &backgroundGreen, blue: &backgroundBlue, alpha: &backgroundAlpha)
        return UIColor(red: red * alpha + backgroundRed * (1 - alpha), green: green * alpha + backgroundGreen * (1 - alpha),
                       blue: blue * alpha + backgroundBlue * (1 - alpha), alpha: 1)
    }

    /// A named colour of the app's asset catalogs resolved for one appearance; nil when the asset is missing.
    static func color(named name: String, style: UIUserInterfaceStyle) -> UIColor? {
        guard let color = UIColor(named: name, in: Bundle.main, compatibleWith: nil) else { return nil }
        return color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    /// Contrast between the fill of a rendered view (the most frequent opaque pixel) and the pixel that differs most
    /// from it (the core of a bold glyph at three times the resolution). Nil when nothing could be rendered.
    @MainActor
    static func renderedRatio(of view: some View, colorScheme: ColorScheme, scale: CGFloat = 3) -> Double? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, colorScheme))
        renderer.scale = scale
        guard let image = renderer.cgImage, let pixels = opaquePixels(of: image), !pixels.isEmpty else { return nil }
        var counts: [Pixel: Int] = [:]
        for pixel in pixels { counts[pixel, default: 0] += 1 }
        guard let fill = counts.max(by: { $0.value < $1.value })?.key,
              let glyph = pixels.max(by: { distance($0, fill) < distance($1, fill) }) else { return nil }
        return ratio(fill.color, glyph.color)
    }

    // MARK: - Internals

    private struct Pixel: Hashable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        var color: UIColor {
            UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        }
    }

    private static func distance(_ first: Pixel, _ second: Pixel) -> Int {
        let red = Int(first.red) - Int(second.red)
        let green = Int(first.green) - Int(second.green)
        let blue = Int(first.blue) - Int(second.blue)
        return red * red + green * green + blue * blue
    }

    private static func relativeLuminance(_ color: UIColor) -> Double {
        // Measured in sRGB: the converted components are what the display gets.
        let srgb = color.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        let components = srgb?.components ?? [0, 0, 0, 1]
        let red = components.count >= 3 ? components[0] : 0
        let green = components.count >= 3 ? components[1] : 0
        let blue = components.count >= 3 ? components[2] : 0
        func linear(_ value: CGFloat) -> Double {
            let channel = Double(value)
            return channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// All fully opaque pixels as sRGB bytes; edge pixels of a shape are skipped because they mix in the background.
    private static func opaquePixels(of image: CGImage) -> [Pixel]? {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var result: [Pixel] = []
        result.reserveCapacity(width * height)
        for index in stride(from: 0, to: bytes.count, by: 4) where bytes[index + 3] == 255 {
            result.append(Pixel(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2]))
        }
        return result
    }
}

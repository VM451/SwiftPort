import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO

/// Pixel-level PNG comparison used by `swiftport verify --snapshots`.
/// Returns the fraction of pixels that differ (0.0 = identical).
/// macOS-only for now; other platforms report unsupported.
public enum SnapshotDiff {
    public enum DiffError: Error, CustomStringConvertible {
        case decodeFailed(String)
        case dimensionMismatch(String, String)

        public var description: String {
            switch self {
            case .decodeFailed(let path): return "could not decode PNG: \(path)"
            case .dimensionMismatch(let a, let b): return "dimension mismatch: \(a) vs \(b)"
            }
        }
    }

    /// Compares two PNG files. Returns differing-pixel fraction in [0, 1].
    public static func compare(pngA: URL, pngB: URL) throws -> Double {
        guard let imageA = decode(pngA), let imageB = decode(pngB) else {
            throw DiffError.decodeFailed("\(pngA.lastPathComponent) / \(pngB.lastPathComponent)")
        }
        guard imageA.width == imageB.width, imageA.height == imageB.height else {
            throw DiffError.dimensionMismatch(
                "\(imageA.width)x\(imageA.height)",
                "\(imageB.width)x\(imageB.height)"
            )
        }
        let width = imageA.width
        let height = imageA.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        guard let dataA = bitmapBytes(imageA, bytesPerRow: bytesPerRow),
              let dataB = bitmapBytes(imageB, bytesPerRow: bytesPerRow) else {
            throw DiffError.decodeFailed("bitmap conversion failed")
        }

        // A pixel differs if any of its 4 RGBA bytes differ.
        var differingPixels = 0
        dataA.withUnsafeBytes { ptrA in
            dataB.withUnsafeBytes { ptrB in
                let baseA = ptrA.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let baseB = ptrB.baseAddress!.assumingMemoryBound(to: UInt8.self)
                for pixel in 0..<(width * height) {
                    let offset = pixel * bytesPerPixel
                    if baseA[offset] != baseB[offset]
                        || baseA[offset + 1] != baseB[offset + 1]
                        || baseA[offset + 2] != baseB[offset + 2]
                        || baseA[offset + 3] != baseB[offset + 3] {
                        differingPixels += 1
                    }
                }
            }
        }
        return Double(differingPixels) / Double(width * height)
    }

    private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Renders a CGImage into a tightly packed RGBA8 buffer.
    private static func bitmapBytes(_ image: CGImage, bytesPerRow: Int) -> Data? {
        var data = Data(count: image.height * bytesPerRow)
        let rendered = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return rendered ? data : nil
    }
}
#endif

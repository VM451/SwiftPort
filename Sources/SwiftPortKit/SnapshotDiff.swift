import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

/// Pixel-level PNG comparison used by `swiftport verify --snapshots`.
/// Returns the fraction of pixels that differ (0.0 = identical).
///
/// Rasterization is platform-specific:
///   * Apple platforms: CoreGraphics/ImageIO decode.
///   * Linux: ImageMagick `identify` + `convert` to raw RGBA8 (binary-safe —
///     Shell stdout is UTF-8 text, so raw pixels go through temp files).
///   * Other platforms (e.g. Windows): comparison reports unsupported;
///     snapshot verification for those targets is CI-only for now.
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

    struct Raster {
        var width: Int
        var height: Int
        /// Tightly packed RGBA8, `width * height * 4` bytes.
        var data: Data
    }

    /// Compares two PNG files. Returns differing-pixel fraction in [0, 1].
    public static func compare(pngA: URL, pngB: URL) throws -> Double {
        let rasterA = try rasterize(pngA)
        let rasterB = try rasterize(pngB)
        guard rasterA.width == rasterB.width, rasterA.height == rasterB.height else {
            throw DiffError.dimensionMismatch(
                "\(rasterA.width)x\(rasterA.height)",
                "\(rasterB.width)x\(rasterB.height)"
            )
        }
        let width = rasterA.width
        let height = rasterA.height
        let bytesPerPixel = 4

        // A pixel differs if any of its 4 RGBA bytes differ.
        var differingPixels = 0
        rasterA.data.withUnsafeBytes { ptrA in
            rasterB.data.withUnsafeBytes { ptrB in
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

    /// Heuristic blank-screen detection for simulator captures: a framebuffer
    /// that never composited app content comes back as a flat color field.
    /// Samples every 32nd pixel and counts distinct quantized colors — real
    /// UI (text, icons, lists) produces hundreds, a blank frame a handful.
    /// Decode failures return false so verification falls through to the
    /// normal diff path rather than blocking on this heuristic.
    public static func isBlankCapture(_ url: URL) -> Bool {
        guard let raster = try? rasterize(url) else { return false }
        var colors = Set<UInt32>()
        let total = raster.width * raster.height
        raster.data.withUnsafeBytes { ptr in
            let base = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var i = 0
            while i < total {
                let o = i * 4
                colors.insert(
                    (UInt32(base[o] >> 4) << 8)
                    | (UInt32(base[o + 1] >> 4) << 4)
                    | UInt32(base[o + 2] >> 4))
                i += 32
            }
        }
        return colors.count < 24
    }

    // MARK: - Apple platforms

    #if canImport(CoreGraphics) && canImport(ImageIO)
    static func rasterize(_ url: URL) throws -> Raster {
        guard let image = decode(url) else {
            throw DiffError.decodeFailed(url.path)
        }
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        guard let data = bitmapBytes(image, bytesPerRow: bytesPerRow) else {
            throw DiffError.decodeFailed("bitmap conversion failed")
        }
        return Raster(width: width, height: height, data: data)
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
    #elseif os(Linux)
    // MARK: - Linux (ImageMagick)

    static func rasterize(_ url: URL) throws -> Raster {
        guard Shell.which("convert") != nil, Shell.which("identify") != nil else {
            throw DiffError.decodeFailed(
                "ImageMagick not found — sudo apt install imagemagick")
        }

        guard let idResult = try? Shell.run(
            "identify", arguments: ["-format", "%w %h", url.path]),
              idResult.succeeded else {
            throw DiffError.decodeFailed(url.path)
        }
        let dims = idResult.stdout
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .compactMap { Int($0) }
        guard dims.count == 2 else { throw DiffError.decodeFailed(url.path) }
        let (width, height) = (dims[0], dims[1])

        // Raw RGBA8 via temp file — Shell stdout is UTF-8 text and would
        // corrupt binary pixel data.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftport-\(UUID().uuidString).rgba")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let conv = try? Shell.run(
            "convert", arguments: [url.path, "rgba:\(tmp.path)"]),
              conv.succeeded,
              let data = try? Data(contentsOf: tmp),
              data.count == width * height * 4 else {
            throw DiffError.decodeFailed(url.path)
        }
        return Raster(width: width, height: height, data: data)
    }
    #else
    // MARK: - Unsupported platforms

    static func rasterize(_ url: URL) throws -> Raster {
        throw DiffError.decodeFailed(
            "PNG comparison is unsupported on this platform: \(url.lastPathComponent)")
    }
    #endif
}

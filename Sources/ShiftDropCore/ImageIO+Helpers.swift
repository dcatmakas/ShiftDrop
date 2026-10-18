import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Small wrappers around ImageIO for loading upright images and writing any supported format.
public enum ImageFile {
    /// Loads the first frame with its EXIF orientation applied, so pixels are upright.
    public static func load(_ url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ShiftDropError.unreadable(url)
        }
        return try load(source, url: url, maxPixelSize: maxPixelSize)
    }

    static func load(_ source: CGImageSource, url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let fullSize = max(width, height)
        let target = min(maxPixelSize ?? fullSize, fullSize)

        // Creating a "thumbnail" at full size is the simplest way to get ImageIO to bake in orientation.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target, 1),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if fullSize > 0, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return image
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ShiftDropError.unreadable(url)
        }
        return image
    }

    /// Metadata of the first frame, without orientation (pixels we write are already upright).
    static func properties(of url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              var props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [:] }
        props[kCGImagePropertyOrientation] = nil
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = nil
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        // Drop the source's size fields; the encoder fills in the real ones.
        props[kCGImagePropertyPixelWidth] = nil
        props[kCGImagePropertyPixelHeight] = nil
        return props
    }

    public static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// Draws `image` over a solid color, for formats that can't store transparency.
    public static func flattened(_ image: CGImage, background: CGColor = CGColor(gray: 1, alpha: 1)) -> CGImage {
        guard hasAlpha(image) else { return image }
        let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(background)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    /// Writes `image` as `format`. `quality` applies to lossy formats (0...1).
    public static func write(
        _ image: CGImage, to url: URL, format: Format,
        quality: Double = 0.9, properties: [CFString: Any] = [:]
    ) async throws {
        if format == .webp {
            try await writeWebP(image, to: url, quality: quality)
            return
        }
        guard let type = format.imageIOType else {
            throw ShiftDropError.unsupported("writing \(format.label) images")
        }
        let pixels = format.supportsAlpha ? image : flattened(image)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw ShiftDropError.writeFailed(url)
        }
        var props = properties
        if format.isLossy { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, pixels, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ShiftDropError.writeFailed(url) }
    }

    /// ImageIO can read WebP but not write it, so go through Homebrew's `cwebp`.
    private static func writeWebP(_ image: CGImage, to url: URL, quality: Double) async throws {
        guard let cwebp = Shell.cwebpPath else {
            throw ShiftDropError.unsupported("WebP (install with: brew install webp)")
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: temp) }
        try await write(image, to: temp, format: .png)
        let q = String(Int((quality * 100).rounded()))
        try await Shell.run(cwebp, ["-quiet", "-metadata", "icc", "-q", q, temp.path, "-o", url.path])
    }

    /// Size of a CGImage in points for a PDF page, using the file's DPI when it has one.
    static func pageSize(for image: CGImage, properties: [CFString: Any]) -> CGSize {
        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double) ?? 72
        var size = CGSize(width: image.width, height: image.height)
        if dpi > 72 {
            size = CGSize(width: size.width * 72 / dpi, height: size.height * 72 / dpi)
        }
        // Keep huge photos to roughly A4 so the PDF prints sensibly.
        let longSide = max(size.width, size.height)
        if longSide > 842 {
            let scale = 842 / longSide
            size = CGSize(width: size.width * scale, height: size.height * scale)
        }
        return size
    }
}

import CoreGraphics
import Foundation
import ImageIO

public enum ImageConverter {
    public static func convert(_ url: URL, to format: Format) async throws -> URL {
        switch format {
        case .pdf:
            return try makePDF(from: [url], output: OutputNamer.url(for: url, ext: "pdf"))
        case .txt:
            let image = try ImageFile.load(url)
            let text = try VisionTasks.recognizeText(in: image)
            guard !text.isEmpty else { throw ShiftDropError.noText }
            let out = OutputNamer.url(for: url, ext: "txt")
            try text.write(to: out, atomically: true, encoding: .utf8)
            return out
        default:
            guard format.kind == .image else { throw ShiftDropError.unsupported("image to \(format.label)") }
            let image = try ImageFile.load(url)
            let out = OutputNamer.url(for: url, ext: format.fileExtension)
            try await ImageFile.write(image, to: out, format: format, properties: ImageFile.properties(of: url))
            return out
        }
    }

    /// Puts each image on its own page of one PDF.
    public static func makePDF(from urls: [URL], output: URL) throws -> URL {
        var mediaBox = CGRect.zero
        guard let ctx = CGContext(output as CFURL, mediaBox: &mediaBox, nil) else {
            throw ShiftDropError.writeFailed(output)
        }
        for url in urls {
            let image = try ImageFile.load(url)
            let size = ImageFile.pageSize(for: image, properties: ImageFile.properties(of: url))
            var box = CGRect(origin: .zero, size: size)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
            ctx.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            ctx.interpolationQuality = .high
            ctx.draw(image, in: box)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return output
    }

    // MARK: - Tools

    /// Re-encodes to a smaller file. Lossy formats keep their format; opaque PNG/TIFF/BMP become JPEG.
    public static func compress(_ url: URL) async throws -> URL {
        guard let source = Format(fileExtension: url.pathExtension) else {
            throw ShiftDropError.unsupported(url.pathExtension)
        }
        // Very large images are rarely needed at full size; cap the long side.
        let image = try ImageFile.load(url, maxPixelSize: 4096)
        let props = ImageFile.properties(of: url)

        let target: Format
        let quality: Double
        switch source {
        case .jpg: target = .jpg; quality = 0.6
        case .heic, .avif: target = source; quality = 0.5
        case .webp: target = Shell.canWriteWebP ? .webp : .jpg; quality = 0.6
        case .gif: target = .gif; quality = 1
        default:
            if ImageFile.hasAlpha(image) {
                target = .png; quality = 1
            } else {
                target = .jpg; quality = 0.75
            }
        }

        // PNGs with transparency are lossless, so shrinking pixels is the only real saving.
        var pixels = image
        if target == .png, max(image.width, image.height) > 2048 {
            pixels = try ImageFile.load(url, maxPixelSize: 2048)
        }

        let out = OutputNamer.url(for: url, suffix: "Compressed", ext: target.fileExtension)
        try await ImageFile.write(pixels, to: out, format: target, quality: quality, properties: props)
        return out
    }

    /// Copies the image without EXIF, GPS, IPTC or XMP data. Pixels are untouched where ImageIO allows.
    public static func stripMetadata(_ url: URL) async throws -> URL {
        guard let format = Format(fileExtension: url.pathExtension) else {
            throw ShiftDropError.unsupported(url.pathExtension)
        }
        let out = OutputNamer.url(for: url, suffix: "Clean", ext: format.fileExtension)

        if let type = format.imageIOType,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let dest = CGImageDestinationCreateWithURL(out as CFURL, type as CFString, 1, nil) {
            // Keep only the orientation so the photo still displays the right way up.
            let metadata = CGImageMetadataCreateMutable()
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let orientation = props[kCGImagePropertyOrientation] as? Int, orientation != 1 {
                CGImageMetadataSetValueMatchingImageProperty(
                    metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation,
                    orientation as CFNumber
                )
            }
            let options: [CFString: Any] = [
                kCGImageDestinationMetadata: metadata,
                kCGImageDestinationMergeMetadata: false,
                kCGImageMetadataShouldExcludeXMP: true,
                kCGImageMetadataShouldExcludeGPS: true,
            ]
            var error: Unmanaged<CFError>?
            if CGImageDestinationCopyImageSource(dest, source, options as CFDictionary, &error) {
                return out
            }
            try? FileManager.default.removeItem(at: out)
        }

        // Fallback: re-encode the pixels with no properties at all.
        let image = try ImageFile.load(url)
        try await ImageFile.write(image, to: out, format: format, quality: 0.95)
        return out
    }

    public static func removeBackground(_ url: URL) throws -> URL {
        let image = try ImageFile.load(url)
        let cutout = try VisionTasks.removeBackground(from: image)
        let out = OutputNamer.url(for: url, suffix: "No BG", ext: "png")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, Format.png.imageIOType! as CFString, 1, nil) else {
            throw ShiftDropError.writeFailed(out)
        }
        CGImageDestinationAddImage(dest, cutout, nil)
        guard CGImageDestinationFinalize(dest) else { throw ShiftDropError.writeFailed(out) }
        return out
    }
}

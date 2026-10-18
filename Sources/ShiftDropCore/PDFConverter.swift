import AppKit
import CoreGraphics
import Foundation
import PDFKit
import Quartz

public enum PDFConverter {
    /// Pages are rendered at print resolution, capped so a poster-sized page doesn't explode.
    static let renderDPI: CGFloat = 300
    static let maxRenderPixels: CGFloat = 6000

    public static func convert(_ url: URL, to format: Format) async throws -> [URL] {
        guard let document = PDFDocument(url: url) else { throw ShiftDropError.unreadable(url) }
        switch format {
        case .txt:
            guard let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ShiftDropError.noText
            }
            let out = OutputNamer.url(for: url, ext: "txt")
            try text.write(to: out, atomically: true, encoding: .utf8)
            return [out]
        case .docx, .rtf, .html, .odt:
            let text = attributedText(of: document)
            guard text.length > 0 else { throw ShiftDropError.noText }
            let out = OutputNamer.url(for: url, ext: format.fileExtension)
            try await DocumentConverter.write(text, to: out, as: format)
            return [out]
        default:
            guard format.kind == .image else { throw ShiftDropError.unsupported("PDF to \(format.label)") }
            return try await renderPages(of: document, source: url, as: format)
        }
    }

    /// Text of all pages with its fonts, separated by blank lines.
    public static func attributedText(of document: PDFDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.attributedString else { continue }
            if result.length > 0 { result.append(NSAttributedString(string: "\n\n")) }
            result.append(text)
        }
        return result
    }

    /// One image per page. A single page lands next to the PDF; several go into a new folder.
    static func renderPages(of document: PDFDocument, source: URL, as format: Format) async throws -> [URL] {
        let count = document.pageCount
        guard count > 0 else { throw ShiftDropError.unreadable(source) }
        let folder = count > 1 ? try OutputNamer.folder(for: source, suffix: "Pages") : nil
        let base = source.deletingPathExtension().lastPathComponent

        var outputs: [URL] = []
        for index in 0..<count {
            guard let page = document.page(at: index)?.pageRef else { continue }
            let (image, dpi) = try render(page)
            let out: URL
            if let folder {
                out = OutputNamer.unique(folder.appendingPathComponent("\(base) \(index + 1).\(format.fileExtension)"))
            } else {
                out = OutputNamer.url(for: source, ext: format.fileExtension)
            }
            let props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
            try await ImageFile.write(image, to: out, format: format, properties: props)
            outputs.append(out)
        }
        return folder.map { [$0] } ?? outputs
    }

    /// Renders a page on white at `renderDPI`, honouring its rotation.
    static func render(_ page: CGPDFPage) throws -> (CGImage, CGFloat) {
        let box = page.getBoxRect(.cropBox)
        let rotated = page.rotationAngle % 180 != 0
        let pointSize = rotated ? CGSize(width: box.height, height: box.width) : box.size
        var scale = renderDPI / 72
        let longSide = max(pointSize.width, pointSize.height) * scale
        if longSide > maxRenderPixels { scale *= maxRenderPixels / longSide }

        let width = Int((pointSize.width * scale).rounded())
        let height = Int((pointSize.height * scale).rounded())
        guard width > 0, height > 0, let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ShiftDropError.unsupported("empty PDF page") }

        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: pointSize), rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { throw ShiftDropError.unsupported("PDF rendering") }
        return (image, 72 * scale)
    }

    // MARK: - Tools

    /// Re-compresses embedded images to JPEG at 150 dpi using a Quartz filter. Text stays as text.
    public static func compress(_ url: URL) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw ShiftDropError.unreadable(url) }
        let filterProperties: [String: Any] = [
            "Domains": ["Applications": true, "Printing": true],
            "FilterType": 1,
            "Name": "ShiftDrop Compress",
            "FilterData": [
                "ColorSettings": [
                    "ImageSettings": [
                        "Compression Quality": 0.6,
                        "ImageCompression": "ImageJPEGCompress",
                        "ImageScaleSettings": [
                            "ImageResolution": 150,
                            "ImageScaleFactor": 0.0,
                            "ImageScaleInterpolate": true,
                            "ImageSizeMax": 0,
                            "ImageSizeMin": 0,
                        ],
                    ],
                ],
            ],
        ]
        guard let filter = QuartzFilter(properties: filterProperties) else {
            throw ShiftDropError.unsupported("PDF compression filter")
        }
        let out = OutputNamer.url(for: url, suffix: "Compressed", ext: "pdf")
        let options = [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]
        guard document.write(to: out, withOptions: options) else { throw ShiftDropError.writeFailed(out) }
        return out
    }

    public static func merge(_ urls: [URL]) throws -> URL {
        guard let first = urls.first, let merged = PDFDocument(url: first) else {
            throw ShiftDropError.unreadable(urls.first ?? URL(fileURLWithPath: "/"))
        }
        for url in urls.dropFirst() {
            guard let doc = PDFDocument(url: url) else { throw ShiftDropError.unreadable(url) }
            for index in 0..<doc.pageCount {
                if let page = doc.page(at: index) { merged.insert(page, at: merged.pageCount) }
            }
        }
        let out = OutputNamer.url(for: first, suffix: "Merged", ext: "pdf")
        guard merged.write(to: out) else { throw ShiftDropError.writeFailed(out) }
        return out
    }

    /// Writes each page as its own PDF into a new folder.
    public static func split(_ url: URL) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw ShiftDropError.unreadable(url) }
        guard document.pageCount > 1 else { throw ShiftDropError.nothingFound("The PDF has only one page") }
        let folder = try OutputNamer.folder(for: url, suffix: "Pages")
        let base = url.deletingPathExtension().lastPathComponent
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let out = folder.appendingPathComponent("\(base) \(index + 1).pdf")
            guard single.write(to: out) else { throw ShiftDropError.writeFailed(out) }
        }
        return folder
    }

    public static func text(of url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw ShiftDropError.unreadable(url) }
        let text = document.string ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ShiftDropError.noText }
        return text
    }
}

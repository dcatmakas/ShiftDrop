import AppKit
import Foundation

/// Text documents (DOCX, DOC, RTF, ODT, HTML, TXT, Markdown) via NSAttributedString.
/// Runs on the main actor because AppKit's HTML importer and text layout require it.
@MainActor
public enum DocumentConverter {
    public static func convert(_ url: URL, to format: Format) async throws -> URL {
        let text = try read(url)
        let out = OutputNamer.url(for: url, ext: format.fileExtension)
        try write(text, to: out, as: format)
        return out
    }

    public static func read(_ url: URL) throws -> NSAttributedString {
        guard let format = Format(fileExtension: url.pathExtension) else {
            throw ShiftDropError.unsupported(url.pathExtension)
        }
        switch format {
        case .txt:
            let string = try String(contentsOf: url, encoding: .utf8)
            return NSAttributedString(string: string, attributes: bodyAttributes)
        case .md:
            let string = try String(contentsOf: url, encoding: .utf8)
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            let parsed = try AttributedString(markdown: string, options: options)
            let result = NSMutableAttributedString(parsed)
            result.addAttributes(bodyAttributes, range: NSRange(location: 0, length: result.length))
            return result
        default:
            guard let type = documentType(for: format) else {
                throw ShiftDropError.unsupported("reading \(format.label)")
            }
            return try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
        }
    }

    public static func write(_ text: NSAttributedString, to url: URL, as format: Format) throws {
        switch format {
        case .txt:
            try text.string.write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            try renderPDF(text, to: url)
        default:
            guard let type = documentType(for: format) else {
                throw ShiftDropError.unsupported("writing \(format.label)")
            }
            let data = try text.data(
                from: NSRange(location: 0, length: text.length),
                documentAttributes: [.documentType: type]
            )
            try data.write(to: url)
        }
    }

    public static func plainText(of url: URL) throws -> String {
        let text = try read(url).string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ShiftDropError.noText }
        return text
    }

    private static let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor.black,
    ]

    private static func documentType(for format: Format) -> NSAttributedString.DocumentType? {
        switch format {
        case .docx: return .officeOpenXML
        case .doc: return .docFormat
        case .rtf: return .rtf
        case .html: return .html
        case .odt: return .openDocument
        default: return nil
        }
    }

    /// Lays the text out on A4 pages with 2 cm margins and draws them into a PDF.
    static func renderPDF(_ text: NSAttributedString, to url: URL) throws {
        let pageSize = CGSize(width: 595, height: 842)
        let margin: CGFloat = 56
        let containerSize = CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)

        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: containerSize)
            layout.addTextContainer(container)
            containers.append(container)
            _ = layout.glyphRange(for: container) // forces layout of this page
        } while NSMaxRange(layout.glyphRange(for: containers.last!)) < layout.numberOfGlyphs && containers.count < 5000

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw ShiftDropError.writeFailed(url)
        }
        let previous = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previous }

        for container in containers {
            let range = layout.glyphRange(for: container)
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            // AppKit text drawing expects a flipped (top-left origin) context.
            ctx.translateBy(x: 0, y: pageSize.height)
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let origin = CGPoint(x: margin, y: margin)
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}

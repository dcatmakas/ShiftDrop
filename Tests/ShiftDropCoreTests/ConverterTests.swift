import AppKit
import ImageIO
import PDFKit
import XCTest
@testable import ShiftDropCore

final class ConverterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ShiftDropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Fixtures

    /// A 600×400 image with a colored block and some large text, so OCR has something to read.
    private func makeImage(named name: String, format: Format, alpha: Bool = false) async throws -> URL {
        let width = 600, height = 400
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue
        )!
        if !alpha {
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        ctx.setFillColor(CGColor(red: 0.95, green: 0.35, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 40, y: 40, width: 200, height: 120))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAttributedString(string: "Hello ShiftDrop", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 48), .foregroundColor: NSColor.black,
        ]).draw(at: NSPoint(x: 40, y: 260))
        NSGraphicsContext.restoreGraphicsState()

        let url = dir.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        try await ImageFile.write(ctx.makeImage()!, to: url, format: format)
        return url
    }

    private func makePDF(pages: Int) async throws -> URL {
        let url = dir.appendingPathComponent("Doc.pdf")
        try await MainActor.run {
            let text = NSMutableAttributedString()
            for page in 1...pages {
                // Form feed starts a new page in the text layout.
                if page > 1 { text.append(NSAttributedString(string: "\u{0C}")) }
                text.append(NSAttributedString(string: "Page \(page) of the test document.\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 18),
                ]))
                text.append(NSAttributedString(string: String(repeating: "Line of filler text.\n", count: 45), attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                ]))
            }
            try DocumentConverter.renderPDF(text, to: url)
        }
        return url
    }

    private func pixelSize(_ url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    // MARK: - Images

    func testImageConvertsToEveryOfferedFormat() async throws {
        let png = try await makeImage(named: "Photo", format: .png)
        let targets = ActionCatalog.convertTargets(for: png)
        XCTAssertFalse(targets.contains(.png), "never offers the source format")
        XCTAssertTrue(targets.contains(.jpg))

        for target in targets {
            let out = try await ImageConverter.convert(png, to: target)
            XCTAssertEqual(out.pathExtension, target.fileExtension)
            XCTAssertGreaterThan(out.fileSize, 0, "\(target) is empty")
            if target.kind == .image {
                XCTAssertEqual(pixelSize(out), CGSize(width: 600, height: 400), "\(target) size")
            }
        }
    }

    func testOCRReadsTextFromImage() async throws {
        let png = try await makeImage(named: "Text", format: .png)
        let out = try await ImageConverter.convert(png, to: .txt)
        let text = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(text.contains("ShiftDrop"), "OCR got: \(text)")
    }

    func testTransparentImageBecomesWhiteJPEG() async throws {
        let png = try await makeImage(named: "Alpha", format: .png, alpha: true)
        let jpg = try await ImageConverter.convert(png, to: .jpg)
        let image = try ImageFile.load(jpg)
        // Corner was transparent; it must not turn black.
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1))!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = ctx.data!.assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(pixel[0], 240)
    }

    func testCompressAndStripMetadata() async throws {
        let jpg = try await makeImage(named: "Big", format: .jpg)
        let compressed = try await ImageConverter.compress(jpg)
        XCTAssertEqual(compressed.lastPathComponent, "Big Compressed.jpg")
        XCTAssertLessThan(compressed.fileSize, jpg.fileSize)

        let clean = try await ImageConverter.stripMetadata(jpg)
        XCTAssertEqual(clean.lastPathComponent, "Big Clean.jpg")
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(clean as CFURL, nil)!, 0, nil) as? [CFString: Any]
        XCTAssertNil(props?[kCGImagePropertyGPSDictionary])
    }

    func testMakePDFFromImages() async throws {
        let a = try await makeImage(named: "A", format: .png)
        let b = try await makeImage(named: "B", format: .jpg)
        let result = try await ActionRunner.run(.tool(.makePDF), on: [a, b])
        XCTAssertEqual(PDFDocument(url: result.outputs[0])?.pageCount, 2)
    }

    // MARK: - PDF

    func testPDFToImagesTextAndDocx() async throws {
        let pdf = try await makePDF(pages: 1)
        XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 1)

        let jpg = try await PDFConverter.convert(pdf, to: .jpg)
        XCTAssertEqual(jpg.map(\.lastPathComponent), ["Doc.jpg"])
        XCTAssertEqual(pixelSize(jpg[0])?.width, 2479) // A4 width at 300 dpi

        let txt = try await PDFConverter.convert(pdf, to: .txt)
        XCTAssertTrue(try String(contentsOf: txt[0], encoding: .utf8).contains("Page 1"))

        let docx = try await PDFConverter.convert(pdf, to: .docx)
        let roundTrip = try await DocumentConverter.read(docx[0])
        XCTAssertTrue(roundTrip.string.contains("Page 1"))
    }

    func testMultiPagePDFSplitMergeAndRender() async throws {
        let pdf = try await makePDF(pages: 3)
        let pageCount = try XCTUnwrap(PDFDocument(url: pdf)?.pageCount)
        XCTAssertGreaterThanOrEqual(pageCount, 3)

        let pngs = try await PDFConverter.convert(pdf, to: .png)
        XCTAssertEqual(pngs.count, 1, "several pages go into one folder")
        let rendered = try FileManager.default.contentsOfDirectory(atPath: pngs[0].path)
        XCTAssertEqual(rendered.count, pageCount)

        let folder = try PDFConverter.split(pdf)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, pageCount)

        let merged = try PDFConverter.merge([pdf, pdf])
        XCTAssertEqual(PDFDocument(url: merged)?.pageCount, pageCount * 2)

        let compressed = try PDFConverter.compress(pdf)
        XCTAssertNotNil(PDFDocument(url: compressed))
    }

    // MARK: - Documents

    func testDocumentRoundTrips() async throws {
        let txt = dir.appendingPathComponent("Notes.txt")
        try "Merhaba dünya — ShiftDrop çalışıyor.".write(to: txt, atomically: true, encoding: .utf8)

        for target in ActionCatalog.convertTargets(for: txt) {
            let out = try await DocumentConverter.convert(txt, to: target)
            XCTAssertGreaterThan(out.fileSize, 0, "\(target)")
            if target == .pdf {
                XCTAssertTrue(PDFDocument(url: out)?.string?.contains("Merhaba") ?? false)
            } else {
                let back = try await DocumentConverter.read(out)
                XCTAssertTrue(back.string.contains("çalışıyor"), "\(target): \(back.string)")
            }
        }
    }

    // MARK: - Archives & catalog

    func testZipSingleAndMultiple() async throws {
        let a = try await makeImage(named: "A", format: .png)
        let b = try await makeImage(named: "B", format: .png)
        let single = try await Archiver.zip([a])
        XCTAssertEqual(single.lastPathComponent, "A.zip")
        let multi = try await Archiver.zip([a, b])
        XCTAssertEqual(multi.lastPathComponent, "Archive.zip")
        XCTAssertGreaterThan(multi.fileSize, 0)
    }

    func testCatalogOffersOnlySharedTargetsAndCapsAtEight() {
        let png = URL(fileURLWithPath: "/tmp/a.png")
        let pdf = URL(fileURLWithPath: "/tmp/b.pdf")
        XCTAssertLessThanOrEqual(ActionCatalog.actions(for: [png], mode: .convert).count, 8)
        XCTAssertEqual(ActionCatalog.actions(for: [pdf], mode: .convert).map(\.title), ["DOCX", "JPG", "PNG", "TXT"])
        // A PNG and a PDF can both become JPG.
        XCTAssertTrue(ActionCatalog.convertTargets(for: [png, pdf]).contains(.jpg))
        XCTAssertEqual(ActionCatalog.tools(for: [png, pdf]), [.zip])
    }
}

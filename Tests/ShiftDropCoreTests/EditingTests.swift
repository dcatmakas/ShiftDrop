import CoreGraphics
import ImageIO
import XCTest
@testable import ShiftDropCore

final class CropGeometryTests: XCTestCase {
    let bounds = CGSize(width: 2000, height: 1000)

    func testFitCentersLargestRectForEachRatio() {
        for aspect in CropAspect.allCases {
            let rect = CropGeometry.fit(ratio: aspect.ratio, in: bounds)
            XCTAssertTrue(CGRect(origin: .zero, size: bounds).contains(rect.insetBy(dx: 0.01, dy: 0.01)), "\(aspect)")
            XCTAssertEqual(rect.midX, 1000, accuracy: 0.01)
            XCTAssertEqual(rect.midY, 500, accuracy: 0.01)
            if let ratio = aspect.ratio {
                XCTAssertEqual(rect.width / rect.height, ratio, accuracy: 0.001, "\(aspect)")
                // Largest: touches the bounds on at least one axis.
                XCTAssertTrue(abs(rect.width - 2000) < 0.01 || abs(rect.height - 1000) < 0.01, "\(aspect)")
            } else {
                XCTAssertEqual(rect.size, bounds)
            }
        }
        XCTAssertEqual(CropGeometry.fit(ratio: 1, in: bounds), CGRect(x: 500, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(CropGeometry.fit(ratio: 9.0 / 16.0, in: bounds).size.height, 1000, accuracy: 0.01)
    }

    func testMoveStaysInBounds() {
        let start = CGRect(x: 100, y: 100, width: 500, height: 300)
        let moved = CropGeometry.move(start, by: CGSize(width: 5000, height: -5000), bounds: bounds)
        XCTAssertEqual(moved, CGRect(x: 1500, y: 0, width: 500, height: 300))
    }

    func testFreeResizeFromCornerAndClamp() {
        let start = CGRect(x: 100, y: 100, width: 500, height: 300)
        let r = CropGeometry.resize(start, handle: .bottomRight, by: CGSize(width: 100, height: 50), ratio: nil, bounds: bounds)
        XCTAssertEqual(r, CGRect(x: 100, y: 100, width: 600, height: 350))

        let clamped = CropGeometry.resize(start, handle: .topLeft, by: CGSize(width: -1000, height: -1000), ratio: nil, bounds: bounds)
        XCTAssertEqual(clamped, CGRect(x: 0, y: 0, width: 600, height: 400))

        // Can't invert the rectangle: stops at the minimum size.
        let tiny = CropGeometry.resize(start, handle: .right, by: CGSize(width: -5000, height: 0), ratio: nil, bounds: bounds)
        XCTAssertEqual(tiny.width, CropGeometry.minSize)
        XCTAssertEqual(tiny.minX, 100)
    }

    func testRatioResizeKeepsRatioAndBounds() {
        let start = CropGeometry.fit(ratio: 1, in: bounds) // 500,0 1000x1000
        for handle in CropHandle.allCases {
            for t in [CGSize(width: 300, height: 120), CGSize(width: -400, height: -250), CGSize(width: 4000, height: 4000)] {
                let r = CropGeometry.resize(start, handle: handle, by: t, ratio: 1, bounds: bounds)
                XCTAssertEqual(r.width, r.height, accuracy: 0.01, "\(handle) \(t)")
                XCTAssertGreaterThanOrEqual(r.minX, -0.01, "\(handle) \(t)")
                XCTAssertGreaterThanOrEqual(r.minY, -0.01, "\(handle) \(t)")
                XCTAssertLessThanOrEqual(r.maxX, 2000.01, "\(handle) \(t)")
                XCTAssertLessThanOrEqual(r.maxY, 1000.01, "\(handle) \(t)")
                XCTAssertGreaterThanOrEqual(r.width, CropGeometry.minSize - 0.01)
            }
        }
        // Dragging the bottom-right corner inward keeps the top-left corner fixed.
        let shrunk = CropGeometry.resize(start, handle: .bottomRight, by: CGSize(width: -200, height: -200), ratio: 1, bounds: bounds)
        XCTAssertEqual(shrunk, CGRect(x: 500, y: 0, width: 800, height: 800))
    }

    func testResizedToExactSize() {
        let rect = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        let r = CropGeometry.resized(rect, width: 800, height: 600, bounds: bounds)
        XCTAssertEqual(r, CGRect(x: 600, y: 200, width: 800, height: 600))
        let big = CropGeometry.resized(rect, width: 9999, height: 9999, bounds: bounds)
        XCTAssertEqual(big.size, bounds)
    }
}

final class CropRendererTests: XCTestCase {
    func testCropOutputSizeAndContent() throws {
        // Left half red, right half blue.
        let image = try makeImage(width: 400, height: 200) { ctx in
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 200, y: 0, width: 200, height: 200))
        }
        let cropped = try CropRenderer.crop(image, to: CGRect(x: 250.4, y: 10, width: 100.2, height: 50))
        XCTAssertEqual(cropped.width, 100)
        XCTAssertEqual(cropped.height, 50)
        let pixel = try pixelColor(cropped, x: 50, y: 25)
        XCTAssertGreaterThan(pixel.b, 200)
        XCTAssertLessThan(pixel.r, 50)
    }

    func testSaveWritesCroppedFileNextToSource() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Shot.jpg")
        let image = try makeImage(width: 300, height: 200) { ctx in
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        }
        try await ImageFile.write(image, to: source, format: .jpg)

        let out = try await CropRenderer.save(image, cropping: CGRect(x: 0, y: 0, width: 120, height: 80), source: source)
        XCTAssertEqual(out.lastPathComponent, "Shot Cropped.jpg")
        let written = try ImageFile.load(out)
        XCTAssertEqual(written.width, 120)
        XCTAssertEqual(written.height, 80)

        let second = try await CropRenderer.save(image, cropping: CGRect(x: 0, y: 0, width: 50, height: 50), source: source)
        XCTAssertEqual(second.lastPathComponent, "Shot Cropped 2.jpg")
    }

    func testUnknownFormatFallsBackToPNG() {
        XCTAssertEqual(CropRenderer.writableFormat(for: URL(fileURLWithPath: "/tmp/a.xyz")), .png)
        XCTAssertEqual(CropRenderer.writableFormat(for: URL(fileURLWithPath: "/tmp/a.HEIC")), .heic)
    }
}

final class BackgroundRendererTests: XCTestCase {
    let image = CGSize(width: 1000, height: 500)

    func testCanvasSizeForEachRatio() {
        let pad: CGFloat = 50 // padded image is 1100 x 600
        XCTAssertEqual(BackgroundRenderer.canvasSize(imageSize: image, padding: pad, ratio: .auto), CGSize(width: 1100, height: 600))
        XCTAssertEqual(BackgroundRenderer.canvasSize(imageSize: image, padding: pad, ratio: .square), CGSize(width: 1100, height: 1100))
        XCTAssertEqual(BackgroundRenderer.canvasSize(imageSize: image, padding: pad, ratio: .wide), CGSize(width: 1100, height: 619))
        XCTAssertEqual(BackgroundRenderer.canvasSize(imageSize: image, padding: pad, ratio: .standard), CGSize(width: 1100, height: 825))
        XCTAssertEqual(BackgroundRenderer.canvasSize(imageSize: image, padding: pad, ratio: .portrait), CGSize(width: 1100, height: 1375))

        // A tall image grows sideways instead.
        let tall = BackgroundRenderer.canvasSize(imageSize: CGSize(width: 400, height: 1000), padding: 0, ratio: .wide)
        XCTAssertEqual(tall, CGSize(width: 1778, height: 1000))

        // Every ratio contains the padded image.
        for ratio in CanvasRatio.allCases {
            let c = BackgroundRenderer.canvasSize(imageSize: image, padding: pad, ratio: ratio)
            XCTAssertGreaterThanOrEqual(c.width, 1100)
            XCTAssertGreaterThanOrEqual(c.height, 600)
        }
    }

    func testImageIsCentered() {
        let rect = BackgroundRenderer.imageRect(imageSize: image, canvasSize: CGSize(width: 1100, height: 1100))
        XCTAssertEqual(rect, CGRect(x: 50, y: 300, width: 1000, height: 500))
    }

    func testRenderSizesAndPreviewScale() throws {
        let source = try makeImage(width: 1000, height: 500) { ctx in
            ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 500))
        }
        for fill in try fills() {
            let settings = BackgroundSettings(fill: fill, padding: 100, cornerRadius: 40, shadow: 30, ratio: .square)
            let full = try XCTUnwrap(BackgroundRenderer.render(source, settings: settings))
            XCTAssertEqual(full.width, 1200)
            XCTAssertEqual(full.height, 1200)

            // Preview from a downscaled copy at a quarter scale: same composition, smaller.
            let small = try makeImage(width: 250, height: 125) { ctx in
                ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 250, height: 125))
            }
            let preview = try XCTUnwrap(BackgroundRenderer.render(small, logicalSize: CGSize(width: 1000, height: 500), settings: settings, scale: 0.25))
            XCTAssertEqual(preview.width, 300)
            XCTAssertEqual(preview.height, 300)
        }
    }

    func testRenderPlacesImageAndFill() throws {
        let source = try makeImage(width: 100, height: 100) { ctx in
            ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let settings = BackgroundSettings(fill: .solid(RGBA(hex: 0xFF0000)), padding: 50, cornerRadius: 0, shadow: 0)
        let out = try XCTUnwrap(BackgroundRenderer.render(source, settings: settings))
        XCTAssertEqual(out.width, 200)
        let corner = try pixelColor(out, x: 5, y: 5)
        XCTAssertEqual(corner.r, 255); XCTAssertEqual(corner.g, 0)
        let center = try pixelColor(out, x: 100, y: 100)
        // The test image's green is generic RGB, so allow for conversion to sRGB.
        XCTAssertGreaterThan(center.g, 240); XCTAssertLessThan(center.r, 20)

        let clear = BackgroundSettings(fill: .clear, padding: 50, cornerRadius: 0, shadow: 0)
        let transparent = try XCTUnwrap(BackgroundRenderer.render(source, settings: clear))
        XCTAssertEqual(try pixelColor(transparent, x: 5, y: 5).a, 0)
    }

    func testSaveWritesPNGWithSuffix() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Page 001.jpg")
        let image = try makeImage(width: 200, height: 100) { ctx in
            ctx.setFillColor(CGColor(gray: 0.3, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        let settings = BackgroundSettings.defaults(for: CGSize(width: 200, height: 100))
        let out = try await BackgroundRenderer.save(image, settings: settings, source: source)
        XCTAssertEqual(out.lastPathComponent, "Page 001 With Background.png")
        let written = try ImageFile.load(out)
        let expected = BackgroundRenderer.canvasSize(imageSize: CGSize(width: 200, height: 100), padding: settings.padding, ratio: .auto)
        XCTAssertEqual(CGSize(width: written.width, height: written.height), expected)
    }

    func testGradientSwatchesRender() {
        for gradient in BackgroundRenderer.gradients {
            XCTAssertNotNil(BackgroundRenderer.swatch(.gradient(gradient), pixelSize: 32), gradient.name)
        }
    }

    private func fills() throws -> [BackgroundFill] {
        let tile = try makeImage(width: 64, height: 32) { ctx in
            ctx.setFillColor(CGColor(gray: 0.8, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        }
        return [.clear, .solid(RGBA(hex: 0x123456)), .gradient(BackgroundRenderer.gradients[0]), .image(tile)]
    }
}

// MARK: - Helpers

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeImage(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
    let ctx = try XCTUnwrap(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    draw(ctx)
    return try XCTUnwrap(ctx.makeImage())
}

/// RGBA bytes at (x, y) with a top-left origin.
private func pixelColor(_ image: CGImage, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int, a: Int) {
    var data = [UInt8](repeating: 0, count: 4)
    let ctx = try XCTUnwrap(CGContext(
        data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    // Shift the image so that pixel (x, y) lands on the 1×1 context.
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(data[0]), Int(data[1]), Int(data[2]), Int(data[3]))
}

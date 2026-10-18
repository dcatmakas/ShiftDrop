import CoreGraphics
import Foundation

/// An sRGB color with components in 0...1.
public struct RGBA: Hashable, Sendable {
    public var r, g, b, a: CGFloat

    public init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `RGBA(hex: 0xF0531C)`
    public init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255, alpha
        )
    }

    public var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
    }
}

/// A soft radial glow laid over a gradient. Coordinates are 0...1 of the canvas, top-left origin.
public struct GradientBlob: Hashable, Sendable {
    public var x, y: CGFloat
    /// Radius as a fraction of the canvas's longer side.
    public var radius: CGFloat
    public var color: RGBA

    public init(x: CGFloat, y: CGFloat, radius: CGFloat, color: RGBA) {
        self.x = x; self.y = y; self.radius = radius; self.color = color
    }
}

/// A linear gradient plus optional glows, which reads like the macOS wallpapers.
public struct BackgroundGradient: Hashable, Sendable, Identifiable {
    public var name: String
    public var stops: [RGBA]
    /// Degrees. 0 runs left → right, 90 runs top → bottom.
    public var angle: CGFloat
    public var blobs: [GradientBlob]

    public var id: String { name }

    public init(name: String, stops: [RGBA], angle: CGFloat, blobs: [GradientBlob] = []) {
        self.name = name; self.stops = stops; self.angle = angle; self.blobs = blobs
    }
}

public enum BackgroundFill {
    case clear
    case solid(RGBA)
    case gradient(BackgroundGradient)
    /// Scaled to cover the whole canvas.
    case image(CGImage)
}

/// Canvas shapes for "Add BG". Auto hugs the padded image.
public enum CanvasRatio: String, CaseIterable, Identifiable, Sendable {
    case auto, square, wide, standard, portrait

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .square: return "1:1"
        case .wide: return "16:9"
        case .standard: return "4:3"
        case .portrait: return "4:5"
        }
    }

    public var ratio: CGFloat? {
        switch self {
        case .auto: return nil
        case .square: return 1
        case .wide: return 16.0 / 9.0
        case .standard: return 4.0 / 3.0
        case .portrait: return 4.0 / 5.0
        }
    }
}

/// Settings of the "Add BG" editor. Lengths are in pixels of the full-size image.
public struct BackgroundSettings {
    public var fill: BackgroundFill
    public var padding: CGFloat
    public var cornerRadius: CGFloat
    public var shadow: CGFloat
    public var ratio: CanvasRatio

    public init(fill: BackgroundFill, padding: CGFloat, cornerRadius: CGFloat, shadow: CGFloat, ratio: CanvasRatio = .auto) {
        self.fill = fill; self.padding = padding; self.cornerRadius = cornerRadius
        self.shadow = shadow; self.ratio = ratio
    }

    /// Sensible starting point for an image of `size`.
    public static func defaults(for size: CGSize) -> BackgroundSettings {
        BackgroundSettings(
            fill: .gradient(BackgroundRenderer.gradients[0]),
            padding: BackgroundRenderer.defaultPadding(for: size),
            cornerRadius: 24, shadow: 24
        )
    }
}

/// Places an image on a background with padding, rounded corners and a drop shadow.
/// The editor preview and the saved file both come from `render`, so they always match.
public enum BackgroundRenderer {
    public static func defaultPadding(for size: CGSize) -> CGFloat {
        (max(size.width, size.height) * 0.08).rounded()
    }

    /// Full canvas size for an image of `imageSize`, in the same units.
    public static func canvasSize(imageSize: CGSize, padding: CGFloat, ratio: CanvasRatio) -> CGSize {
        var size = CGSize(width: imageSize.width + padding * 2, height: imageSize.height + padding * 2)
        if let r = ratio.ratio {
            if size.width / size.height < r {
                size.width = size.height * r
            } else {
                size.height = size.width / r
            }
        }
        return CGSize(width: size.width.rounded(), height: size.height.rounded())
    }

    /// Where the image sits on the canvas (centered), top-left origin.
    public static func imageRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
        CGRect(
            x: (canvasSize.width - imageSize.width) / 2, y: (canvasSize.height - imageSize.height) / 2,
            width: imageSize.width, height: imageSize.height
        )
    }

    /// Renders the composition.
    /// - Parameters:
    ///   - image: The pixels to place. May be a downscaled preview of the real image.
    ///   - logicalSize: Size of the full image that `settings` lengths refer to. Defaults to `image`'s size.
    ///   - scale: Output pixels per logical pixel (1 = full resolution).
    public static func render(
        _ image: CGImage, logicalSize: CGSize? = nil, settings style: BackgroundSettings, scale: CGFloat = 1
    ) -> CGImage? {
        let imageSize = logicalSize ?? CGSize(width: image.width, height: image.height)
        let canvas = canvasSize(imageSize: imageSize, padding: style.padding, ratio: style.ratio)
        let width = max(1, Int((canvas.width * scale).rounded()))
        let height = max(1, Int((canvas.height * scale).rounded()))

        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Work in logical units with a top-left origin, like the editor.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(width) / canvas.width, y: -CGFloat(height) / canvas.height)
        ctx.interpolationQuality = .high

        let canvasRect = CGRect(origin: .zero, size: canvas)
        drawFill(style.fill, in: canvasRect, context: ctx)

        let rect = imageRect(imageSize: imageSize, canvasSize: canvas)
        let radius = min(style.cornerRadius, rect.width / 2, rect.height / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        if style.shadow > 0 {
            // Shadow geometry ignores the CTM, so convert logical lengths to device pixels.
            let pixelScale = CGFloat(width) / canvas.width
            ctx.setShadow(
                offset: CGSize(width: 0, height: -style.shadow * 0.35 * pixelScale),
                blur: style.shadow * pixelScale,
                color: CGColor(gray: 0, alpha: 0.35)
            )
        }
        // A transparency layer makes the shadow follow the clipped image, including its own alpha.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(path)
        ctx.clip()
        drawUpright(image, in: rect, context: ctx)
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Writes `<name> With Background.png` next to `source` at full resolution.
    @discardableResult
    public static func save(_ image: CGImage, settings: BackgroundSettings, source: URL) async throws -> URL {
        guard let output = render(image, settings: settings) else {
            throw ShiftDropError.unsupported("rendering the background")
        }
        let out = OutputNamer.url(for: source, suffix: "With Background", ext: "png")
        try await ImageFile.write(output, to: out, format: .png)
        return out
    }

    /// Just the background, for swatch thumbnails.
    public static func swatch(_ fill: BackgroundFill, pixelSize: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(pixelSize))
        ctx.scaleBy(x: 1, y: -1)
        drawFill(fill, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize), context: ctx)
        return ctx.makeImage()
    }

    // MARK: - Drawing

    /// Draws a CGImage in a flipped (top-left origin) context without turning it upside down.
    static func drawUpright(_ image: CGImage, in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    static func drawFill(_ fill: BackgroundFill, in rect: CGRect, context ctx: CGContext) {
        switch fill {
        case .clear:
            break
        case .solid(let color):
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        case .image(let image):
            let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
            ctx.saveGState()
            ctx.clip(to: rect)
            drawUpright(image, in: target, context: ctx)
            ctx.restoreGState()
        case .gradient(let gradient):
            drawGradient(gradient, in: rect, context: ctx)
        }
    }

    static func drawGradient(_ gradient: BackgroundGradient, in rect: CGRect, context ctx: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = gradient.stops.map(\.cgColor) as CFArray
        guard let linear = CGGradient(colorsSpace: space, colors: colors, locations: nil) else { return }

        // Line through the center at `angle`, long enough to span the rectangle.
        let radians = gradient.angle * .pi / 180
        let dx = cos(radians), dy = sin(radians)
        let half = (abs(rect.width * dx) + abs(rect.height * dy)) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(
            linear,
            start: CGPoint(x: center.x - dx * half, y: center.y - dy * half),
            end: CGPoint(x: center.x + dx * half, y: center.y + dy * half),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        let longSide = max(rect.width, rect.height)
        for blob in gradient.blobs {
            var clearColor = blob.color
            clearColor.a = 0
            guard let radial = CGGradient(
                colorsSpace: space, colors: [blob.color.cgColor, clearColor.cgColor] as CFArray, locations: [0, 1]
            ) else { continue }
            let point = CGPoint(x: rect.minX + blob.x * rect.width, y: rect.minY + blob.y * rect.height)
            ctx.drawRadialGradient(radial, startCenter: point, startRadius: 0, endCenter: point, endRadius: blob.radius * longSide, options: [])
        }
        ctx.restoreGState()
    }

    // MARK: - Presets

    public static let gradients: [BackgroundGradient] = [
        BackgroundGradient(
            name: "Sonoma", stops: [RGBA(hex: 0xF9484A), RGBA(hex: 0xFBA34B), RGBA(hex: 0xFBD72B)], angle: 300,
            blobs: [GradientBlob(x: 0.85, y: 0.95, radius: 0.6, color: RGBA(hex: 0x9C8CF2, alpha: 0.9))]
        ),
        BackgroundGradient(name: "Sunset", stops: [RGBA(hex: 0xFF5F6D), RGBA(hex: 0xFFC371)], angle: 45),
        BackgroundGradient(
            name: "Big Sur", stops: [RGBA(hex: 0x3A1C71), RGBA(hex: 0xD76D77), RGBA(hex: 0xFFAF7B)], angle: 120,
            blobs: [GradientBlob(x: 0.1, y: 0.1, radius: 0.5, color: RGBA(hex: 0x4F6CF0, alpha: 0.7))]
        ),
        BackgroundGradient(name: "Indigo", stops: [RGBA(hex: 0x667EEA), RGBA(hex: 0x764BA2)], angle: 45),
        BackgroundGradient(name: "Ocean", stops: [RGBA(hex: 0x2193B0), RGBA(hex: 0x6DD5ED)], angle: 60),
        BackgroundGradient(name: "Pastel", stops: [RGBA(hex: 0xFBC2EB), RGBA(hex: 0xA6C1EE)], angle: 30),
        BackgroundGradient(name: "Peach", stops: [RGBA(hex: 0xFFECD2), RGBA(hex: 0xFCB69F)], angle: 60),
        BackgroundGradient(name: "Mint", stops: [RGBA(hex: 0x84FAB0), RGBA(hex: 0x8FD3F4)], angle: 45),
        BackgroundGradient(name: "Lavender", stops: [RGBA(hex: 0xE0C3FC), RGBA(hex: 0x8EC5FC)], angle: 45),
        BackgroundGradient(
            name: "Aurora", stops: [RGBA(hex: 0x0F2027), RGBA(hex: 0x203A43), RGBA(hex: 0x2C5364)], angle: 90,
            blobs: [GradientBlob(x: 0.2, y: 0.85, radius: 0.55, color: RGBA(hex: 0x38EF7D, alpha: 0.45))]
        ),
        BackgroundGradient(
            name: "Graphite", stops: [RGBA(hex: 0x232526), RGBA(hex: 0x414345)], angle: 90,
            blobs: [GradientBlob(x: 0.8, y: 0.15, radius: 0.5, color: RGBA(hex: 0x6E6E73, alpha: 0.5))]
        ),
    ]

    public static let solids: [RGBA] = [
        RGBA(hex: 0xFFFFFF), RGBA(hex: 0xF2F2F7), RGBA(hex: 0x8E8E93), RGBA(hex: 0x1C1C1E), RGBA(hex: 0x000000),
        RGBA(hex: 0xF0531C), RGBA(hex: 0xFFCC00), RGBA(hex: 0x34C759), RGBA(hex: 0x30B0C7), RGBA(hex: 0x007AFF),
        RGBA(hex: 0x5856D6), RGBA(hex: 0xFF2D55),
    ]
}

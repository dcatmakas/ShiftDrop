import CoreGraphics
import Foundation

/// Aspect ratios offered by the crop editor.
public enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case free, square, wide, tall, standard, portrait

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .wide: return "16:9"
        case .tall: return "9:16"
        case .standard: return "4:3"
        case .portrait: return "3:4"
        }
    }

    /// Width divided by height, or nil for free cropping.
    public var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .wide: return 16.0 / 9.0
        case .tall: return 9.0 / 16.0
        case .standard: return 4.0 / 3.0
        case .portrait: return 3.0 / 4.0
        }
    }
}

/// The eight grab points around the crop rectangle.
public enum CropHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }

    /// Position of the handle on `rect`, in the same (top-left origin) coordinates.
    public func point(in rect: CGRect) -> CGPoint {
        let x = movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX
        let y = movesTop ? rect.minY : movesBottom ? rect.maxY : rect.midY
        return CGPoint(x: x, y: y)
    }
}

/// Crop rectangle math in image pixels, with a top-left origin (like CGImage.cropping).
public enum CropGeometry {
    public static let minSize: CGFloat = 16

    /// The largest rectangle with `ratio` (width / height) centered in `bounds`.
    public static func fit(ratio: CGFloat?, in bounds: CGSize) -> CGRect {
        guard let ratio, ratio > 0 else { return CGRect(origin: .zero, size: bounds) }
        var size = bounds
        if bounds.width / bounds.height > ratio {
            size.width = bounds.height * ratio
        } else {
            size.height = bounds.width / ratio
        }
        return CGRect(
            x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }

    /// Slides `start` by `translation`, keeping it inside `bounds`.
    public static func move(_ start: CGRect, by translation: CGSize, bounds: CGSize) -> CGRect {
        var rect = start
        rect.origin.x = min(max(0, start.minX + translation.width), bounds.width - start.width)
        rect.origin.y = min(max(0, start.minY + translation.height), bounds.height - start.height)
        return rect
    }

    /// Drags one handle of `start` by `translation`. With a ratio, corners keep the opposite
    /// corner fixed and edges keep the rectangle centered on the other axis.
    public static func resize(
        _ start: CGRect, handle: CropHandle, by translation: CGSize,
        ratio: CGFloat?, bounds: CGSize
    ) -> CGRect {
        let minSize = min(Self.minSize, bounds.width, bounds.height)
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        if handle.movesLeft { minX = min(max(0, start.minX + translation.width), maxX - minSize) }
        if handle.movesRight { maxX = max(min(bounds.width, start.maxX + translation.width), minX + minSize) }
        if handle.movesTop { minY = min(max(0, start.minY + translation.height), maxY - minSize) }
        if handle.movesBottom { maxY = max(min(bounds.height, start.maxY + translation.height), minY + minSize) }
        let free = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        guard let ratio, ratio > 0 else { return free }
        let minWidth = minSize * max(1, ratio)

        if handle.isCorner {
            let anchorX = handle.movesLeft ? start.maxX : start.minX
            let anchorY = handle.movesTop ? start.maxY : start.minY
            let roomX = handle.movesLeft ? anchorX : bounds.width - anchorX
            let roomY = handle.movesTop ? anchorY : bounds.height - anchorY
            // Average both axes so dragging diagonally, horizontally or vertically all feel natural.
            var width = (free.width + free.height * ratio) / 2
            width = min(max(width, minWidth), roomX, roomY * ratio)
            let height = width / ratio
            return CGRect(
                x: handle.movesLeft ? anchorX - width : anchorX,
                y: handle.movesTop ? anchorY - height : anchorY,
                width: width, height: height
            )
        }

        if handle.movesTop || handle.movesBottom {
            var height = free.height
            var width = height * ratio
            if width > bounds.width { width = bounds.width; height = width / ratio }
            let y = handle.movesTop ? start.maxY - height : start.minY
            let x = min(max(0, start.midX - width / 2), bounds.width - width)
            return CGRect(x: x, y: y, width: width, height: height)
        } else {
            var width = free.width
            var height = width / ratio
            if height > bounds.height { height = bounds.height; width = height * ratio }
            let x = handle.movesLeft ? start.maxX - width : start.minX
            let y = min(max(0, start.midY - height / 2), bounds.height - height)
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    /// Sets an exact size (from the W / H fields), keeping the center and staying inside `bounds`.
    public static func resized(_ rect: CGRect, width: CGFloat, height: CGFloat, bounds: CGSize) -> CGRect {
        let w = min(max(1, width), bounds.width)
        let h = min(max(1, height), bounds.height)
        let x = min(max(0, rect.midX - w / 2), bounds.width - w)
        let y = min(max(0, rect.midY - h / 2), bounds.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Whole pixels, inside the image.
    public static func pixelRect(_ rect: CGRect, bounds: CGSize) -> CGRect {
        let full = CGRect(origin: .zero, size: bounds)
        let r = CGRect(
            x: rect.minX.rounded(), y: rect.minY.rounded(),
            width: rect.width.rounded(), height: rect.height.rounded()
        ).intersection(full)
        return r.isNull || r.isEmpty ? full : r
    }
}

public enum CropRenderer {
    /// Crops `image` (already upright) to `rect` in top-left pixel coordinates.
    public static func crop(_ image: CGImage, to rect: CGRect) throws -> CGImage {
        let bounds = CGSize(width: image.width, height: image.height)
        let pixels = CropGeometry.pixelRect(rect, bounds: bounds)
        guard let cropped = image.cropping(to: pixels) else {
            throw ShiftDropError.unsupported("cropping to \(Int(pixels.width))×\(Int(pixels.height))")
        }
        return cropped
    }

    /// Writes `<name> Cropped.<ext>` next to `source`, keeping its format and metadata.
    @discardableResult
    public static func save(_ image: CGImage, cropping rect: CGRect, source: URL) async throws -> URL {
        let cropped = try crop(image, to: rect)
        let format = writableFormat(for: source)
        let out = OutputNamer.url(for: source, suffix: "Cropped", ext: format.fileExtension)
        try await ImageFile.write(cropped, to: out, format: format, properties: ImageFile.properties(of: source))
        return out
    }

    /// The source's format if we can write it, otherwise PNG.
    static func writableFormat(for source: URL) -> Format {
        guard let format = Format(fileExtension: source.pathExtension), format.kind == .image else { return .png }
        if format == .webp && !Shell.canWriteWebP { return .png }
        return format
    }
}

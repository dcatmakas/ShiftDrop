import Foundation
import UniformTypeIdentifiers

/// Broad family of a file. Decides which ring items are offered.
public enum FileKind: String, Sendable {
    case image, pdf, document, video, audio, other

    public static func of(_ url: URL) -> FileKind {
        if let format = Format(fileExtension: url.pathExtension) {
            return format.kind
        }
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .svg) { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .other
    }
}

/// A file format ShiftDrop can read and/or write.
public enum Format: String, CaseIterable, Sendable {
    // Images
    case png, jpg, heic, webp, avif, tiff, bmp, gif
    // Documents
    case pdf, txt, docx, doc, rtf, html, odt, md
    // Video & audio
    case mp4, mov, m4v, m4a, wav, aiff, mp3, caf

    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg", "jpe": self = .jpg
        case "heic", "heif": self = .heic
        case "webp": self = .webp
        case "avif": self = .avif
        case "tif", "tiff": self = .tiff
        case "bmp": self = .bmp
        case "gif": self = .gif
        case "pdf": self = .pdf
        case "txt", "text": self = .txt
        case "docx": self = .docx
        case "doc": self = .doc
        case "rtf": self = .rtf
        case "html", "htm": self = .html
        case "odt": self = .odt
        case "md", "markdown": self = .md
        case "mp4": self = .mp4
        case "mov", "qt": self = .mov
        case "m4v": self = .m4v
        case "m4a": self = .m4a
        case "wav", "wave": self = .wav
        case "aif", "aiff": self = .aiff
        case "mp3": self = .mp3
        case "caf": self = .caf
        default: return nil
        }
    }

    public var fileExtension: String { rawValue }

    /// Text shown on the ring segment.
    public var label: String { rawValue.uppercased() }

    public var kind: FileKind {
        switch self {
        case .png, .jpg, .heic, .webp, .avif, .tiff, .bmp, .gif: return .image
        case .pdf: return .pdf
        case .txt, .docx, .doc, .rtf, .html, .odt, .md: return .document
        case .mp4, .mov, .m4v: return .video
        case .m4a, .wav, .aiff, .mp3, .caf: return .audio
        }
    }

    /// ImageIO type identifier used when writing this format, if ImageIO can write it.
    var imageIOType: String? {
        switch self {
        case .png: return UTType.png.identifier
        case .jpg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .avif: return "public.avif"
        case .tiff: return UTType.tiff.identifier
        case .bmp: return UTType.bmp.identifier
        case .gif: return UTType.gif.identifier
        default: return nil
        }
    }

    /// Whether the format can store transparency.
    var supportsAlpha: Bool {
        switch self {
        case .jpg, .bmp: return false
        default: return true
        }
    }

    /// Whether the format uses lossy compression (quality setting applies).
    var isLossy: Bool {
        switch self {
        case .jpg, .heic, .webp, .avif: return true
        default: return false
        }
    }
}

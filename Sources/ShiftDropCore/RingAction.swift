import Foundation

/// The two pages of the ring. Pressing Shift again during a drag flips between them.
public enum RingMode: Sendable {
    case convert, tools

    public var toggled: RingMode { self == .convert ? .tools : .convert }
}

/// Single-purpose operations on the "tools" page of the ring.
public enum Tool: String, CaseIterable, Sendable {
    case compress
    case removeBackground
    case addBackground
    case crop
    case stripMetadata
    case copyText
    case makePDF
    case mergePDF
    case splitPDF
    case mute
    case zip

    public var title: String {
        switch self {
        case .compress: return "COMPRESS"
        case .removeBackground: return "REMOVE BG"
        case .addBackground: return "ADD BG"
        case .crop: return "CROP"
        case .stripMetadata: return "STRIP EXIF"
        case .copyText: return "COPY TEXT"
        case .makePDF: return "MAKE PDF"
        case .mergePDF: return "MERGE"
        case .splitPDF: return "SPLIT"
        case .mute: return "MUTE"
        case .zip: return "ZIP"
        }
    }

    /// SF Symbol drawn above the title.
    public var symbol: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .removeBackground: return "person.crop.rectangle"
        case .addBackground: return "photo.on.rectangle"
        case .crop: return "crop"
        case .stripMetadata: return "eye.slash"
        case .copyText: return "text.viewfinder"
        case .makePDF: return "doc.richtext"
        case .mergePDF: return "rectangle.stack"
        case .splitPDF: return "square.split.2x1"
        case .mute: return "speaker.slash"
        case .zip: return "archivebox"
        }
    }

    /// Tools that open a window instead of finishing right away.
    public var isInteractive: Bool {
        self == .crop || self == .addBackground
    }
}

public enum ActionKind: Hashable, Sendable {
    case convert(Format)
    case tool(Tool)
}

/// One segment of the ring.
public struct RingAction: Identifiable, Hashable, Sendable {
    public let kind: ActionKind

    public init(_ kind: ActionKind) { self.kind = kind }

    public var id: String {
        switch kind {
        case .convert(let format): return "convert.\(format.rawValue)"
        case .tool(let tool): return "tool.\(tool.rawValue)"
        }
    }

    public var title: String {
        switch kind {
        case .convert(let format): return format.label
        case .tool(let tool): return tool.title
        }
    }

    public var symbol: String? {
        switch kind {
        case .convert: return nil
        case .tool(let tool): return tool.symbol
        }
    }
}

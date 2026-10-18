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
        case .compress: return "Compress"
        case .removeBackground: return "Remove background"
        case .addBackground: return "Add background"
        case .crop: return "Crop"
        case .stripMetadata: return "Remove EXIF"
        case .copyText: return "Copy text"
        case .makePDF: return "Make PDF"
        case .mergePDF: return "Merge"
        case .splitPDF: return "Split pages"
        case .mute: return "Mute"
        case .zip: return "Zip"
        }
    }

    /// One line shown in the middle of the ring while hovering.
    public var hint: String {
        switch self {
        case .compress: return "Smaller copy, same look"
        case .removeBackground: return "Transparent PNG of the subject"
        case .addBackground: return "Opens the background editor"
        case .crop: return "Opens the crop editor"
        case .stripMetadata: return "Drops location and camera info"
        case .copyText: return "Puts the text on the clipboard"
        case .makePDF: return "One PDF, a page per image"
        case .mergePDF: return "Joins the PDFs into one"
        case .splitPDF: return "A separate PDF per page"
        case .mute: return "Removes the sound"
        case .zip: return "Packs into a .zip archive"
        }
    }

    /// SF Symbol drawn above the title.
    public var symbol: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .removeBackground: return "person.and.background.dotted"
        case .addBackground: return "photo.artframe"
        case .crop: return "crop"
        case .stripMetadata: return "location.slash"
        case .copyText: return "text.viewfinder"
        case .makePDF: return "doc.on.doc"
        case .mergePDF: return "rectangle.stack"
        case .splitPDF: return "rectangle.split.3x1"
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

    /// Short explanation of the result, for the middle of the ring.
    public func hint(for source: FileKind) -> String {
        switch kind {
        case .tool(let tool): return tool.hint
        case .convert(let format): return format.hint(from: source)
        }
    }
}

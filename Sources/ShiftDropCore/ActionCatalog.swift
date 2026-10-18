import Foundation

/// Decides which ring segments to show for the dragged files.
public enum ActionCatalog {
    /// More than this does not fit around the ring legibly.
    public static let maxItems = 8

    public static func actions(for urls: [URL], mode: RingMode) -> [RingAction] {
        guard !urls.isEmpty else { return [] }
        let items: [ActionKind]
        switch mode {
        case .convert: items = convertTargets(for: urls).map { .convert($0) }
        case .tools: items = tools(for: urls).map { .tool($0) }
        }
        return Array(items.prefix(maxItems)).map(RingAction.init)
    }

    // MARK: - Convert

    static func convertTargets(for urls: [URL]) -> [Format] {
        // Only offer formats every dragged file can be turned into, in the order of the first file.
        var common: [Format]? = nil
        for url in urls {
            let targets = convertTargets(for: url)
            common = common.map { current in current.filter(targets.contains) } ?? targets
        }
        return common ?? []
    }

    static func convertTargets(for url: URL) -> [Format] {
        let source = Format(fileExtension: url.pathExtension)
        let candidates: [Format]
        switch FileKind.of(url) {
        case .image:
            var list: [Format] = [.png, .jpg, .webp, .heic, .avif, .pdf, .tiff, .txt, .gif, .bmp]
            if !Shell.canWriteWebP { list.removeAll { $0 == .webp } }
            candidates = list
        case .pdf:
            candidates = [.docx, .jpg, .png, .txt]
        case .document:
            candidates = [.pdf, .docx, .rtf, .txt, .html, .odt]
        case .video:
            candidates = [.mp4, .mov, .m4a, .gif]
        case .audio:
            candidates = [.m4a, .wav, .aiff, .caf]
        case .other:
            candidates = []
        }
        return candidates.filter { target in
            guard let source else { return true }
            if target == source { return false }
            // m4v is already an mp4 container; offer mov only.
            if source == .m4v && target == .mp4 { return false }
            return true
        }
    }

    // MARK: - Tools

    static func tools(for urls: [URL]) -> [Tool] {
        let kinds = Set(urls.map(FileKind.of))
        let single = urls.count == 1
        guard kinds.count == 1, let kind = kinds.first else { return [.zip] }

        switch kind {
        case .image:
            if single {
                return [.compress, .stripMetadata, .copyText, .removeBackground, .addBackground, .crop, .zip]
            }
            return [.compress, .stripMetadata, .removeBackground, .makePDF, .zip]
        case .pdf:
            return single
                ? [.compress, .copyText, .splitPDF, .zip]
                : [.compress, .mergePDF, .splitPDF, .zip]
        case .document:
            return single ? [.copyText, .zip] : [.zip]
        case .video:
            return [.compress, .mute, .zip]
        case .audio, .other:
            return [.zip]
        }
    }
}

import Foundation

/// What happened after a ring item was used, for the confirmation bubble.
public struct RunResult: Sendable {
    public var outputs: [URL] = []
    /// Extra detail, e.g. "1.2 MB → 340 KB".
    public var detail: String?
    /// Set by "Copy Text"; the app puts it on the clipboard.
    public var textToCopy: String?
    /// Inputs that failed while others succeeded.
    public var failures: [(URL, Error)] = []

    public init() {}
}

/// Runs non-interactive ring actions. Crop and Add BG open windows and are handled by the app.
public enum ActionRunner {
    public static func run(_ kind: ActionKind, on urls: [URL]) async throws -> RunResult {
        switch kind {
        case .convert(let format):
            return try await eachFile(urls) { url in try await convert(url, to: format) }
        case .tool(let tool):
            return try await run(tool, on: urls)
        }
    }

    static func convert(_ url: URL, to format: Format) async throws -> [URL] {
        switch FileKind.of(url) {
        case .image: return [try await ImageConverter.convert(url, to: format)]
        case .pdf: return try await PDFConverter.convert(url, to: format)
        case .document: return [try await DocumentConverter.convert(url, to: format)]
        case .video: return [try await MediaConverter.convertVideo(url, to: format)]
        case .audio: return [try await MediaConverter.convertAudio(url, to: format)]
        case .other: throw ShiftDropError.unsupported(url.lastPathComponent)
        }
    }

    static func run(_ tool: Tool, on urls: [URL]) async throws -> RunResult {
        switch tool {
        case .compress:
            var result = try await eachFile(urls) { url -> [URL] in
                switch FileKind.of(url) {
                case .image: return [try await ImageConverter.compress(url)]
                case .pdf: return [try PDFConverter.compress(url)]
                case .video: return [try await MediaConverter.compressVideo(url)]
                default: throw ShiftDropError.unsupported("compressing \(url.pathExtension)")
                }
            }
            let before = urls.reduce(Int64(0)) { $0 + $1.fileSize }
            let after = result.outputs.reduce(Int64(0)) { $0 + $1.fileSize }
            if after > 0 { result.detail = "\(ByteFormat.string(before)) → \(ByteFormat.string(after))" }
            return result

        case .stripMetadata:
            return try await eachFile(urls) { [try await ImageConverter.stripMetadata($0)] }

        case .removeBackground:
            return try await eachFile(urls) { [try ImageConverter.removeBackground($0)] }

        case .copyText:
            guard let url = urls.first else { return RunResult() }
            let text: String
            switch FileKind.of(url) {
            case .image:
                text = try VisionTasks.recognizeText(in: try ImageFile.load(url))
            case .pdf:
                text = try PDFConverter.text(of: url)
            case .document:
                text = try await DocumentConverter.plainText(of: url)
            default:
                throw ShiftDropError.unsupported("text from \(url.pathExtension)")
            }
            guard !text.isEmpty else { throw ShiftDropError.noText }
            var result = RunResult()
            result.textToCopy = text
            let words = text.split { $0.isWhitespace || $0.isNewline }.count
            result.detail = "Copied \(words) words"
            return result

        case .makePDF:
            guard let first = urls.first else { return RunResult() }
            let out = OutputNamer.url(for: first, suffix: "Combined", ext: "pdf")
            var result = RunResult()
            result.outputs = [try ImageConverter.makePDF(from: urls, output: out)]
            return result

        case .mergePDF:
            var result = RunResult()
            result.outputs = [try PDFConverter.merge(urls)]
            return result

        case .splitPDF:
            return try await eachFile(urls) { [try PDFConverter.split($0)] }

        case .mute:
            return try await eachFile(urls) { [try await MediaConverter.mute($0)] }

        case .zip:
            var result = RunResult()
            result.outputs = [try await Archiver.zip(urls)]
            return result

        case .crop, .addBackground:
            throw ShiftDropError.unsupported("\(tool.title) needs its editor window")
        }
    }

    /// Runs `work` for every file. Throws only if every file failed.
    static func eachFile(_ urls: [URL], _ work: (URL) async throws -> [URL]) async throws -> RunResult {
        var result = RunResult()
        for url in urls {
            do {
                result.outputs += try await work(url)
            } catch {
                result.failures.append((url, error))
            }
        }
        if result.outputs.isEmpty, let (_, error) = result.failures.first {
            throw error
        }
        return result
    }
}

public enum Archiver {
    /// One file or folder -> `Name.zip`; several -> `Archive.zip` next to the first one.
    public static func zip(_ urls: [URL]) async throws -> URL {
        guard let first = urls.first else { throw ShiftDropError.nothingFound("Nothing to zip") }
        if urls.count == 1 {
            let out = OutputNamer.unique(first.deletingPathExtension().appendingPathExtension("zip"))
            try await Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, out.path])
            return out
        }
        // ditto archives a single item, so stage the files in a temporary folder first.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Archive")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging.deletingLastPathComponent()) }
        for url in urls {
            try FileManager.default.copyItem(at: url, to: OutputNamer.unique(staging.appendingPathComponent(url.lastPathComponent)))
        }
        let out = OutputNamer.unique(first.deletingLastPathComponent().appendingPathComponent("Archive.zip"))
        try await Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", staging.path, out.path])
        return out
    }
}

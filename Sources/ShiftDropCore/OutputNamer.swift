import Foundation

/// Picks where results are written: next to the source, never overwriting anything.
public enum OutputNamer {
    /// `Photo.png` + suffix "Cropped" + ext "png" -> `Photo Cropped.png`,
    /// or `Photo Cropped 2.png` if that already exists.
    public static func url(for source: URL, suffix: String? = nil, ext: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? source.deletingLastPathComponent()
        var base = source.deletingPathExtension().lastPathComponent
        if let suffix, !suffix.isEmpty { base += " \(suffix)" }
        return unique(dir.appendingPathComponent(base).appendingPathExtension(ext))
    }

    /// Returns `url`, or `name 2.ext`, `name 3.ext`... if it is taken.
    public static func unique(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            var candidate = dir.appendingPathComponent("\(base) \(n)")
            if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext) }
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// A new folder next to `source`, used when one input produces many files (PDF pages).
    public static func folder(for source: URL, suffix: String) throws -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let dir = unique(source.deletingLastPathComponent().appendingPathComponent("\(base) \(suffix)"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

public extension URL {
    var fileSize: Int64 {
        (try? resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }
}

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

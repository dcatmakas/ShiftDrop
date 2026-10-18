import Foundation

/// Runs the few command line tools ShiftDrop relies on.
/// `afconvert` and `ditto` ship with macOS; `cwebp` is optional (Homebrew `webp`).
enum Shell {
    static let cwebpPath: String? = {
        ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static var canWriteWebP: Bool { cwebpPath != nil }

    /// Runs `launchPath` and throws with its stderr if it exits non-zero.
    static func run(_ launchPath: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { p in
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let message = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let name = (launchPath as NSString).lastPathComponent
                    continuation.resume(throwing: ShiftDropError.toolFailed("\(name): \(message)"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

public enum ShiftDropError: LocalizedError {
    case unreadable(URL)
    case unsupported(String)
    case writeFailed(URL)
    case toolFailed(String)
    case noText
    case nothingFound(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): return "Can't read \(url.lastPathComponent)"
        case .unsupported(let what): return "Not supported: \(what)"
        case .writeFailed(let url): return "Couldn't write \(url.lastPathComponent)"
        case .toolFailed(let message): return message
        case .noText: return "No text found"
        case .nothingFound(let what): return what
        }
    }
}

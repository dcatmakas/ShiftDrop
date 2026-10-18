import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Video through AVFoundation, audio through the built-in `afconvert`.
public enum MediaConverter {
    public static func convertVideo(_ url: URL, to format: Format) async throws -> URL {
        let asset = AVURLAsset(url: url)
        switch format {
        case .mp4, .mov:
            let out = OutputNamer.url(for: url, ext: format.fileExtension)
            let type: AVFileType = format == .mp4 ? .mp4 : .mov
            // Re-wrapping the existing streams is instant; re-encode only if the codecs don't fit.
            do {
                try await export(asset, preset: AVAssetExportPresetPassthrough, to: out, type: type)
            } catch {
                try? FileManager.default.removeItem(at: out)
                try await export(asset, preset: AVAssetExportPresetHighestQuality, to: out, type: type)
            }
            return out
        case .m4a:
            let out = OutputNamer.url(for: url, ext: "m4a")
            try await export(asset, preset: AVAssetExportPresetAppleM4A, to: out, type: .m4a)
            return out
        case .gif:
            return try await makeGIF(from: asset, source: url)
        default:
            throw ShiftDropError.unsupported("video to \(format.label)")
        }
    }

    public static func convertAudio(_ url: URL, to format: Format) async throws -> URL {
        let args: [String]
        switch format {
        case .m4a: args = ["-f", "m4af", "-d", "aac", "-b", "256000"]
        case .wav: args = ["-f", "WAVE", "-d", "LEI16"]
        case .aiff: args = ["-f", "AIFF", "-d", "BEI16"]
        case .caf: args = ["-f", "caff", "-d", "LEI16"]
        default: throw ShiftDropError.unsupported("audio to \(format.label)")
        }
        let out = OutputNamer.url(for: url, ext: format.fileExtension)
        try await Shell.run("/usr/bin/afconvert", args + [url.path, out.path])
        return out
    }

    // MARK: - Tools

    /// HEVC at up to 1080p. Usually a fraction of the size of phone or screen recordings.
    public static func compressVideo(_ url: URL) async throws -> URL {
        let out = OutputNamer.url(for: url, suffix: "Compressed", ext: "mp4")
        try await export(AVURLAsset(url: url), preset: AVAssetExportPresetHEVC1920x1080, to: out, type: .mp4)
        return out
    }

    /// Copies the video without its audio tracks.
    public static func mute(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        let duration = try await asset.load(.duration)
        for track in try await asset.loadTracks(withMediaType: .video) {
            guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try target.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
            target.preferredTransform = try await track.load(.preferredTransform)
        }
        let ext = Format(fileExtension: url.pathExtension) == .mov ? "mov" : "mp4"
        let out = OutputNamer.url(for: url, suffix: "Muted", ext: ext)
        try await export(composition, preset: AVAssetExportPresetPassthrough, to: out, type: ext == "mov" ? .mov : .mp4)
        return out
    }

    // MARK: - Helpers

    static func export(_ asset: AVAsset, preset: String, to url: URL, type: AVFileType) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ShiftDropError.unsupported("export preset \(preset)")
        }
        guard session.supportedFileTypes.contains(type) else {
            throw ShiftDropError.unsupported("\(type.rawValue) with \(preset)")
        }
        session.outputURL = url
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        if session.status != .completed {
            throw session.error ?? ShiftDropError.writeFailed(url)
        }
    }

    /// Up to 20 seconds at 12 fps, 640 px wide. GIFs get huge quickly.
    static func makeGIF(from asset: AVAsset, source: URL) async throws -> URL {
        let fps = 12.0
        let duration = min(try await asset.load(.duration).seconds, 20)
        guard duration > 0 else { throw ShiftDropError.unreadable(source) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let frameCount = max(1, Int(duration * fps))
        let out = OutputNamer.url(for: source, ext: "gif")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw ShiftDropError.writeFailed(out)
        }
        let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]]

        for index in 0..<frameCount {
            let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image else { continue }
            CGImageDestinationAddImage(dest, frame, frameProps as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw ShiftDropError.writeFailed(out) }
        return out
    }
}

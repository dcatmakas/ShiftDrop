import AVFoundation
import XCTest
@testable import ShiftDropCore

/// Runs against a real video when SHIFTDROP_SAMPLE_VIDEO points at one; skipped otherwise.
final class MediaSmokeTests: XCTestCase {
    func testVideoAndAudioConversions() async throws {
        guard let path = ProcessInfo.processInfo.environment["SHIFTDROP_SAMPLE_VIDEO"] else {
            throw XCTSkip("Set SHIFTDROP_SAMPLE_VIDEO to a video file to run")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ShiftDropMedia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appendingPathComponent("Clip").appendingPathExtension(URL(fileURLWithPath: path).pathExtension)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: video)

        for target in ActionCatalog.convertTargets(for: video) {
            let out = try await MediaConverter.convertVideo(video, to: target)
            print("video ->", out.lastPathComponent, ByteFormat.string(out.fileSize))
            XCTAssertGreaterThan(out.fileSize, 0)
        }
        let m4a = dir.appendingPathComponent("Clip.m4a")
        for target in ActionCatalog.convertTargets(for: m4a) {
            let out = try await MediaConverter.convertAudio(m4a, to: target)
            print("audio ->", out.lastPathComponent, ByteFormat.string(out.fileSize))
            XCTAssertGreaterThan(out.fileSize, 0)
        }
        let muted = try await MediaConverter.mute(video)
        let audioTracks = try await AVURLAsset(url: muted).loadTracks(withMediaType: .audio)
        XCTAssertTrue(audioTracks.isEmpty)

        let compressed = try await MediaConverter.compressVideo(video)
        print("compress:", ByteFormat.string(video.fileSize), "->", ByteFormat.string(compressed.fileSize))
        XCTAssertGreaterThan(compressed.fileSize, 0)

        // Keep results around for a manual look when asked to.
        if let keep = ProcessInfo.processInfo.environment["SHIFTDROP_KEEP_DIR"] {
            for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                let target = URL(fileURLWithPath: keep).appendingPathComponent(file.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: file, to: target)
            }
        }
    }
}

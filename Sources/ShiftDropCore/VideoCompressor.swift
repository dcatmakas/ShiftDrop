import AVFoundation
import Foundation

/// Re-encodes video as HEVC at a bitrate we choose (Apple's presets often keep the size as is).
/// Long side capped at 1920 px, audio as 128 kbps AAC.
enum VideoCompressor {
    /// Bits per pixel per frame. ~0.06 keeps screen recordings and phone video looking clean in HEVC.
    static let bitsPerPixel: Double = 0.06

    static func compress(_ source: URL, to output: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ShiftDropError.nothingFound("No video track")
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let fps = Double(try await videoTrack.load(.nominalFrameRate))
        let sourceBitrate = Double(try await videoTrack.load(.estimatedDataRate))

        let scale = min(1, 1920 / max(naturalSize.width, naturalSize.height))
        let width = Int((naturalSize.width * scale / 2).rounded()) * 2
        let height = Int((naturalSize.height * scale / 2).rounded()) * 2
        var bitrate = Double(width * height) * max(fps, 24) * bitsPerPixel
        if sourceBitrate > 0 { bitrate = min(bitrate, sourceBitrate * 0.6) }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = false

        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOut.alwaysCopiesSampleData = false
        reader.add(videoOut)

        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(bitrate),
                AVVideoExpectedSourceFrameRateKey: Int(max(fps, 1).rounded()),
                AVVideoMaxKeyFrameIntervalKey: Int(max(fps, 1).rounded()) * 2,
            ],
        ])
        videoIn.transform = transform
        videoIn.expectsMediaDataInRealTime = false
        writer.add(videoIn)

        var pairs: [(AVAssetReaderOutput, AVAssetWriterInput)] = [(videoOut, videoIn)]

        if let audioTrack {
            let formats = try await audioTrack.load(.formatDescriptions)
            let asbd = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
            let channels = min(Int(asbd?.mChannelsPerFrame ?? 2), 2)
            let sampleRate = min(asbd?.mSampleRate ?? 44_100, 48_000)

            let audioOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: sampleRate,
            ])
            reader.add(audioOut)
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: sampleRate,
                AVEncoderBitRateKey: channels == 1 ? 96_000 : 128_000,
            ])
            audioIn.expectsMediaDataInRealTime = false
            writer.add(audioIn)
            pairs.append((audioOut, audioIn))
        }

        guard reader.startReading() else { throw reader.error ?? ShiftDropError.unreadable(source) }
        guard writer.startWriting() else { throw writer.error ?? ShiftDropError.writeFailed(output) }
        writer.startSession(atSourceTime: .zero)

        await withTaskGroup(of: Void.self) { group in
            for (index, pair) in pairs.enumerated() {
                let boxed = UncheckedPair(output: pair.0, input: pair.1)
                group.addTask {
                    await pump(from: boxed.output, to: boxed.input, label: "shiftdrop.compress.\(index)")
                }
            }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? ShiftDropError.unreadable(source)
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? ShiftDropError.writeFailed(output)
        }
    }

    /// Feeds samples from the reader into the writer whenever the writer can take more.
    private static func pump(from output: AVAssetReaderOutput, to input: AVAssetWriterInput, label: String) async {
        let queue = DispatchQueue(label: label)
        // Reader output and writer input are only touched on `queue`, which AVFoundation serializes.
        let pair = UncheckedPair(output: output, input: input)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            pair.input.requestMediaDataWhenReady(on: queue) {
                let (output, input) = (pair.output, pair.input)
                while input.isReadyForMoreMediaData && !finished {
                    if let sample = output.copyNextSampleBuffer(), input.append(sample) {
                        continue
                    }
                    finished = true
                    input.markAsFinished()
                    continuation.resume()
                }
            }
        }
    }

    private struct UncheckedPair: @unchecked Sendable {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
    }
}

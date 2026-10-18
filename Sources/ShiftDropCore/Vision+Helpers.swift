import CoreGraphics
import CoreImage
import Foundation
import Vision

/// On-device text recognition and subject lifting, both via the Vision framework.
public enum VisionTasks {
    /// Reads all text in the image, top to bottom.
    public static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])

        let observations = (request.results ?? []).sorted { a, b in
            // Vision's origin is bottom-left. Treat boxes on nearly the same line as one row.
            let dy = a.boundingBox.midY - b.boundingBox.midY
            if abs(dy) > min(a.boundingBox.height, b.boundingBox.height) / 2 { return dy > 0 }
            return a.boundingBox.minX < b.boundingBox.minX
        }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Cuts the main subject(s) out of the image, leaving a transparent background.
    public static func removeBackground(from image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw ShiftDropError.nothingFound("No subject found in the image")
        }
        let buffer = try result.generateMaskedImage(
            ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false
        )
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            throw ShiftDropError.nothingFound("Couldn't build the cut-out image")
        }
        return output
    }
}

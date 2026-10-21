import CoreGraphics
import Foundation
import Vision

struct OCRLine: Identifiable, Equatable {
    let id: UUID
    let text: String
    let confidence: Float
    /// Vision-normalized rectangle (origin bottom-left).
    let boundingBox: CGRect

    init(
        id: UUID = UUID(),
        text: String,
        confidence: Float,
        boundingBox: CGRect = .zero
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

struct OCRResult: Equatable {
    let lines: [OCRLine]
    let imageSize: CGSize

    init(lines: [OCRLine], imageSize: CGSize = .zero) {
        self.lines = lines
        self.imageSize = imageSize
    }

    /// Top-to-bottom, left-to-right text suitable for the receipt parser.
    var text: String {
        lines.map(\.text).joined(separator: "\n")
    }

    var averageConfidence: Double {
        guard !lines.isEmpty else {
            return 0
        }
        let total = lines.reduce(0.0) { $0 + Double($1.confidence) }
        return total / Double(lines.count)
    }

    /// True when the screenshot was hard to read. The import draft turns this
    /// into `.lowOCRConfidence` and requires a review.
    var isLowConfidence: Bool {
        guard !lines.isEmpty else {
            return true
        }
        return averageConfidence < 0.55
            || lines.contains { $0.confidence < 0.35 }
    }
}

enum OCRError: LocalizedError, Equatable {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return "文字识别失败：\(message)"
        }
    }
}

/// Thin Vision wrapper. It intentionally returns plain values so the parser and
/// import service stay independent of Vision and easy to test.
///
/// `VNImageRequestHandler.perform` is synchronous. Call `recognize` from a
/// background task in the UI layer so a large screenshot does not block the
/// main actor.
final class VisionOCRService {

    private static let minimumConfidence: Float = 0.30
    private static let sameLineTolerance: CGFloat = 0.015

    func recognize(cgImage: CGImage) async throws -> OCRResult {
        let request = VNRecognizeTextRequest(completionHandler: nil)
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.requestFailed(error.localizedDescription)
        }

        let observations = (request.results ?? []) as? [VNRecognizedTextObservation] ?? []
        var lines: [OCRLine] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else {
                continue
            }
            guard candidate.confidence >= Self.minimumConfidence else {
                continue
            }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }
            lines.append(
                OCRLine(
                    text: text,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            )
        }

        lines.sort { lhs, rhs in
            let verticalDistance = abs(
                lhs.boundingBox.midY - rhs.boundingBox.midY
            )
            if verticalDistance > Self.sameLineTolerance {
                // Vision's y origin is bottom-left.
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        return OCRResult(
            lines: lines,
            imageSize: CGSize(
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            )
        )
    }
}

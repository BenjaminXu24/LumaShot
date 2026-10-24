import Combine
import CoreGraphics
import Vision

/// On-device text recognition. Images are passed to Vision as `CGImage` values and are never uploaded.
enum TextRecognition {
    static let preferredLanguageIdentifiers = ["zh-Hans", "en-US"]
    /// Lines whose vertical centers are closer than this (normalized Vision space) stay on one row.
    static let sameLineThreshold: CGFloat = 0.02

    struct Settings: Equatable {
        var languages: [String]
        var usesLanguageCorrection: Bool
        var automaticallyDetectsLanguage: Bool
    }

    struct Outcome: Equatable {
        var text: String
        var pixelWidth: Int
        var pixelHeight: Int
    }

    /// A recognized string plus its normalized bounding box. Vision's origin is the bottom-left.
    struct RecognizedLine: Equatable {
        var text: String
        var boundingBox: CGRect
    }

    static func settings(supportedLanguages: [String]) -> Settings {
        Settings(
            languages: preferredLanguages(supported: supportedLanguages),
            usesLanguageCorrection: true,
            automaticallyDetectsLanguage: false
        )
    }

    /// Keeps Simplified Chinese and English when the system offers them, in that preference order.
    static func preferredLanguages(supported: [String]) -> [String] {
        if supported.isEmpty { return preferredLanguageIdentifiers }
        var chosen: [String] = []
        for identifier in preferredLanguageIdentifiers {
            if let match = supported.first(where: { $0.caseInsensitiveCompare(identifier) == .orderedSame }) {
                chosen.append(match)
            }
        }
        if chosen.isEmpty, let english = supported.first(where: { $0.lowercased().hasPrefix("en") }) {
            chosen.append(english)
        }
        if chosen.isEmpty, let fallback = supported.first {
            chosen.append(fallback)
        }
        return chosen
    }

    static func transcript(_ lines: [RecognizedLine]) -> String {
        let sorted = lines.sorted { lhs, rhs in
            let deltaY = lhs.boundingBox.midY - rhs.boundingBox.midY
            if abs(deltaY) > sameLineThreshold { return lhs.boundingBox.midY > rhs.boundingBox.midY }
            if lhs.boundingBox.minX != rhs.boundingBox.minX { return lhs.boundingBox.minX < rhs.boundingBox.minX }
            return lhs.text < rhs.text
        }
        return sorted.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func transcript(observations: [VNRecognizedTextObservation]) -> String {
        let lines = observations.compactMap { observation -> RecognizedLine? in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return RecognizedLine(text: text, boundingBox: observation.boundingBox)
        }
        return transcript(lines)
    }

    static func scopeDescription(kind: String, image: CGImage, region: CGRect?) -> String {
        if let region {
            guard let area = ImageCrop.pixelRect(region, imageWidth: image.width, imageHeight: image.height) else {
                return kind
            }
            return "\(kind) · \(Int(area.width)) × \(Int(area.height))"
        }
        return "\(kind) · \(image.width) × \(image.height)"
    }

    static func recognize(image: CGImage, region: CGRect?, recognizer: TextRecognizing) async throws -> Outcome {
        let target = try imageForRecognition(image, region: region)
        let text = try await recognizer.recognize(target)
        return Outcome(text: text, pixelWidth: target.width, pixelHeight: target.height)
    }

    static func perform(image: CGImage, region: CGRect?, kind: String, recognizer: TextRecognizing) async -> OCRPhase {
        let scope = scopeDescription(kind: kind, image: image, region: region)
        do {
            let outcome = try await recognize(image: image, region: region, recognizer: recognizer)
            return .result(text: outcome.text, scope: "\(kind) · \(outcome.pixelWidth) × \(outcome.pixelHeight)")
        } catch TextRecognitionError.regionTooSmall {
            return .failed(message: "选区太小或超出图片范围，请重新框选。", scope: scope)
        } catch {
            return .failed(message: "识别失败，请重试。", scope: scope)
        }
    }

    private static func imageForRecognition(_ image: CGImage, region: CGRect?) throws -> CGImage {
        guard image.width > 0, image.height > 0 else { throw TextRecognitionError.regionTooSmall }
        guard let region else { return image }
        guard let cropped = ImageCrop.cgImage(image, topLeftRect: region) else {
            throw TextRecognitionError.regionTooSmall
        }
        return cropped
    }
}

enum TextRecognitionError: Error, Equatable {
    case regionTooSmall
}

protocol TextRecognizing {
    func recognize(_ image: CGImage) async throws -> String
}

/// Crops in the same top-left pixel space as editor annotations.
/// `CGImage` row 0 is the first row of pixel data, which is the top of the bitmap.
enum ImageCrop {
    static func cgImage(_ image: CGImage, topLeftRect rect: CGRect) -> CGImage? {
        guard let area = pixelRect(rect, imageWidth: image.width, imageHeight: image.height) else { return nil }
        return image.cropping(to: area)
    }

    static func pixelRect(_ rect: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        let area = rect.standardized.integral.intersection(bounds)
        guard area.width >= 1, area.height >= 1 else { return nil }
        return area
    }
}

/// Local Vision request. `recognitionLanguages` prefers Simplified Chinese, then English.
/// `automaticallyDetectsLanguage` stays off so the request does not substitute another language.
struct VisionTextRecognizer: TextRecognizing {
    func recognize(_ image: CGImage) async throws -> String {
        let supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate,
            revision: VNRecognizeTextRequest.currentRevision
        )) ?? []
        let settings = TextRecognition.settings(supportedLanguages: supported)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.revision = VNRecognizeTextRequest.currentRevision
                request.usesLanguageCorrection = settings.usesLanguageCorrection
                request.automaticallyDetectsLanguage = settings.automaticallyDetectsLanguage
                request.recognitionLanguages = settings.languages
                let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                    let observations: [VNRecognizedTextObservation] = request.results ?? []
                    continuation.resume(returning: TextRecognition.transcript(observations: observations))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum OCRPhase: Equatable {
    case idle
    case recognizing(scope: String)
    case result(text: String, scope: String)
    case failed(message: String, scope: String)

    var scope: String? {
        switch self {
        case .idle: return nil
        case .recognizing(let scope), .result(_, let scope), .failed(_, let scope):
            return scope
        }
    }

    var canCopy: Bool {
        guard case .result(let text, _) = self else { return false }
        return text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil
    }
}

/// Presents one local recognition at a time. Closing the sheet drops a late result.
final class OCRSession: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var phase: OCRPhase = .idle
    var recognizer: TextRecognizing
    private(set) var task: Task<Void, Never>?
    private var generation = 0

    init(recognizer: TextRecognizing = VisionTextRecognizer()) {
        self.recognizer = recognizer
    }

    @MainActor
    func recognize(image: CGImage, region: CGRect?, kind: String) {
        generation += 1
        let token = generation
        let engine = recognizer
        isPresented = true
        phase = .recognizing(scope: TextRecognition.scopeDescription(kind: kind, image: image, region: region))
        task = Task { @MainActor [weak self] in
            let next = await TextRecognition.perform(image: image, region: region, kind: kind, recognizer: engine)
            guard let self, token == self.generation else { return }
            self.phase = next
        }
    }

    @MainActor
    func copyToPasteboard() -> Bool {
        guard case .result(let text, _) = phase else { return false }
        return ExportService.copyText(text)
    }

    @MainActor
    func dismiss() {
        generation += 1
        task?.cancel()
        task = nil
        if isPresented { isPresented = false }
    }
}

import AppKit
import CoreText
import XCTest
@testable import LumaShot

@MainActor
final class TextRecognitionTests: XCTestCase {
    func testPreferredLanguagesKeepSimplifiedChineseThenEnglish() {
        XCTAssertEqual(
            TextRecognition.preferredLanguages(supported: ["en-US", "fr-FR", "zh-Hant", "zh-Hans"]),
            ["zh-Hans", "en-US"]
        )
        XCTAssertEqual(
            TextRecognition.preferredLanguages(supported: ["EN-US", "ZH-HANS"]),
            ["ZH-HANS", "EN-US"]
        )
        XCTAssertEqual(TextRecognition.preferredLanguages(supported: ["fr-FR", "en-GB"]), ["en-GB"])
        XCTAssertEqual(TextRecognition.preferredLanguages(supported: ["ja-JP"]), ["ja-JP"])
        XCTAssertEqual(TextRecognition.preferredLanguages(supported: []), TextRecognition.preferredLanguageIdentifiers)
    }

    func testSettingsStayOnDeviceAndDoNotAutoDetectLanguage() {
        let settings = TextRecognition.settings(supportedLanguages: ["zh-Hans", "en-US", "fr-FR"])
        XCTAssertEqual(settings.languages, ["zh-Hans", "en-US"])
        XCTAssertTrue(settings.usesLanguageCorrection)
        XCTAssertFalse(settings.automaticallyDetectsLanguage)
    }

    func testTranscriptReadsTopToBottomThenLeftToRight() {
        let topRight = TextRecognition.RecognizedLine(text: "right", boundingBox: CGRect(x: 0.55, y: 0.70, width: 0.2, height: 0.08))
        let topLeft = TextRecognition.RecognizedLine(text: "left", boundingBox: CGRect(x: 0.05, y: 0.71, width: 0.2, height: 0.08))
        let bottom = TextRecognition.RecognizedLine(text: "bottom", boundingBox: CGRect(x: 0.10, y: 0.10, width: 0.3, height: 0.08))
        let blank = TextRecognition.RecognizedLine(text: "", boundingBox: CGRect(x: 0, y: 0.9, width: 0.2, height: 0.05))
        XCTAssertEqual(TextRecognition.transcript([topRight, bottom, blank, topLeft]), "left\nright\nbottom")
    }

    func testCropUsesTopLeftPixelsRatherThanPointSize() throws {
        let source = try raster(width: 40, height: 30) { _, y in
            y < 8 ? (0, 255, 0, 255) : (0, 0, 255, 255)
        }
        let top = try XCTUnwrap(ImageCrop.cgImage(source, topLeftRect: CGRect(x: 1.2, y: 0.4, width: 10.2, height: 7.2)))
        XCTAssertEqual(top.width, 11)
        XCTAssertEqual(top.height, 8)
        try assertDominant(top, channel: .green)

        let bottom = try XCTUnwrap(ImageCrop.cgImage(source, topLeftRect: CGRect(x: 4, y: 18, width: 6, height: 5)))
        XCTAssertEqual(bottom.width, 6)
        XCTAssertEqual(bottom.height, 5)
        try assertDominant(bottom, channel: .blue)

        XCTAssertNil(ImageCrop.pixelRect(CGRect(x: 80, y: 0, width: 4, height: 4), imageWidth: 40, imageHeight: 30))
        XCTAssertEqual(
            ImageCrop.pixelRect(CGRect(x: -4, y: -2, width: 10, height: 8), imageWidth: 40, imageHeight: 30),
            CGRect(x: 0, y: 0, width: 6, height: 6)
        )

        let retina = NSImage(cgImage: source, size: NSSize(width: 20, height: 15))
        let encoded = try XCTUnwrap(ImageEncoding.cgImage(from: retina))
        XCTAssertEqual(encoded.width, 40)
        XCTAssertEqual(encoded.height, 30)
    }

    func testPipelineSendsOnlyTheSelectedPixels() async throws {
        let source = try raster(width: 40, height: 30) { _, y in
            y < 8 ? (0, 255, 0, 255) : (0, 0, 255, 255)
        }
        let recognizer = RecordingRecognizer("选区文字")
        let selected = await TextRecognition.perform(
            image: source,
            region: CGRect(x: 0, y: 0, width: 12, height: 8),
            kind: "选区",
            recognizer: recognizer
        )
        guard case .result(let text, let scope) = selected else {
            return XCTFail("expected a result, got \(selected)")
        }
        XCTAssertEqual(text, "选区文字")
        XCTAssertEqual(scope, "选区 · 12 × 8")
        let crop = try XCTUnwrap(recognizer.images.first)
        XCTAssertEqual(crop.width, 12)
        XCTAssertEqual(crop.height, 8)
        try assertDominant(crop, channel: .green)

        let full = RecordingRecognizer("整图")
        let entire = await TextRecognition.perform(image: source, region: nil, kind: "整张图片", recognizer: full)
        guard case .result(_, let fullScope) = entire else { return XCTFail("expected a full-image result") }
        XCTAssertEqual(full.images.first?.width, 40)
        XCTAssertEqual(full.images.first?.height, 30)
        XCTAssertEqual(fullScope, "整张图片 · 40 × 30")

        let missed = RecordingRecognizer("不应调用")
        let outside = await TextRecognition.perform(
            image: source,
            region: CGRect(x: 100, y: 0, width: 5, height: 5),
            kind: "选区",
            recognizer: missed
        )
        guard case .failed(let message, _) = outside else { return XCTFail("expected a failed selection") }
        XCTAssertEqual(message, "选区太小或超出图片范围，请重新框选。")
        XCTAssertTrue(missed.images.isEmpty)

        let blank = await TextRecognition.perform(image: source, region: nil, kind: "整张图片", recognizer: RecordingRecognizer("  \n"))
        XCTAssertFalse(blank.canCopy)
    }

    func testCopyTextWritesTheStringAndLeavesWhitespaceUntouched() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LumaShotTests.OCR.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        XCTAssertTrue(ExportService.copyText("拾光\nHello", pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "拾光\nHello")
        XCTAssertFalse(ExportService.copyText(" \n\t", pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "拾光\nHello")
    }

    func testEditorRecognitionUsesRetinaPixelsAndDoesNotInsertAnnotations() async throws {
        let source = try raster(width: 40, height: 30) { _, y in
            y < 8 ? (0, 255, 0, 255) : (0, 0, 255, 255)
        }
        let image = NSImage(cgImage: source, size: NSSize(width: 20, height: 15))
        let recognizer = RecordingRecognizer("只显示文字")
        let model = AnnotationEditorModel(image: image, onCopy: { _ in }, onSave: { _ in })
        model.ocrSession.recognizer = recognizer
        XCTAssertEqual(model.pixelSize, CGSize(width: 40, height: 30))

        model.ocrSelection = CGRect(x: 0, y: 0, width: 10, height: 10)
        model.recognizeCurrentImage()
        XCTAssertNil(model.ocrSelection)
        await model.ocrSession.task?.value
        XCTAssertEqual(recognizer.images.first?.width, 40)
        XCTAssertEqual(recognizer.images.first?.height, 30)
        XCTAssertTrue(model.annotations.isEmpty)

        model.commit(EditorAnnotation(tool: .rectangle, points: [.zero, CGPoint(x: 12, y: 8)], color: .red, lineWidth: 2))
        model.recognizeCurrentImage()
        await model.ocrSession.task?.value
        XCTAssertEqual(recognizer.images.last?.width, 40, "Annotated recognition stays at the source pixel size")
        XCTAssertEqual(model.annotations.count, 1)

        model.recognizeSelection(CGRect(x: 0, y: 0, width: 12, height: 8))
        await model.ocrSession.task?.value
        XCTAssertEqual(model.annotations.count, 1)
        XCTAssertEqual(model.annotations.first?.tool, .rectangle)
        XCTAssertNil(model.draft)
        let crop = try XCTUnwrap(recognizer.images.last)
        XCTAssertEqual(crop.width, 12)
        XCTAssertEqual(crop.height, 8)
        guard case .result(let text, let scope) = model.ocrSession.phase else {
            return XCTFail("expected recognized text, got \(model.ocrSession.phase)")
        }
        XCTAssertEqual(text, "只显示文字")
        XCTAssertEqual(scope, "选区 · 12 × 8")
        XCTAssertTrue(model.ocrSession.isPresented)
    }

    func testVisionRecognizesRenderedEnglishLocally() async throws {
        let image = try helloImage()
        let recognized = try await VisionTextRecognizer().recognize(image)
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(trimmed.isEmpty)
        XCTAssertTrue(
            recognized.localizedCaseInsensitiveContains("hello"),
            "On-device Vision should read the fixture. Recognized: \(recognized)"
        )
    }

    /// Same top-left text path as `AnnotationRenderer`, which the annotation tests already
    /// check lands upright. Vision then reads that bitmap on device.
    private func helloImage() throws -> CGImage {
        let width = 960
        let height = 280
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let font = NSFont.systemFont(ofSize: 96, weight: .bold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hello", attributes: [
            .font: font,
            .foregroundColor: NSColor.black
        ]))
        context.saveGState()
        context.translateBy(x: 48, y: 80 + font.ascender)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
        return try XCTUnwrap(context.makeImage())
    }

    private func raster(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) throws -> CGImage {
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let sample = pixel(x, y)
                let index = y * bytesPerRow + x * 4
                bytes[index] = sample.0
                bytes[index + 1] = sample.1
                bytes[index + 2] = sample.2
                bytes[index + 3] = sample.3
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private enum Channel { case green, blue }

    private func assertDominant(_ image: CGImage, channel: Channel, file: StaticString = #filePath, line: UInt = #line) throws {
        let color = try XCTUnwrap(sample(image, x: min(1, image.width - 1), y: min(1, image.height - 1)))
        let red = color.redComponent
        let green = color.greenComponent
        let blue = color.blueComponent
        switch channel {
        case .green:
            XCTAssertGreaterThan(green, red, file: file, line: line)
            XCTAssertGreaterThan(green, blue, file: file, line: line)
        case .blue:
            XCTAssertGreaterThan(blue, red, file: file, line: line)
            XCTAssertGreaterThan(blue, green, file: file, line: line)
        }
    }

    private func sample(_ image: CGImage, x: Int, y: Int) -> NSColor? {
        NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    }
}

private final class RecordingRecognizer: TextRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [CGImage] = []
    let result: String

    init(_ result: String) { self.result = result }

    var images: [CGImage] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func recognize(_ image: CGImage) async throws -> String {
        lock.lock()
        stored.append(image)
        lock.unlock()
        return result
    }
}

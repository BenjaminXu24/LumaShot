import XCTest
import AppKit
@testable import LumaShot

final class StitcherTests: XCTestCase {
    func testOverlappingFramesKeepExactPixelOrder() throws {
        let source = makePattern(width: 160, height: 1_200)
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 320)))
        let stitcher = try XCTUnwrap(ImageStitcher(firstImage: first))
        for offset in [170, 340] {
            let frame = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: offset, width: 160, height: 320)))
            XCTAssertEqual(stitcher.append(frame), .appended(addedPixels: 170, totalHeight: 320 + offset))
        }
        let output = try XCTUnwrap(stitcher.makeImage())
        let expected = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 660)))
        XCTAssertEqual(output.width, 160)
        XCTAssertEqual(output.height, 660)
        assertPixelsEqual(output, expected)
    }

    func testStickyHeaderAndFooterAppearOnlyOnce() throws {
        let source = makePattern(width: 160, height: 1_400)
        let header = 32
        let footer = 28
        let viewport = 360
        let first = try viewportImage(source: source, offset: 0, height: viewport, header: header, footer: footer)
        let stitcher = try XCTUnwrap(ImageStitcher(firstImage: first))
        for offset in [170, 340] {
            let frame = try viewportImage(source: source, offset: offset, height: viewport, header: header, footer: footer)
            XCTAssertEqual(stitcher.append(frame), .appended(addedPixels: 170, totalHeight: viewport + offset))
        }
        let output = try XCTUnwrap(stitcher.makeImage())
        let expected = try viewportImage(source: source, offset: 0, height: 700, header: header, footer: footer)
        assertPixelsEqual(output, expected)
    }

    func testRepeatedFrameDoesNotExtendScreenshot() throws {
        let first = makePattern(width: 160, height: 320)
        let stitcher = try XCTUnwrap(ImageStitcher(firstImage: first))
        XCTAssertEqual(stitcher.append(first), .unchanged)
        XCTAssertEqual(stitcher.totalHeight, 320)
        XCTAssertEqual(stitcher.frameCount, 1)
        assertPixelsEqual(try XCTUnwrap(stitcher.makeImage()), first)
    }

    func testUnrelatedFrameDoesNotCorruptExistingCapture() throws {
        let first = makePattern(width: 160, height: 320, seed: 1)
        let stitcher = try XCTUnwrap(ImageStitcher(firstImage: first))
        XCTAssertEqual(stitcher.append(makePattern(width: 160, height: 320, seed: 9_181)), .noOverlap)
        XCTAssertEqual(stitcher.totalHeight, 320)
        assertPixelsEqual(try XCTUnwrap(stitcher.makeImage()), first)
    }

    func testHeightLimitPreservesValidImage() throws {
        let source = makePattern(width: 160, height: 800)
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 320)))
        let stitcher = try XCTUnwrap(ImageStitcher(firstImage: first, maximumHeight: 400))
        let next = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 160, width: 160, height: 320)))
        XCTAssertEqual(stitcher.append(next), .heightLimit)
        XCTAssertEqual(stitcher.totalHeight, 320)
    }

    func testFindsSmallScrollWithoutRoundingSeam() throws {
        let source = makePattern(width: 160, height: 800)
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 320)))
        let stitcher = try XCTUnwrap(ImageStitcher(firstImage: first))
        let next = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 7, width: 160, height: 320)))
        XCTAssertEqual(stitcher.append(next), .appended(addedPixels: 7, totalHeight: 327))
        let expected = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 327)))
        assertPixelsEqual(try XCTUnwrap(stitcher.makeImage()), expected)
    }

    func testMismatchedDimensionsAreRejected() throws {
        let stitcher = try XCTUnwrap(ImageStitcher(firstImage: makePattern(width: 160, height: 320)))
        XCTAssertEqual(stitcher.append(makePattern(width: 161, height: 320)), .noOverlap)
        XCTAssertEqual(stitcher.append(makePattern(width: 160, height: 321)), .noOverlap)
    }

    func testSparseHorizontalLineIsNotMistakenForUnchangedPage() throws {
        let width = 160
        var pixels = [UInt8](repeating: 255, count: width * 800 * 4)
        for x in 0..<width {
            let p = (200 * width + x) * 4
            pixels[p] = 0
            pixels[p + 1] = 0
            pixels[p + 2] = 0
        }
        let source = makeImage(pixels: pixels, width: width, height: 800)
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: width, height: 320)))
        let next = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 72, width: width, height: 320)))
        let stitcher = try XCTUnwrap(ImageStitcher(firstImage: first))
        XCTAssertEqual(stitcher.append(next), .appended(addedPixels: 72, totalHeight: 392))
        let expected = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: width, height: 392)))
        assertPixelsEqual(try XCTUnwrap(stitcher.makeImage()), expected)
    }

    @MainActor func testThreeTextScreensReachEditorAndExportAtFullHeight() throws {
        let source = makeTextPage(width: 664, height: 2_400)
        let viewport = 630
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: source.width, height: viewport)))
        let stitcher = try XCTUnwrap(ImageStitcher(firstImage: first))
        for offset in [280, 560] {
            let next = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: offset, width: source.width, height: viewport)))
            XCTAssertEqual(stitcher.append(next), .appended(addedPixels: 280, totalHeight: viewport + offset))
        }
        XCTAssertEqual(stitcher.frameCount, 3)
        let output = try XCTUnwrap(stitcher.makeImage())
        let expected = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: source.width, height: 1_190)))
        assertPixelsEqual(output, expected)
        let editor = AnnotationEditorModel(image: NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height)),
                                           onCopy: { _ in }, onSave: { _ in })
        XCTAssertEqual(editor.pixelSize, CGSize(width: 664, height: 1_190))
        let rendered = try XCTUnwrap(editor.renderedImage())
        assertPixelsEqual(try XCTUnwrap(ImageEncoding.bitmap(from: rendered)?.cgImage), expected)
    }

    private func makeTextPage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for row in 0..<70 {
            let text = "\(row + 1). 这是一段用于分享的回答。Capture paragraph \(row * 17): \(row * row)."
            (text as NSString).draw(at: CGPoint(x: 24, y: height - 40 - row * 32), withAttributes: [
                .font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.black
            ])
        }
        return context.makeImage()!
    }

    private func makePattern(width: Int, height: Int, seed: UInt32 = 1) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                // Deterministic rich detail, with rows that cannot accidentally
                // align at an incorrect periodic offset.
                var value = UInt32(x) &* 747_796_405 &+ UInt32(y) &* 2_891_336_453 &+ seed
                value = ((value >> ((value >> 28) + 4)) ^ value) &* 277_803_737
                value = (value >> 22) ^ value
                let p = (y * width + x) * 4
                pixels[p] = UInt8(truncatingIfNeeded: value)
                pixels[p + 1] = UInt8(truncatingIfNeeded: value >> 8)
                pixels[p + 2] = UInt8(truncatingIfNeeded: value >> 16)
            }
        }
        return makeImage(pixels: pixels, width: width, height: height)
    }

    private func viewportImage(source: CGImage, offset: Int, height: Int, header: Int, footer: Int) throws -> CGImage {
        let sourcePixels = pixelBytes(source)
        let rowSize = source.width * 4
        var pixels = [UInt8](repeating: 255, count: rowSize * height)
        for y in 0..<height {
            for x in 0..<source.width {
                let p = y * rowSize + x * 4
                if y < header {
                    pixels[p] = 40
                    pixels[p + 1] = UInt8(60 + x % 70)
                    pixels[p + 2] = 150
                } else if y >= height - footer {
                    pixels[p] = 160
                    pixels[p + 1] = 40
                    pixels[p + 2] = UInt8(50 + x % 90)
                } else {
                    let s = (offset + y - header) * rowSize + x * 4
                    pixels[p..<(p + 4)] = sourcePixels[s..<(s + 4)]
                }
            }
        }
        return makeImage(pixels: pixels, width: source.width, height: height)
    }

    private func makeImage(pixels: [UInt8], width: Int, height: Int) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func pixelBytes(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    private func assertPixelsEqual(_ actual: CGImage, _ expected: CGImage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        let a = pixelBytes(actual)
        let b = pixelBytes(expected)
        guard a.count == b.count else { return }
        let firstDifference = a.indices.first(where: { a[$0] != b[$0] })
        XCTAssertNil(firstDifference, "Pixels differ at byte \(firstDifference.map(String.init) ?? "none")", file: file, line: line)
    }
}

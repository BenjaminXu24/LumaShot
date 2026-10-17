import AppKit
import XCTest
@testable import LumaShot

final class AnnotationTests: XCTestCase {
    private let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    private func sourceImage(width: Int = 120, height: Int = 80, retina: Bool = true,
                             drawing: (CGContext) -> Void) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawing(context)
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: retina ? width / 2 : width,
                                                                 height: retina ? height / 2 : height))
    }
    private struct Pixel {
        let redComponent: CGFloat
        let greenComponent: CGFloat
        let blueComponent: CGFloat
        let alphaComponent: CGFloat
    }
    private struct SRGBPixels {
        let bytes: [UInt8]
        let bytesPerRow: Int
        init(_ image: NSImage) {
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            bytesPerRow = context.bytesPerRow
            bytes = Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                              count: context.bytesPerRow * cg.height))
        }
    }
    // NSBitmapImageRep.colorAt reports calibrated RGB for these sRGB bitmaps.
    // Converting that NSColor again changes its components. Read known RGBA sRGB
    // bytes instead, so the test measures exported pixels without a second transform.
    private func pixel(_ image: SRGBPixels, x: Int, y: Int) -> Pixel {
        let index = y * image.bytesPerRow + x * 4
        return Pixel(redComponent: CGFloat(image.bytes[index]) / 255,
                     greenComponent: CGFloat(image.bytes[index + 1]) / 255,
                     blueComponent: CGFloat(image.bytes[index + 2]) / 255,
                     alphaComponent: CGFloat(image.bytes[index + 3]) / 255)
    }
    func testExportPreservesRetinaPixelsAndTopLeftAnnotationCoordinates() throws {
        let image = sourceImage { context in
            context.setFillColor(red.cgColor)
            context.fill(CGRect(x: 0, y: 40, width: 120, height: 40))
        }
        let rectangle = EditorAnnotation(tool: .rectangle,
                                         points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30)],
                                         color: blue, lineWidth: 4)
        let rendered = try XCTUnwrap(AnnotationRenderer.render(image: image, annotations: [rectangle]))
        let renderedPixels = SRGBPixels(rendered)
        let cg = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cg.width, 120)
        XCTAssertEqual(cg.height, 80)
        XCTAssertEqual(rendered.size, CGSize(width: 60, height: 40))
        XCTAssertGreaterThan(pixel(renderedPixels, x: 5, y: 5).redComponent, 0.98)
        XCTAssertLessThan(pixel(renderedPixels, x: 5, y: 5).greenComponent, 0.02)
        XCTAssertGreaterThan(pixel(renderedPixels, x: 10, y: 15).blueComponent, 0.98)
        XCTAssertLessThan(pixel(renderedPixels, x: 10, y: 15).redComponent, 0.02)
        XCTAssertGreaterThan(pixel(renderedPixels, x: 10, y: 65).redComponent, 0.98)
        XCTAssertGreaterThan(pixel(renderedPixels, x: 10, y: 65).greenComponent, 0.98)
    }
    func testMosaicChangesActualPixelsWithoutFlippingCrop() throws {
        let image = sourceImage { context in
            context.setFillColor(blue.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 40))
            for x in 0..<120 {
                context.setFillColor((x.isMultiple(of: 2) ? red : NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)).cgColor)
                context.fill(CGRect(x: x, y: 40, width: 1, height: 40))
            }
        }
        let mosaic = EditorAnnotation(tool: .mosaic,
                                      points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30)],
                                      color: .black, lineWidth: 4)
        let rendered = try XCTUnwrap(AnnotationRenderer.render(image: image, annotations: [mosaic]))
        let sourcePixels = SRGBPixels(image)
        let renderedPixels = SRGBPixels(rendered)
        let beforeA = pixel(sourcePixels, x: 12, y: 15), beforeB = pixel(sourcePixels, x: 13, y: 15)
        let afterA = pixel(renderedPixels, x: 12, y: 15), afterB = pixel(renderedPixels, x: 13, y: 15)
        XCTAssertGreaterThan(abs(beforeA.greenComponent - beforeB.greenComponent), 0.9)
        XCTAssertEqual(afterA.greenComponent, afterB.greenComponent, accuracy: 0.01,
                       "Mosaic must replace fine details with actual large pixel blocks")
        XCTAssertGreaterThan(afterA.redComponent, 0.98)
        XCTAssertLessThan(afterA.blueComponent, 0.02, "A top crop must not sample the blue bottom half")
        XCTAssertGreaterThan(pixel(renderedPixels, x: 12, y: 65).blueComponent, 0.98)
        XCTAssertEqual(pixel(renderedPixels, x: 8, y: 15).greenComponent,
                       pixel(sourcePixels, x: 8, y: 15).greenComponent, accuracy: 0.01,
                       "Pixels outside the selected mosaic rectangle must stay unchanged")
    }
    func testTextRendersInTopLeftImageSpace() throws {
        let image = sourceImage(retina: false) { _ in }
        let text = EditorAnnotation(tool: .text, points: [CGPoint(x: 8, y: 5)], color: .black,
                                    lineWidth: 3, text: "TOP", fontSize: 20)
        let rendered = try XCTUnwrap(AnnotationRenderer.render(image: image, annotations: [text]))
        let renderedPixels = SRGBPixels(rendered)
        var topInk = 0, bottomInk = 0
        for y in 0..<80 {
            for x in 0..<70 where pixel(renderedPixels, x: x, y: y).redComponent < 0.5 {
                if y < 35 { topInk += 1 } else { bottomInk += 1 }
            }
        }
        XCTAssertGreaterThan(topInk, 30)
        XCTAssertEqual(bottomInk, 0)
    }
    @MainActor func testAnnotationHistoryPreservesUndoRedoAndInvalidatesRedoAfterNewEdit() async {
        let image = sourceImage { _ in }
        let model = AnnotationEditorModel(image: image, onCopy: { _ in }, onSave: { _ in })
        let rectangle = EditorAnnotation(tool: .rectangle, points: [.zero, CGPoint(x: 20, y: 20)], color: blue, lineWidth: 4)
        model.commit(rectangle)
        XCTAssertEqual(model.annotations.count, 1)
        model.undo()
        XCTAssertTrue(model.annotations.isEmpty)
        XCTAssertTrue(model.canRedo)
        model.redo()
        XCTAssertEqual(model.annotations.first?.id, rectangle.id)
        model.undo()
        model.commit(EditorAnnotation(tool: .number, points: [CGPoint(x: 30, y: 30)], color: red, lineWidth: 4))
        XCTAssertFalse(model.canRedo)
        model.clear()
        XCTAssertTrue(model.annotations.isEmpty)
        model.undo()
        XCTAssertEqual(model.annotations.count, 1)
    }
}

import AppKit
import XCTest
@testable import LumaShot

final class ServicesTests: XCTestCase {
    func testCapturePersistenceKeepsNativePixelDimensions() async throws {
        try await MainActor.run {
            let directory = makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CaptureStore(directory: directory)
            let image = try makeImage(width: 320, height: 160, pointScale: 2)
            let item = try XCTUnwrap(store.add(image: image, mode: .region))

            XCTAssertEqual(item.pixelWidth, 320)
            XCTAssertEqual(item.pixelHeight, 160)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.filename).path))

            let restored = CaptureStore(directory: directory)
            XCTAssertEqual(restored.items, [item])
            let reloaded = try XCTUnwrap(restored.image(for: item))
            let bitmap = try XCTUnwrap(ImageEncoding.bitmap(from: reloaded))
            XCTAssertEqual(bitmap.pixelsWide, 320)
            XCTAssertEqual(bitmap.pixelsHigh, 160)
        }
    }

    func testRetentionDeletesOldImagesAndKeepsLatestFirst() async throws {
        try await MainActor.run {
            let directory = makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CaptureStore(directory: directory, retentionLimit: 2)
            let image = try makeImage(width: 24, height: 12)
            let oldest = try XCTUnwrap(store.add(image: image, mode: .region))
            let second = try XCTUnwrap(store.add(image: image, mode: .window))
            let newest = try XCTUnwrap(store.add(image: image, mode: .scroll))

            XCTAssertEqual(store.items, [newest, second])
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(oldest.filename).path))
            XCTAssertEqual(CaptureStore(directory: directory).items, [newest, second])
        }
    }

    func testDeleteAndClearPersistAndRemoveImageFiles() async throws {
        try await MainActor.run {
            let directory = makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CaptureStore(directory: directory)
            let image = try makeImage(width: 20, height: 10)
            let first = try XCTUnwrap(store.add(image: image, mode: .fullscreen))
            let second = try XCTUnwrap(store.add(image: image, mode: .window))

            store.delete(first)
            XCTAssertEqual(store.items, [second])
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(first.filename).path))
            XCTAssertEqual(CaptureStore(directory: directory).items, [second])

            store.clear()
            XCTAssertTrue(store.items.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(second.filename).path))
            XCTAssertTrue(CaptureStore(directory: directory).items.isEmpty)
        }
    }

    func testRestoringSkipsMissingFilesAndUnsafeFilenames() async throws {
        try await MainActor.run {
            let directory = makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let invalidItems = [
                CaptureItem(id: UUID(), filename: "missing.png", mode: .region, createdAt: Date(), pixelWidth: 8, pixelHeight: 8),
                CaptureItem(id: UUID(), filename: "../outside.png", mode: .region, createdAt: Date(), pixelWidth: 8, pixelHeight: 8)
            ]
            try JSONEncoder().encode(invalidItems).write(to: directory.appendingPathComponent("index.json"))
            let store = CaptureStore(directory: directory)

            XCTAssertTrue(store.items.isEmpty)
            XCTAssertNil(store.image(for: invalidItems[1]))
            let rewritten = try JSONDecoder().decode([CaptureItem].self, from: Data(contentsOf: directory.appendingPathComponent("index.json")))
            XCTAssertTrue(rewritten.isEmpty)
        }
    }

    func testFailedSaveDoesNotAddPhantomCapture() async throws {
        try await MainActor.run {
            let directory = makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            try Data("a file cannot be a capture directory".utf8).write(to: directory)
            let store = CaptureStore(directory: directory)

            XCTAssertNil(store.add(image: try makeImage(width: 8, height: 8), mode: .region))
            XCTAssertTrue(store.items.isEmpty)
        }
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LumaShotTests-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    private func makeImage(width: Int, height: Int, pointScale: CGFloat = 1) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ))
        if let bytes = bitmap.bitmapData {
            bytes.initialize(repeating: 180, count: bitmap.bytesPerRow * height)
        }
        bitmap.size = NSSize(width: CGFloat(width) / pointScale, height: CGFloat(height) / pointScale)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }
}

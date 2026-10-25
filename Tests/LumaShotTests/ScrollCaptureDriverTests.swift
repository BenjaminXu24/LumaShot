import AppKit
import XCTest
@testable import LumaShot

final class ScrollCaptureDriverTests: XCTestCase {
    @MainActor func testPauseWhileSettlingStillCollectsTheScrolledFrame() async throws {
        let fixture = Fixture(holding: .settling)
        defer { fixture.close() }
        fixture.driver.resume()
        await fulfillment(of: [fixture.checkpoint.entered], timeout: 5)
        fixture.driver.pause()
        XCTAssertTrue(fixture.driver.isCollectingFrame)
        fixture.checkpoint.release()
        await fulfillment(of: [fixture.captured], timeout: 5)
        XCTAssertFalse(fixture.driver.isAutomatic)
        XCTAssertEqual(fixture.scrollCount, 1)
        XCTAssertEqual(fixture.snapshots, [302])
        fixture.driver.finish()
        await fulfillment(of: [fixture.finished], timeout: 5)
        try fixture.assertExport(height: 932, frames: 2)
    }

    @MainActor func testPauseAndResumeWhileSettlingKeepsBothOverlappingFrames() async throws {
        let fixture = Fixture(holding: .settling, expectedCaptures: 2)
        defer { fixture.close() }
        fixture.finishAfterCaptures = 2
        fixture.driver.resume()
        await fulfillment(of: [fixture.checkpoint.entered], timeout: 5)
        fixture.driver.pause()
        fixture.driver.resume()
        fixture.checkpoint.release()
        await fulfillment(of: [fixture.finished], timeout: 5)
        XCTAssertEqual(fixture.snapshots, [302, 604])
        XCTAssertEqual(fixture.scrollCount, 2)
        try fixture.assertExport(height: 1_234, frames: 3)
    }

    @MainActor func testResumeDuringStitchingWaitsForTheFrameAndContinues() async throws {
        let fixture = Fixture(holding: .stitching, expectedCaptures: 2)
        defer { fixture.close() }
        fixture.finishAfterCaptures = 2
        fixture.driver.resume()
        await fulfillment(of: [fixture.checkpoint.entered], timeout: 5)
        fixture.driver.pause()
        fixture.driver.resume()
        XCTAssertTrue(fixture.driver.isAutomatic)
        XCTAssertEqual(fixture.scrollCount, 1)
        XCTAssertEqual(fixture.preparedAfterFrames, [1])
        fixture.checkpoint.release()
        await fulfillment(of: [fixture.finished], timeout: 5)
        // Activation/cursor preparation for Resume must follow the pending append.
        XCTAssertEqual(fixture.preparedAfterFrames, [1, 2])
        XCTAssertEqual(fixture.snapshots, [302, 604])
        try fixture.assertExport(height: 1_234, frames: 3)
    }

    @MainActor func testResumeDuringManualAppendPreservesTheManualFrame() async throws {
        let fixture = Fixture(holding: .stitching, expectedCaptures: 2)
        defer { fixture.close() }
        fixture.finishAfterCaptures = 2
        fixture.offset = 302
        fixture.driver.addCurrentFrame()
        await fulfillment(of: [fixture.checkpoint.entered], timeout: 5)
        fixture.driver.resume()
        XCTAssertEqual(fixture.scrollCount, 0)
        fixture.checkpoint.release()
        await fulfillment(of: [fixture.finished], timeout: 5)
        XCTAssertEqual(fixture.snapshots, [302, 604])
        XCTAssertEqual(fixture.scrollCount, 1)
        try fixture.assertExport(height: 1_234, frames: 3)
    }

    @MainActor func testFinishDuringGestureIncludesTheScrolledFrame() async throws {
        try await assertFinishCollectsLastFrame(holding: .gesture)
    }

    @MainActor func testFinishWhileSettlingIncludesTheScrolledFrame() async throws {
        try await assertFinishCollectsLastFrame(holding: .settling)
    }

    @MainActor func testFinishBeforeSnapshotDoesNotCancelThePendingCapture() async throws {
        try await assertFinishCollectsLastFrame(holding: .beforeSnapshot)
    }

    @MainActor func testFinishDuringStitchingWaitsForThePendingAppend() async throws {
        try await assertFinishCollectsLastFrame(holding: .stitching)
    }

    @MainActor func testFinishOverridesQueuedResumeAndExportsOnlyOnce() async throws {
        let fixture = Fixture(holding: .stitching)
        defer { fixture.close() }
        fixture.driver.resume()
        await fulfillment(of: [fixture.checkpoint.entered], timeout: 5)
        fixture.driver.pause()
        fixture.driver.resume()
        fixture.driver.finish()
        fixture.driver.finish()
        fixture.driver.resume()
        XCTAssertTrue(fixture.driver.isFinishing)
        XCTAssertFalse(fixture.driver.isAutomatic)
        fixture.checkpoint.release()
        await fulfillment(of: [fixture.finished], timeout: 5)
        XCTAssertEqual(fixture.scrollCount, 1)
        XCTAssertEqual(fixture.finishCount, 1)
        try fixture.assertExport(height: 932, frames: 2)
    }

    @MainActor func testCancelDiscardsPendingFrameWithoutFinishing() async {
        let fixture = Fixture(holding: .settling)
        defer { fixture.close() }
        fixture.driver.resume()
        await fulfillment(of: [fixture.checkpoint.entered], timeout: 5)
        fixture.driver.cancel()
        fixture.captured.isInverted = true
        fixture.finished.isInverted = true
        fixture.driver.resume()
        fixture.driver.finish()
        fixture.checkpoint.release()
        await fulfillment(of: [fixture.captured, fixture.finished], timeout: 0.05)
        XCTAssertTrue(fixture.snapshots.isEmpty)
        XCTAssertEqual(fixture.stitcher.frameCount, 1)
    }

    @MainActor func testUnchangedPageStillPausesAfterTwoCaptures() async {
        let fixture = Fixture(expectedCaptures: 2)
        defer { fixture.close() }
        fixture.scrollAmount = 0
        fixture.driver.resume()
        await fulfillment(of: [fixture.endDetected], timeout: 5)
        XCTAssertFalse(fixture.driver.isAutomatic)
        XCTAssertEqual(fixture.snapshots, [0, 0])
        XCTAssertEqual(fixture.stitcher.frameCount, 1)
        XCTAssertEqual(fixture.finishCount, 0)
    }

    @MainActor private func assertFinishCollectsLastFrame(holding stage: Fixture.Stage) async throws {
        let fixture = Fixture(holding: stage)
        defer { fixture.close() }
        fixture.driver.resume()
        await fulfillment(of: [fixture.checkpoint.entered], timeout: 5)
        fixture.driver.finish()
        XCTAssertNil(fixture.exported)
        fixture.checkpoint.release()
        await fulfillment(of: [fixture.finished], timeout: 5)
        XCTAssertEqual(fixture.scrollCount, 1)
        XCTAssertEqual(fixture.snapshots, [302])
        try fixture.assertExport(height: 932, frames: 2)
    }
}

@MainActor
private final class Fixture {
    enum Stage { case gesture, settling, beforeSnapshot, stitching }
    let checkpoint = Checkpoint()
    let captured = XCTestExpectation(description: "frames captured")
    let finished = XCTestExpectation(description: "full image exported")
    let endDetected = XCTestExpectation(description: "unchanged page paused")
    private let holding: Stage?
    private var held = false
    private let source: CGImage
    let stitcher: ImageStitcher
    var scrollAmount = 302
    var offset = 0
    var scrollCount = 0
    var snapshots: [Int] = []
    var preparedAfterFrames: [Int] = []
    var finishAfterCaptures: Int?
    var finishCount = 0
    var exported: CGImage?

    lazy var driver = ScrollCaptureDriver(
        prepare: { [unowned self] in preparedAfterFrames.append(stitcher.frameCount) },
        scroll: { [unowned self] in
            scrollCount += 1
            offset += scrollAmount
            try await hold(at: .gesture)
            return true
        },
        capture: { [unowned self] in await captureFrame() },
        onAutomaticChange: { _ in },
        onCaptureActivityChange: { _ in },
        onFinish: { [unowned self] in
            exported = stitcher.makeImage()
            finishCount += 1
            finished.fulfill()
        },
        onEnd: { [unowned self] in endDetected.fulfill() },
        onError: { XCTFail("Unexpected driver error: \($0)") },
        wait: { [unowned self] delay in
            if case .settling = delay { try await hold(at: .settling) }
        }
    )

    init(holding: Stage? = nil, expectedCaptures: Int = 1) {
        self.holding = holding
        captured.expectedFulfillmentCount = expectedCaptures
        source = Self.makePattern(width: 160, height: 2_000)
        stitcher = ImageStitcher(firstImage: source.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 630))!)!
    }

    private func hold(at stage: Stage) async throws {
        guard holding == stage, !held else { return }
        held = true
        try await checkpoint.suspend()
    }

    private func captureFrame() async -> ImageStitcher.AppendResult? {
        do {
            // Stands in for the production capture's cancellable UI-removal delay.
            try await hold(at: .beforeSnapshot)
            let image = source.cropping(to: CGRect(x: 0, y: offset, width: 160, height: 630))!
            snapshots.append(offset)
            try await hold(at: .stitching)
            let result = stitcher.append(image)
            captured.fulfill()
            if snapshots.count == finishAfterCaptures { driver.finish() }
            return result
        } catch {
            return nil
        }
    }

    func close() {
        driver.cancel()
        checkpoint.release()
    }

    func assertExport(height: Int, frames: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(stitcher.frameCount, frames, file: file, line: line)
        let actual = try XCTUnwrap(exported, file: file, line: line)
        XCTAssertEqual(actual.height, height, file: file, line: line)
        let expected = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 160, height: height)))
        XCTAssertEqual(Self.pixels(actual), Self.pixels(expected), "Export must preserve every row", file: file, line: line)
    }

    private static func makePattern(width: Int, height: Int) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var value = UInt32(x) &* 747_796_405 &+ UInt32(y) &* 2_891_336_453 &+ 1
                value = ((value >> ((value >> 28) + 4)) ^ value) &* 277_803_737
                value = (value >> 22) ^ value
                let p = (y * width + x) * 4
                pixels[p] = UInt8(truncatingIfNeeded: value)
                pixels[p + 1] = UInt8(truncatingIfNeeded: value >> 8)
                pixels[p + 2] = UInt8(truncatingIfNeeded: value >> 16)
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func pixels(_ image: CGImage) -> Data {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Data(bytes)
    }
}

@MainActor
private final class Checkpoint {
    let entered = XCTestExpectation(description: "interruption point reached")
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func suspend() async throws {
        entered.fulfill()
        if !released {
            await withCheckedContinuation { continuation = $0 }
        }
        try Task.checkCancellation()
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

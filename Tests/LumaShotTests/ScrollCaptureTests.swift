import XCTest
import CoreGraphics
@testable import LumaShot

final class ScrollCaptureTests: XCTestCase {
    func testLeavingSelectionPausesRatherThanRepositioningThePointer() {
        let selection = CGRect(x: 100, y: 100, width: 600, height: 500)
        XCTAssertTrue(ScrollInput.allowsScrolling(at: CGPoint(x: 400, y: 350), in: selection, avoiding: nil))
        XCTAssertTrue(ScrollInput.allowsScrolling(at: CGPoint(x: 700, y: 600), in: selection, avoiding: nil))
        XCTAssertFalse(ScrollInput.allowsScrolling(at: CGPoint(x: 400, y: 650), in: selection, avoiding: nil))
    }

    func testMovingToControlsPausesEvenWhenControlsOverlapTheSelection() {
        let selection = CGRect(x: 100, y: 100, width: 600, height: 500)
        let controls = CGRect(x: 160, y: 110, width: 480, height: 154)
        XCTAssertFalse(ScrollInput.allowsScrolling(at: CGPoint(x: 300, y: 180), in: selection, avoiding: controls))
        XCTAssertTrue(ScrollInput.allowsScrolling(at: CGPoint(x: 400, y: 350), in: selection, avoiding: controls))
    }

    func testPixelScrollGestureHasExactDistanceAndEnds() throws {
        let point = CGPoint(x: 420, y: 360)
        let events = try XCTUnwrap(ScrollInput.events(at: point, pixels: 307))
        XCTAssertEqual(events.count, 7)
        XCTAssertEqual(events.first?.getIntegerValueField(.scrollWheelEventScrollPhase), Int64(CGScrollPhase.began.rawValue))
        XCTAssertEqual(events.last?.getIntegerValueField(.scrollWheelEventScrollPhase), Int64(CGScrollPhase.ended.rawValue))
        XCTAssertEqual(events.last?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 0)
        let distance = events.reduce(Int64(0)) { $0 + $1.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }
        XCTAssertEqual(distance, -307)
        for event in events {
            XCTAssertEqual(event.location, point)
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
            XCTAssertEqual(event.type, .scrollWheel)
            XCTAssertEqual(event.flags, [])
        }
        for event in events.dropFirst().dropLast() {
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventScrollPhase), Int64(CGScrollPhase.changed.rawValue))
        }
    }

    func testScrollTargetAvoidsControlsMovedOverTheSelectionCenter() throws {
        let selection = CGRect(x: -900, y: 120, width: 600, height: 800)
        let controls = CGRect(x: -840, y: 450, width: 480, height: 154)
        let target = try XCTUnwrap(ScrollInput.target(in: selection, avoiding: controls))
        XCTAssertTrue(selection.contains(target))
        XCTAssertFalse(controls.contains(target))
        XCTAssertEqual(target.x, selection.midX)
    }

    func testCompletelyCoveredSelectionRequiresMovingControls() {
        let selection = CGRect(x: 20, y: 20, width: 100, height: 100)
        XCTAssertNil(ScrollInput.target(in: selection, avoiding: CGRect(x: 0, y: 0, width: 480, height: 154)))
        XCTAssertEqual(ScrollInput.target(in: selection, avoiding: nil), CGPoint(x: 70, y: 70))
    }
}

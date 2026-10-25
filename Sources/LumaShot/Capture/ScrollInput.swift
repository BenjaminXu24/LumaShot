import AppKit
import CoreGraphics

/// A complete pixel-scroll gesture works in both AppKit and web-backed views.
enum ScrollInput {
    static func allowsScrolling(at point: CGPoint, in rect: CGRect, avoiding controls: CGRect?) -> Bool {
        rect.insetBy(dx: -2, dy: -2).contains(point) && !(controls?.contains(point) ?? false)
    }

    static func target(in rect: CGRect, avoiding controls: CGRect?) -> CGPoint? {
        let candidates = [
            CGPoint(x: rect.midX, y: rect.midY),
            CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.25),
            CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.75),
            CGPoint(x: rect.minX + rect.width * 0.25, y: rect.midY),
            CGPoint(x: rect.minX + rect.width * 0.75, y: rect.midY)
        ]
        return candidates.first { point in
            rect.contains(point) && !(controls?.insetBy(dx: -8, dy: -8).contains(point) ?? false)
        }
    }

    static func events(at point: CGPoint, pixels: Int32) -> [CGEvent]? {
        let steps = 6
        var events: [CGEvent] = []
        for step in 0..<steps {
            let delta = pixels / Int32(steps) + (step == steps - 1 ? pixels % Int32(steps) : 0)
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                      wheel1: -delta, wheel2: 0, wheel3: 0) else { return nil }
            event.location = point
            event.flags = []
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            let phase: CGScrollPhase = step == 0 ? .began : .changed
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            events.append(event)
        }
        guard let end = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                wheel1: 0, wheel2: 0, wheel3: 0) else { return nil }
        end.location = point
        end.flags = []
        end.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        end.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.ended.rawValue))
        events.append(end)
        return events
    }
}

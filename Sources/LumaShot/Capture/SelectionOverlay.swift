import AppKit
import ScreenCaptureKit

@MainActor
final class SelectionOverlay {
    struct Selection {
        let screen: NSScreen
        let rect: CGRect // Global Cocoa screen coordinates.
        let window: SCWindow?
    }

    private var panels: [SelectionPanel] = []
    private let mode: CaptureMode
    private let windows: [SCWindow]
    private var completion: ((Selection?) -> Void)?

    init(mode: CaptureMode, windows: [SCWindow], completion: @escaping (Selection?) -> Void) {
        self.mode = mode
        self.windows = windows
        self.completion = completion
    }

    func show() {
        for screen in NSScreen.screens {
            // Keep the user's app active while still receiving Escape and other
            // keyboard events when capture starts from a global shortcut.
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size),
                                     screen: screen, mode: mode, windows: windows)
            view.onComplete = { [weak self] rect, window in
                self?.finish(Selection(screen: screen, rect: rect, window: window))
            }
            view.onCancel = { [weak self] in self?.finish(nil) }
            panel.contentView = view
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        if let panel = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panels.first {
            panel.makeKey()
            panel.makeFirstResponder(panel.contentView)
        }
        NSCursor.crosshair.push()
    }

    func close() {
        guard !panels.isEmpty else { return }
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        NSCursor.pop()
    }

    func cancel() { finish(nil) }

    private func finish(_ selection: Selection?) {
        let callback = completion
        completion = nil
        close()
        callback?(selection)
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class SelectionView: NSView {
    let screen: NSScreen
    let mode: CaptureMode
    let candidates: [SCWindow]
    var onComplete: ((CGRect, SCWindow?) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var selection = CGRect.zero
    private var selectedWindow: SCWindow?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    init(frame: CGRect, screen: NSScreen, mode: CaptureMode, windows: [SCWindow]) {
        self.screen = screen
        self.mode = mode
        candidates = windows
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        let global = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let quartz = CGPoint(x: global.x, y: primaryHeight - global.y)
        selectedWindow = candidates.first { $0.frame.contains(quartz) }
        if let selectedWindow {
            let rect = CGRect(x: selectedWindow.frame.minX, y: primaryHeight - selectedWindow.frame.maxY,
                              width: selectedWindow.frame.width, height: selectedWindow.frame.height)
            selection = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        } else {
            selection = .zero
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        if mode == .window {
            mouseMoved(with: event)
            return
        }
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start, mode != .window else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if mode == .window {
            guard let selectedWindow else { return }
            onComplete?(selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), selectedWindow)
        } else if selection.width >= (mode == .scroll ? 24 : 2) && selection.height >= (mode == .scroll ? 24 : 2) {
            onComplete?(selection.integral.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), nil)
        } else {
            start = nil
            selection = .zero
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.38).setFill()
        shade.fill()
        if !selection.isEmpty {
            let border = NSBezierPath(roundedRect: selection.insetBy(dx: -1, dy: -1), xRadius: mode == .window ? 10 : 2, yRadius: mode == .window ? 10 : 2)
            NSColor(calibratedRed: 0.62, green: 0.63, blue: 1, alpha: 1).setStroke()
            border.lineWidth = 2
            border.stroke()
            if mode != .window {
                for point in [CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY),
                              CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY)] {
                    NSColor.white.setFill()
                    NSBezierPath(roundedRect: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6), xRadius: 2, yRadius: 2).fill()
                }
            }
            let size = "\(Int(selection.width)) × \(Int(selection.height))"
            drawPill(size, at: CGPoint(x: min(max(selection.midX - 48, 16), bounds.width - 130),
                                      y: min(max(selection.maxY + 12, 16), bounds.height - 44)), width: 112)
        }
        let hint: String
        switch mode {
        case .window: hint = "点击窗口截图  ·  Esc 取消"
        case .scroll: hint = "框选滚动内容区域  ·  尽量避开侧栏与固定工具栏  ·  Esc 取消"
        default: hint = "拖动选择截图区域  ·  Esc 取消"
        }
        let width = min(bounds.width - 40, mode == .scroll ? 510.0 : 310.0)
        drawPill(hint, at: CGPoint(x: (bounds.width - width) / 2, y: bounds.height - 86), width: width)
    }

    private func drawPill(_ text: String, at point: CGPoint, width: CGFloat) {
        let rect = CGRect(origin: point, size: CGSize(width: width, height: 34))
        NSColor(calibratedWhite: 0.09, alpha: 0.93).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (text as NSString).draw(in: rect.insetBy(dx: 8, dy: 9), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ])
    }
}

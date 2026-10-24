import AppKit
import SwiftUI

struct EditorCanvas: NSViewRepresentable {
    @ObservedObject var model: AnnotationEditorModel
    func makeNSView(context: Context) -> EditorScrollView {
        let scroll = EditorScrollView(model: model)
        return scroll
    }
    func updateNSView(_ view: EditorScrollView, context: Context) {
        view.canvas.model = model
        view.needsLayout = true
        view.canvas.needsDisplay = true
        view.canvas.window?.invalidateCursorRects(for: view.canvas)
    }
}

@MainActor
final class EditorScrollView: NSScrollView {
    let canvas: AnnotationCanvasView
    init(model: AnnotationEditorModel) {
        canvas = AnnotationCanvasView(model: model)
        super.init(frame: .zero)
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        borderType = .noBorder
        documentView = canvas
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        canvas.updateGeometry(viewport: contentView.bounds.size)
    }
    override func magnify(with event: NSEvent) {
        canvas.model.changeZoom(by: 1 + event.magnification)
    }
}

@MainActor
final class AnnotationCanvasView: NSView, NSUserInterfaceValidations {
    var model: AnnotationEditorModel
    private(set) var imageRect: CGRect = .zero
    private var drawingOrigin: CGPoint?
    private var previousPoint: CGPoint?
    private var isMovingSelection = false
    private var isPanning = false
    private var selectionCheckpointed = false
    private var scale: CGFloat = 1
    private var lastZoom: CGFloat? = nil
    private var lastImageSize: CGSize = .zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(model: AnnotationEditorModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let attachedWindow = window else { return }
        attachedWindow.initialFirstResponder = self
        DispatchQueue.main.async { [weak self, weak attachedWindow] in
            guard let self, let attachedWindow, self.window === attachedWindow,
                  !(attachedWindow.firstResponder is NSText) else { return }
            attachedWindow.makeFirstResponder(self)
        }
    }
    func updateGeometry(viewport: CGSize) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let pixels = model.pixelSize
        guard pixels.width > 0, pixels.height > 0 else { return }
        let fitting = min(max(1, viewport.width - 112) / pixels.width,
                          max(1, viewport.height - 168) / pixels.height, 1)
        let newScale = model.zoom ?? fitting
        let displaySize = CGSize(width: pixels.width * newScale, height: pixels.height * newScale)
        let docSize = CGSize(width: max(viewport.width, displaySize.width + 112),
                             height: max(viewport.height, displaySize.height + 168))
        let shouldCenter = model.zoom != lastZoom || pixels != lastImageSize
        lastZoom = model.zoom
        lastImageSize = pixels
        scale = newScale
        imageRect = CGRect(x: (docSize.width - displaySize.width) / 2, y: 112 + (docSize.height - 168 - displaySize.height) / 2,
                           width: displaySize.width, height: displaySize.height)
        if frame.size != docSize { setFrameSize(docSize) }
        if shouldCenter, let clip = enclosingScrollView?.contentView {
            let origin = CGPoint(x: max(0, (docSize.width - viewport.width) / 2),
                                 y: max(0, (docSize.height - viewport.height) / 2))
            clip.scroll(to: origin)
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
        if abs(model.effectiveScale - newScale) > 0.0001 {
            // Geometry changes during SwiftUI layout; publish after this update finishes.
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.model.effectiveScale - self.scale) > 0.0001 else { return }
                self.model.effectiveScale = self.scale
            }
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor(srgbRed: 0.951, green: 0.951, blue: 0.969, alpha: 1).setFill()
        dirtyRect.fill()
        let dotSpacing: CGFloat = 20
        context.setFillColor(NSColor(srgbRed: 0.81, green: 0.81, blue: 0.86, alpha: 0.55).cgColor)
        let startX = floor(dirtyRect.minX / dotSpacing) * dotSpacing
        let startY = floor(dirtyRect.minY / dotSpacing) * dotSpacing
        var y = startY
        while y < dirtyRect.maxY {
            var x = startX
            while x < dirtyRect.maxX {
                context.fillEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                x += dotSpacing
            }
            y += dotSpacing
        }
        guard imageRect.width > 0, let source = model.pixelImage else { return }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 5), blur: 20,
                          color: NSColor.black.withAlphaComponent(0.12).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(imageRect)
        context.restoreGState()
        model.image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1,
                         respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        context.saveGState()
        context.clip(to: imageRect)
        context.translateBy(x: imageRect.minX, y: imageRect.minY)
        context.scaleBy(x: scale, y: scale)
        AnnotationRenderer.draw(model.annotations, in: context, source: source)
        if let draft = model.draft { AnnotationRenderer.draw(draft, in: context, source: source) }
        context.restoreGState()
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor)
        context.setLineWidth(1)
        context.stroke(imageRect.insetBy(dx: -0.5, dy: -0.5))
        if let id = model.selectedID, let annotation = model.annotations.first(where: { $0.id == id }) {
            let r = displayRect(annotation.rect).insetBy(dx: -7, dy: -7)
            context.setStrokeColor(NSColor(srgbRed: 0.49, green: 0.35, blue: 0.94, alpha: 1).cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [5, 4])
            context.stroke(r)
            context.setLineDash(phase: 0, lengths: [])
            for point in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                          CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
                context.strokeEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
            }
        }
        drawOCRSelection(in: context)
    }
    private func drawOCRSelection(in context: CGContext) {
        guard let selection = model.ocrSelection, selection.width > 0.5, selection.height > 0.5 else { return }
        let rect = displayRect(selection)
        context.saveGState()
        context.setFillColor(NSColor(srgbRed: 0.49, green: 0.35, blue: 0.94, alpha: 0.14).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor(srgbRed: 0.49, green: 0.35, blue: 0.94, alpha: 1).cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.stroke(rect)
        context.restoreGState()
    }
    override func resetCursorRects() {
        let cursor: NSCursor
        if model.regionRecognitionArmed {
            cursor = .crosshair
        } else {
            switch model.tool {
            case .select: cursor = .arrow
            case .hand: cursor = .openHand
            case .text: cursor = .iBeam
            default: cursor = .crosshair
            }
        }
        addCursorRect(visibleRect, cursor: cursor)
    }
    private func imagePoint(_ event: NSEvent, constrained: Bool = true) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        var point = CGPoint(x: (local.x - imageRect.minX) / scale, y: (local.y - imageRect.minY) / scale)
        if constrained {
            point.x = min(max(0, point.x), model.pixelSize.width)
            point.y = min(max(0, point.y), model.pixelSize.height)
        }
        return point
    }
    private func displayRect(_ rect: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + rect.minX * scale, y: imageRect.minY + rect.minY * scale,
               width: rect.width * scale, height: rect.height * scale)
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let local = convert(event.locationInWindow, from: nil)
        if model.tool == .hand || event.modifierFlags.contains(.option) {
            isPanning = true
            previousPoint = event.locationInWindow
            NSCursor.closedHand.set()
            return
        }
        if model.regionRecognitionArmed {
            guard imageRect.contains(local) else { model.ocrSelection = nil; return }
            let point = imagePoint(event)
            drawingOrigin = point
            model.selectedID = nil
            model.ocrSelection = CGRect(origin: point, size: .zero)
            return
        }
        guard imageRect.contains(local) else { model.selectedID = nil; return }
        let point = imagePoint(event)
        drawingOrigin = point
        previousPoint = point
        if model.tool == .select {
            let tolerance = 7 / scale
            model.selectedID = model.annotations.reversed().first { $0.rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }?.id
            isMovingSelection = model.selectedID != nil
            selectionCheckpointed = false
            return
        }
        model.selectedID = nil
        if model.tool == .text {
            addText(at: point)
            drawingOrigin = nil
            return
        }
        if model.tool == .number {
            let number = (model.annotations.filter { $0.tool == .number }.map(\.number).max() ?? 0) + 1
            model.commit(EditorAnnotation(tool: .number, points: [point], color: model.color,
                                          lineWidth: model.lineWidth, number: number, fontSize: model.fontSize))
            drawingOrigin = nil
            return
        }
        model.draft = EditorAnnotation(tool: model.tool, points: model.tool == .pen ? [point] : [point, point], color: model.color,
                                       lineWidth: model.lineWidth, fontSize: model.fontSize)
    }
    override func mouseDragged(with event: NSEvent) {
        if isPanning {
            guard let previous = previousPoint, let scroll = enclosingScrollView else { return }
            let now = event.locationInWindow
            let origin = scroll.contentView.bounds.origin
            scroll.contentView.scroll(to: CGPoint(x: max(0, min(frame.width - scroll.contentView.bounds.width, origin.x - (now.x - previous.x))),
                                                  y: max(0, min(frame.height - scroll.contentView.bounds.height, origin.y + (now.y - previous.y)))))
            scroll.reflectScrolledClipView(scroll.contentView)
            previousPoint = now
            return
        }
        if model.regionRecognitionArmed {
            guard let origin = drawingOrigin else { return }
            model.ocrSelection = Self.spanning(origin, imagePoint(event))
            needsDisplay = true
            return
        }
        guard let origin = drawingOrigin else { return }
        var point = imagePoint(event)
        if isMovingSelection, let id = model.selectedID, let previous = previousPoint,
           let index = model.annotations.firstIndex(where: { $0.id == id }) {
            if !selectionCheckpointed { model.checkpoint(); selectionCheckpointed = true }
            model.annotations[index].translate(by: CGSize(width: point.x - previous.x, height: point.y - previous.y))
            previousPoint = point
            return
        }
        guard var draft = model.draft else { return }
        if event.modifierFlags.contains(.shift) {
            let dx = point.x - origin.x, dy = point.y - origin.y
            if draft.tool == .arrow {
                let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                let distance = hypot(dx, dy)
                point = CGPoint(x: origin.x + cos(angle) * distance, y: origin.y + sin(angle) * distance)
            } else if draft.tool == .rectangle || draft.tool == .ellipse {
                let side = max(abs(dx), abs(dy))
                point = CGPoint(x: origin.x + (dx >= 0 ? side : -side), y: origin.y + (dy >= 0 ? side : -side))
            }
        }
        if draft.tool == .pen { draft.points.append(point) }
        else { draft.points = [origin, point] }
        model.draft = draft
    }
    override func mouseUp(with event: NSEvent) {
        let recognizeDrag = model.regionRecognitionArmed && !isPanning
        let selection = model.ocrSelection
        defer {
            drawingOrigin = nil
            previousPoint = nil
            isMovingSelection = false
            isPanning = false
            window?.invalidateCursorRects(for: self)
        }
        if recognizeDrag {
            if let selection, selection.width >= 4, selection.height >= 4 {
                model.recognizeSelection(selection)
            } else if selection != nil {
                model.ocrSelection = nil
                model.showToast("拖动框选需要识别的区域")
            }
            return
        }
        guard let draft = model.draft else { return }
        if draft.tool == .pen || max(draft.rect.width, draft.rect.height) >= 3 / scale {
            model.commit(draft)
        } else { model.draft = nil }
    }
    override func magnify(with event: NSEvent) {
        model.changeZoom(by: 1 + event.magnification)
    }
    @objc func copy(_ sender: Any?) { model.copyImage() }
    @objc func saveDocument(_ sender: Any?) { model.saveImage() }
    @objc func undo(_ sender: Any?) { model.undo() }
    @objc func redo(_ sender: Any?) { model.redo() }
    @objc func delete(_ sender: Any?) { model.deleteSelection() }
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return model.canUndo
        case #selector(redo(_:)): return model.canRedo
        case #selector(delete(_:)): return model.selectedID != nil
        default: return true
        }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { model.deleteSelection(); return }
        if event.keyCode == 53 {
            model.draft = nil
            model.selectedID = nil
            model.ocrSelection = nil
            drawingOrigin = nil
            return
        }
        let command = event.modifierFlags.contains(.command)
        if command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": model.copyImage(); return
            case "s": model.saveImage(); return
            case "z": event.modifierFlags.contains(.shift) ? model.redo() : model.undo(); return
            case "0": model.zoom = nil; return
            case "1": model.zoom = 1; return
            default: break
            }
        }
        super.keyDown(with: event)
    }
    private static func spanning(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
    private func addText(at point: CGPoint) {
        let alert = NSAlert()
        alert.messageText = "添加文字"
        alert.informativeText = "为截图补充一句说明。"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 340, height: 56))
        field.placeholderString = "输入标注文字…"
        field.font = NSFont.systemFont(ofSize: 15)
        field.maximumNumberOfLines = 3
        field.lineBreakMode = .byWordWrapping
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.commit(EditorAnnotation(tool: .text, points: [point], color: model.color,
                                      lineWidth: model.lineWidth, text: text, fontSize: model.fontSize))
    }
}

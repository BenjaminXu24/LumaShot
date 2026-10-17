import AppKit
import SwiftUI
import CoreText
import UniformTypeIdentifiers

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, arrow, rectangle, ellipse, pen, text, number, mosaic, hand
    var id: String { rawValue }
    var name: String {
        switch self {
        case .select: return "选择"
        case .arrow: return "箭头"
        case .rectangle: return "矩形"
        case .ellipse: return "圆形"
        case .pen: return "画笔"
        case .text: return "文字"
        case .number: return "序号"
        case .mosaic: return "马赛克"
        case .hand: return "移动"
        }
    }
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .number: return "1.circle"
        case .mosaic: return "square.grid.3x3.fill"
        case .hand: return "hand.draw"
        }
    }
    var hint: String {
        switch self {
        case .select: return "点选标注可移动，按 Delete 删除"
        case .arrow: return "拖动绘制箭头，按住 Shift 锁定方向"
        case .rectangle: return "拖动绘制矩形，按住 Shift 绘制正方形"
        case .ellipse: return "拖动绘制椭圆，按住 Shift 绘制正圆"
        case .pen: return "按住鼠标自由书写"
        case .text: return "点击画布添加文字"
        case .number: return "点击画布添加连续序号"
        case .mosaic: return "拖动框选需要隐藏的区域"
        case .hand: return "拖动画布查看，双指捏合缩放"
        }
    }
}

struct EditorAnnotation: Identifiable {
    let id: UUID
    var tool: AnnotationTool
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text: String
    var number: Int
    var fontSize: CGFloat

    init(tool: AnnotationTool, points: [CGPoint], color: NSColor, lineWidth: CGFloat,
         text: String = "", number: Int = 1, fontSize: CGFloat = 32) {
        id = UUID()
        self.tool = tool
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.number = number
        self.fontSize = fontSize
    }
    var rect: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .text {
            let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)])
            return CGRect(origin: first, size: CGSize(width: max(12, size.width), height: max(fontSize, size.height)))
        }
        if tool == .number {
            return CGRect(x: first.x - fontSize * 0.62, y: first.y - fontSize * 0.62,
                          width: fontSize * 1.24, height: fontSize * 1.24)
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min() ?? first.x, y: ys.min() ?? first.y,
                      width: (xs.max() ?? first.x) - (xs.min() ?? first.x),
                      height: (ys.max() ?? first.y) - (ys.min() ?? first.y))
    }
    mutating func translate(by delta: CGSize) {
        points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
    }
}

@MainActor
final class AnnotationEditorModel: ObservableObject {
    @Published var image: NSImage
    @Published var tool: AnnotationTool = .arrow
    @Published var color: NSColor = NSColor(srgbRed: 0.49, green: 0.35, blue: 0.94, alpha: 1)
    @Published var lineWidth: CGFloat = 8
    @Published var annotations: [EditorAnnotation] = []
    @Published var draft: EditorAnnotation?
    @Published var selectedID: UUID?
    @Published var zoom: CGFloat? = nil
    @Published var effectiveScale: CGFloat = 1
    @Published var toast: String?
    @Published private(set) var undoStack: [[EditorAnnotation]] = []
    @Published private(set) var redoStack: [[EditorAnnotation]] = []
    private var toastTask: Task<Void, Never>?
    let onCopy: (NSImage) -> Void
    let onSave: (NSImage) -> Void

    init(image: NSImage, onCopy: @escaping (NSImage) -> Void, onSave: @escaping (NSImage) -> Void) {
        self.image = image
        self.onCopy = onCopy
        self.onSave = onSave
        lineWidth = max(4, min(14, CGFloat(pixelImage?.width ?? 1600) / 200))
    }
    var pixelImage: CGImage? { image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    var pixelSize: CGSize {
        guard let cg = pixelImage else { return image.size }
        return CGSize(width: cg.width, height: cg.height)
    }
    var fontSize: CGFloat { max(22, min(80, pixelSize.width / 42)) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func checkpoint() {
        undoStack.append(annotations)
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    func commit(_ annotation: EditorAnnotation) {
        checkpoint()
        annotations.append(annotation)
        draft = nil
        selectedID = nil
    }
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedID = nil
        draft = nil
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedID = nil
        draft = nil
    }
    func deleteSelection() {
        guard let id = selectedID else { return }
        checkpoint()
        annotations.removeAll { $0.id == id }
        selectedID = nil
    }
    func clear() {
        guard !annotations.isEmpty else { return }
        checkpoint()
        annotations.removeAll()
        selectedID = nil
    }
    func renderedImage() -> NSImage? {
        AnnotationRenderer.render(image: image, annotations: annotations)
    }
    func copyImage() {
        guard let rendered = renderedImage() else { showToast("图片暂时无法导出"); return }
        onCopy(rendered)
        showToast("已复制到剪贴板")
    }
    func saveImage() {
        guard let rendered = renderedImage() else { showToast("图片暂时无法导出"); return }
        onSave(rendered)
    }
    func changeZoom(by factor: CGFloat) {
        zoom = min(8, max(0.05, (zoom ?? effectiveScale) * factor))
    }
    func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "打开图片"
        guard panel.runModal() == .OK, let url = panel.url, let newImage = NSImage(contentsOf: url) else { return }
        image = newImage
        annotations = []
        draft = nil
        selectedID = nil
        undoStack = []
        redoStack = []
        zoom = nil
        lineWidth = max(4, min(14, pixelSize.width / 200))
    }
}

/// All geometry uses original image pixels, measured from the top-left corner.
/// The bitmap export uses the source CGImage dimensions, independent of display scale.
enum AnnotationRenderer {
    static func render(image: NSImage, annotations: [EditorAnnotation]) -> NSImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        context.translateBy(x: 0, y: CGFloat(source.height))
        context.scaleBy(x: 1, y: -1)
        draw(annotations, in: context, source: source)
        guard let result = context.makeImage() else { return nil }
        return NSImage(cgImage: result, size: image.size)
    }
    static func draw(_ annotations: [EditorAnnotation], in context: CGContext, source: CGImage) {
        for annotation in annotations { draw(annotation, in: context, source: source) }
    }
    static func draw(_ a: EditorAnnotation, in context: CGContext, source: CGImage) {
        guard let first = a.points.first else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(a.color.cgColor)
        context.setFillColor(a.color.cgColor)
        context.setLineWidth(a.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch a.tool {
        case .rectangle:
            context.stroke(a.rect)
        case .ellipse:
            context.strokeEllipse(in: a.rect)
        case .arrow:
            guard let end = a.points.last else { return }
            let angle = atan2(end.y - first.y, end.x - first.x)
            let length = hypot(end.x - first.x, end.y - first.y)
            let head = min(length * 0.45, max(a.lineWidth * 3.8, 18))
            context.move(to: first)
            context.addLine(to: end)
            context.strokePath()
            context.move(to: CGPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6)))
            context.addLine(to: end)
            context.addLine(to: CGPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6)))
            context.strokePath()
        case .pen:
            if a.points.count == 1 {
                context.fillEllipse(in: CGRect(x: first.x - a.lineWidth / 2, y: first.y - a.lineWidth / 2,
                                              width: a.lineWidth, height: a.lineWidth))
            } else {
                context.addLines(between: a.points)
                context.strokePath()
            }
        case .text:
            drawText(a.text, at: first, size: a.fontSize, color: a.color, in: context)
        case .number:
            context.fillEllipse(in: a.rect)
            let text = String(a.number)
            let fontSize = a.fontSize * 0.75
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white]))
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            drawText(text, at: CGPoint(x: first.x - width / 2, y: first.y - (ascent + descent) / 2),
                     size: fontSize, color: .white, in: context, weight: .bold, monospaced: true)
        case .mosaic:
            drawMosaic(in: a.rect, context: context, source: source)
        case .select, .hand: break
        }
    }
    private static func drawText(_ text: String, at point: CGPoint, size: CGFloat, color: NSColor,
                                 in context: CGContext, weight: NSFont.Weight = .semibold, monospaced: Bool = false) {
        let font = monospaced ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let lines = text.components(separatedBy: .newlines)
        let lineHeight = font.ascender - font.descender + font.leading
        for (index, string) in lines.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]))
            context.saveGState()
            context.translateBy(x: point.x, y: point.y + font.ascender + CGFloat(index) * lineHeight)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }
    private static func drawMosaic(in rect: CGRect, context: CGContext, source: CGImage) {
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let area = rect.integral.intersection(bounds)
        guard area.width >= 1, area.height >= 1, let cropped = source.cropping(to: area) else { return }
        let block = max(10, min(28, CGFloat(source.width) / 100))
        let w = max(1, Int(area.width / block)), h = max(1, Int(area.height / block))
        guard let small = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .low
        small.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let pixelated = small.makeImage() else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.translateBy(x: area.minX, y: area.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(pixelated, in: CGRect(origin: .zero, size: area.size))
        context.restoreGState()
    }
}

import AppKit
import UniformTypeIdentifiers

enum ExportService {
    @MainActor
    @discardableResult
    static func copy(_ image: NSImage) -> Bool {
        guard let bitmap = ImageEncoding.bitmap(from: image),
              let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        let pasteboard = NSPasteboard.general
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = bitmap.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    /// Copies recognized text only. Whitespace-only strings are left off the pasteboard.
    @MainActor
    @discardableResult
    static func copyText(_ text: String, pasteboard: NSPasteboard = .general) -> Bool {
        guard text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    @MainActor
    @discardableResult
    static func save(_ image: NSImage, suggestedName: String? = nil) -> URL? {
        guard let bitmap = ImageEncoding.bitmap(from: image) else { return nil }
        let panel = NSSavePanel()
        panel.title = "保存截图"
        panel.message = "以原始分辨率保存截图"
        panel.prompt = "保存"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let baseName = suggestedName ?? "拾光截图 \(formatter.string(from: Date()))"
        let filename = URL(fileURLWithPath: baseName).lastPathComponent
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        let stem = ["png", "jpg", "jpeg"].contains(fileExtension) ? (filename as NSString).deletingPathExtension : filename
        panel.nameFieldStringValue = stem + ".png"

        let formatController = SaveFormatController(panel: panel)
        panel.accessoryView = formatController.view
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }
        let isJPEG = formatController.selectedFormat == .jpeg
        let data: Data?
        if isJPEG {
            data = jpegData(from: bitmap)
        } else {
            data = bitmap.representation(using: .png, properties: [:])
        }
        guard let data else {
            let alert = NSAlert()
            alert.messageText = "无法导出这张截图"
            alert.informativeText = "图像可能过大，或没有足够的可用内存。请尝试使用 PNG 格式，或重新截取较小的区域。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return nil
        }
        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "截图保存失败"
            alert.runModal()
            return nil
        }
    }

    /// JPEG does not support transparency, so explicitly composite onto white.
    private static func jpegData(from bitmap: NSBitmapImageRep) -> Data? {
        guard let image = bitmap.cgImage,
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor.white)
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flattened = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: flattened).representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }
}

@MainActor
private final class SaveFormatController: NSObject {
    enum Format { case png, jpeg }
    weak var panel: NSSavePanel?
    let view: NSView
    private let picker: NSPopUpButton
    var selectedFormat: Format { picker.indexOfSelectedItem == 1 ? .jpeg : .png }

    init(panel: NSSavePanel) {
        self.panel = panel
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 36))
        let label = NSTextField(labelWithString: "图像格式")
        label.frame = NSRect(x: 0, y: 8, width: 72, height: 20)
        picker = NSPopUpButton(frame: NSRect(x: 76, y: 4, width: 200, height: 28), pullsDown: false)
        super.init()
        picker.addItems(withTitles: ["PNG · 无损图像", "JPEG · 较小文件"])
        picker.target = self
        picker.action = #selector(formatChanged)
        view.addSubview(label)
        view.addSubview(picker)
    }

    @objc private func formatChanged() {
        guard let panel else { return }
        let extensionName = selectedFormat == .jpeg ? "jpg" : "png"
        panel.allowedContentTypes = selectedFormat == .jpeg ? [.jpeg] : [.png]
        let name = panel.nameFieldStringValue as NSString
        panel.nameFieldStringValue = name.deletingPathExtension + "." + extensionName
    }
}

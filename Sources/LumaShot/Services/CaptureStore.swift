import AppKit
import Combine
import ImageIO

struct CaptureItem: Identifiable, Codable, Equatable {
    let id: UUID
    let filename: String
    let mode: CaptureMode
    let createdAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
}

/// A small, local screenshot library. Images are always stored at their native pixel size.
@MainActor
final class CaptureStore: ObservableObject {
    @Published private(set) var items: [CaptureItem] = []
    let directory: URL
    private let retentionLimit: Int
    private let fileManager: FileManager
    private let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        cache.countLimit = 100
        return cache
    }()
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init(directory: URL? = nil, retentionLimit: Int = 100, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.retentionLimit = max(1, retentionLimit)
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LumaShot", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
        restore()
    }

    @discardableResult
    func add(image: NSImage, mode: CaptureMode) -> CaptureItem? {
        guard let bitmap = ImageEncoding.bitmap(from: image),
              let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let identifier = UUID()
        let item = CaptureItem(
            id: identifier,
            filename: "\(identifier.uuidString).png",
            mode: mode,
            createdAt: Date(),
            pixelWidth: bitmap.pixelsWide,
            pixelHeight: bitmap.pixelsHigh
        )
        let imageURL = directory.appendingPathComponent(item.filename)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: imageURL, options: .atomic)
            let updatedItems = Array(([item] + items).prefix(retentionLimit))
            try persist(updatedItems)
            let removedItems = items.filter { old in !updatedItems.contains(where: { $0.id == old.id }) }
            items = updatedItems
            for removed in removedItems {
                thumbnailCache.removeObject(forKey: removed.id.uuidString as NSString)
                try? fileManager.removeItem(at: directory.appendingPathComponent(removed.filename))
            }
            return item
        } catch {
            try? fileManager.removeItem(at: imageURL)
            return nil
        }
    }

    func image(for item: CaptureItem) -> NSImage? {
        guard Self.isSafeFilename(item.filename) else { return nil }
        return NSImage(contentsOf: directory.appendingPathComponent(item.filename))
    }

    func thumbnail(for item: CaptureItem) -> NSImage? {
        guard Self.isSafeFilename(item.filename) else { return nil }
        let cacheKey = item.id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) { return cached }
        let url = directory.appendingPathComponent(item.filename)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let thumbnail = NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
        thumbnailCache.setObject(thumbnail, forKey: cacheKey, cost: bitmap.bytesPerRow * bitmap.height)
        return thumbnail
    }

    func delete(_ item: CaptureItem) {
        guard let storedItem = items.first(where: { $0.id == item.id }) else { return }
        let updatedItems = items.filter { $0.id != item.id }
        do {
            try persist(updatedItems)
            items = updatedItems
            thumbnailCache.removeObject(forKey: storedItem.id.uuidString as NSString)
            if Self.isSafeFilename(storedItem.filename) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(storedItem.filename))
            }
        } catch {
            // Leave the current library intact if its updated index cannot be committed.
        }
    }

    func clear() {
        do {
            try persist([])
            let previousItems = items
            items = []
            thumbnailCache.removeAllObjects()
            for item in previousItems where Self.isSafeFilename(item.filename) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(item.filename))
            }
        } catch {
            // Keep files and their index consistent when the destination becomes unwritable.
        }
    }

    private func restore() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            guard fileManager.fileExists(atPath: indexURL.path) else { return }
            let savedItems = try JSONDecoder().decode([CaptureItem].self, from: Data(contentsOf: indexURL))
            var identifiers = Set<UUID>()
            let validItems = savedItems
                .filter { item in
                    Self.isSafeFilename(item.filename)
                        && item.pixelWidth > 0 && item.pixelHeight > 0
                        && fileManager.fileExists(atPath: directory.appendingPathComponent(item.filename).path)
                        && identifiers.insert(item.id).inserted
                }
                .sorted { $0.createdAt > $1.createdAt }
            let retainedItems = Array(validItems.prefix(retentionLimit))
            try persist(retainedItems)
            items = retainedItems
            for item in validItems.dropFirst(retentionLimit) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(item.filename))
            }
        } catch {
            items = []
        }
    }

    private func persist(_ updatedItems: [CaptureItem]) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updatedItems).write(to: indexURL, options: .atomic)
    }

    private static func isSafeFilename(_ filename: String) -> Bool {
        !filename.isEmpty && filename == URL(fileURLWithPath: filename).lastPathComponent
            && filename.lowercased().hasSuffix(".png")
            && !filename.contains("/") && !filename.contains("\\")
    }
}

enum ImageEncoding {
    static func bitmap(from image: NSImage) -> NSBitmapImageRep? {
        // Picking the bitmap representation avoids downsampling Retina captures to point size.
        if let original = image.representations.compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
           let cgImage = original.cgImage {
            return NSBitmapImageRep(cgImage: cgImage)
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage)
    }
}

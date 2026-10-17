import AppKit
import CoreGraphics

/// Joins successive views of the same vertically scrolling surface. Coordinates are
/// image pixels, so Retina captures keep their original detail.
final class ImageStitcher {
    enum AppendResult: Equatable {
        case appended(addedPixels: Int, totalHeight: Int)
        case unchanged
        case noOverlap
        case heightLimit
    }

    private struct Signature {
        let width = 80
        let height: Int
        let pixels: [UInt8]
        let anchors: [Int]

        init?(_ image: CGImage) {
            let sampleWidth = 80
            let sampleHeight = image.height
            height = sampleHeight
            var storage = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
            let success = storage.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: sampleWidth, height: sampleHeight,
                                              bitsPerComponent: 8, bytesPerRow: sampleWidth * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.interpolationQuality = .low
                context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
                return true
            }
            guard success else { return nil }
            var values = [UInt8](repeating: 0, count: width * height)
            for y in 0..<height {
                for x in 0..<width {
                    let p = (y * width + x) * 4
                    values[y * width + x] = UInt8((Int(storage[p]) * 3 + Int(storage[p + 1]) * 6 + Int(storage[p + 2])) / 10)
                }
            }
            pixels = values
            // Include informative rows in addition to evenly spaced samples.
            // This prevents a thin line or a short text band on a mostly white
            // page from falling entirely between the sampling grid's rows.
            var contentRows: [Int] = []
            let binSize = max(1, sampleHeight / 24)
            for start in stride(from: 0, to: sampleHeight, by: binSize) {
                var strongestRow = start
                var strongestEnergy = 0
                for y in start..<min(sampleHeight, start + binSize) {
                    var low = 255
                    var high = 0
                    var vertical = 0
                    for x in stride(from: 7, to: sampleWidth - 7, by: 2) {
                        let value = Int(values[y * sampleWidth + x])
                        low = min(low, value)
                        high = max(high, value)
                        if y > 0 { vertical += abs(value - Int(values[(y - 1) * sampleWidth + x])) }
                    }
                    let energy = high - low + vertical / 33
                    if energy > strongestEnergy { strongestEnergy = energy; strongestRow = y }
                }
                if strongestEnergy > 4 { contentRows.append(strongestRow) }
            }
            anchors = contentRows
        }

        func rowDifference(to other: Signature, first: Int, second: Int) -> Double {
            var sum = 0
            var count = 0
            // Ignore scrollbars and narrow stationary side decorations.
            for x in stride(from: 7, to: width - 7, by: 2) {
                sum += abs(Int(pixels[first * width + x]) - Int(other.pixels[second * width + x]))
                count += 1
            }
            return Double(sum) / Double(max(1, count))
        }

        func difference(to other: Signature, shift: Int, top: Int, bottom: Int, samples: Int = 34) -> Double {
            let start = top
            let end = height - shift - bottom
            guard end - start > 24 else { return .infinity }
            var total: Double = 0
            var count = 0
            let step = max(1, (end - start) / samples)
            for y in stride(from: start, to: end, by: step) {
                total += rowDifference(to: other, first: y + shift, second: y)
                count += 1
            }
            for y in other.anchors where y >= start && y < end {
                total += rowDifference(to: other, first: y + shift, second: y)
                count += 1
            }
            for previousY in anchors {
                let y = previousY - shift
                if y >= start && y < end {
                    total += rowDifference(to: other, first: previousY, second: y)
                    count += 1
                }
            }
            return total / Double(max(1, count))
        }
    }

    private var previous: CGImage
    private var signature: Signature
    private var segments: [CGImage]
    private var footer: CGImage?
    private var footerHeight = 0
    private var hasAppended = false
    private(set) var totalHeight: Int
    private(set) var frameCount = 1
    let maximumHeight: Int

    init?(firstImage: CGImage, maximumHeight: Int = 50_000) {
        guard let signature = Signature(firstImage) else { return nil }
        previous = firstImage
        self.signature = signature
        segments = [firstImage]
        totalHeight = firstImage.height
        // Bound both length and total bitmap allocation on wide Retina screens.
        self.maximumHeight = min(maximumHeight, max(firstImage.height, 80_000_000 / max(1, firstImage.width)))
    }

    func append(_ image: CGImage) -> AppendResult {
        guard image.width == previous.width, image.height == previous.height,
              let next = Signature(image) else { return .noOverlap }
        let height = image.height
        let edgeLimit = max(1, height / 5)
        var top = 0
        var bottom = 0
        // A sticky toolbar or fixed footer is present in the same position in
        // successive frames. Exclude it from alignment and keep one copy.
        while top < edgeLimit && signature.rowDifference(to: next, first: top, second: top) < 2.2 { top += 1 }
        while bottom < edgeLimit && signature.rowDifference(to: next, first: height - bottom - 1, second: height - bottom - 1) < 2.2 { bottom += 1 }
        // An entirely matching margin gives no evidence of a fixed toolbar;
        // treating white page space as a footer can drop later content.
        if top == edgeLimit { top = 0 }
        if bottom == edgeLimit { bottom = 0 }
        let baseline = signature.difference(to: next, shift: 0, top: 0, bottom: 0, samples: 70)
        if baseline < 1.1 { return .unchanged }

        let minimumOverlap = max(40, height / 7)
        let maximumShift = height - max(minimumOverlap, top + bottom + 32)
        guard maximumShift > 0 else { return .noOverlap }
        var bestShift = 0
        var bestScore = Double.infinity
        // Every pixel is considered; the sampled columns keep this inexpensive
        // while avoiding subpixel seams at Retina scale.
        for shift in 1...maximumShift {
            let score = signature.difference(to: next, shift: shift, top: top, bottom: bottom)
            if score < bestScore {
                bestScore = score
                bestShift = shift
            }
        }
        guard bestShift > 0,
              bestScore < 17,
              bestScore < baseline * 0.78 || bestScore < 2 else { return .noOverlap }
        // Check more rows before accepting a match in sparse or repetitive pages.
        let verified = signature.difference(to: next, shift: bestShift, top: top, bottom: bottom, samples: 120)
        guard verified < 20 else { return .noOverlap }
        guard totalHeight + bestShift <= maximumHeight else { return .heightLimit }

        if !hasAppended {
            footerHeight = bottom >= 3 ? bottom : 0
            if footerHeight > 0 {
                guard let body = previous.cropping(to: CGRect(x: 0, y: 0, width: previous.width, height: height - footerHeight)) else { return .noOverlap }
                segments = [body]
            }
        }
        let contentStart = height - footerHeight - bestShift
        guard contentStart >= top,
              let addition = image.cropping(to: CGRect(x: 0, y: contentStart, width: image.width, height: bestShift)) else { return .noOverlap }
        segments.append(addition)
        if footerHeight > 0 {
            footer = image.cropping(to: CGRect(x: 0, y: height - footerHeight, width: image.width, height: footerHeight))
        }
        totalHeight += bestShift
        frameCount += 1
        previous = image
        signature = next
        hasAppended = true
        return .appended(addedPixels: bestShift, totalHeight: totalHeight)
    }

    func makeImage() -> CGImage? {
        guard let context = CGContext(data: nil, width: previous.width, height: totalHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var offset = 0
        for segment in segments + (footer.map { [$0] } ?? []) {
            context.draw(segment, in: CGRect(x: 0, y: totalHeight - offset - segment.height,
                                            width: segment.width, height: segment.height))
            offset += segment.height
        }
        return context.makeImage()
    }
}

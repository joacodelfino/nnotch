import AppKit
import ImageIO

/// Decode only the pixels needed by the UI, without retaining the full-size source.
enum ImageThumbnail {
    static func make(data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }
        return make(source: source, maxPixel: maxPixel)
    }

    static func make(url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }
        return make(source: source, maxPixel: maxPixel)
    }

    private static func make(source: CGImageSource, maxPixel: Int) -> NSImage? {
        guard maxPixel > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    static func decodedCost(_ image: NSImage) -> Int {
        image.representations.reduce(0) { cost, rep in
            cost + max(rep.pixelsWide, 0) * max(rep.pixelsHigh, 0) * 4
        }
    }
}

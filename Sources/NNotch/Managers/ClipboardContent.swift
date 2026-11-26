import AppKit
import CryptoKit
import ImageIO

struct ClipboardItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text, link, file, image
    }

    let id: UUID
    let date: Date
    let kind: Kind
    /// Text content, link URL string, or file path depending on `kind`.
    let value: String
    /// Stable key used for de-duplication.
    let contentKey: String

    var fileURL: URL? {
        kind == .file ? URL(fileURLWithPath: value) : nil
    }
}

enum ClipboardContent {
    static func key(kind: ClipboardItem.Kind, value: String) -> String {
        switch kind {
        case .text, .link:
            return kind.rawValue + ":sha256:" + digest(Data(value.utf8))
        case .file:
            return "file:" + value
        case .image:
            return value
        }
    }

    static func migrated(_ item: ClipboardItem) -> ClipboardItem {
        guard item.kind == .text || item.kind == .link else { return item }
        return ClipboardItem(id: item.id, date: item.date, kind: item.kind, value: item.value,
                             contentKey: key(kind: item.kind, value: item.value))
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Preserve existing PNG bytes. TIFF conversion runs on the capture worker.
    static func pngData(from data: Data, isPNG: Bool) -> Data? {
        if isPNG {
            guard let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false
            ] as CFDictionary),
                  CGImageSourceGetType(source) as String? == "public.png",
                  CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil else { return nil }
            return data
        }
        return NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
    }
}

/// One conversion at a time bounds peak memory. Epochs invalidate results after
/// clear/remove/disable/recopy, without allowing a stale completion to reinsert data.
struct ClipboardCaptureState {
    private(set) var generation = 0
    private(set) var isProcessing = false

    mutating func begin() -> Int? {
        guard !isProcessing else { return nil }
        isProcessing = true
        return generation
    }

    mutating func invalidate() { generation &+= 1 }

    mutating func finish(_ token: Int) -> Bool {
        isProcessing = false
        return token == generation
    }
}

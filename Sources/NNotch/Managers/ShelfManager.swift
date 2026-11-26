import AppKit
import Combine
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let fileName: String
    /// Path of our private copy inside Application Support — survives moves of the original.
    let storedPath: String

    var storedURL: URL { URL(fileURLWithPath: storedPath) }
}

/// Temporary file shelf: drop files onto the notch to park them,
/// drag them back out (or AirDrop them) whenever needed.
@MainActor
final class ShelfManager: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    @Published var selectedIDs: Set<UUID> = []
    var selectedItems: [ShelfItem] { items.filter { selectedIDs.contains($0.id) } }

    func toggleSelection(_ item: ShelfItem) {
        if !selectedIDs.insert(item.id).inserted { selectedIDs.remove(item.id) }
    }

    private let shelfDir = Persistence.directory("Shelf")
    private let ioQueue = DispatchQueue(label: "nnotch.shelf.io", qos: .userInitiated)
    private var clearGeneration = 0

    init() {
        let saved = Persistence.load([ShelfItem].self, from: "shelf.json") ?? []
        // Drop entries whose backing file disappeared.
        items = saved.filter { FileManager.default.fileExists(atPath: $0.storedPath) }
        if items.count != saved.count { persist() }
    }

    // MARK: - Adding

    func add(fileURL: URL) {
        let id = UUID()
        let fileName = fileURL.lastPathComponent
        let itemDir = shelfDir.appendingPathComponent(id.uuidString, isDirectory: true)
        let target = itemDir.appendingPathComponent(fileName)
        let gen = clearGeneration

        ioQueue.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: fileURL, to: target)
            } catch {
                NSLog("Shelf copy failed: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: itemDir)
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.clearGeneration == gen else {
                    self.ioQueue.async { try? FileManager.default.removeItem(at: itemDir) }
                    return
                }
                self.items.insert(
                    ShelfItem(id: id, date: Date(), fileName: fileName, storedPath: target.path),
                    at: 0
                )
                self.persist()
            }
        }
    }

    func add(imageData: Data, suggestedName: String = "Imagen") {
        let id = UUID()
        let fileName = "\(suggestedName)-\(shortStamp()).png"
        let itemDir = shelfDir.appendingPathComponent(id.uuidString, isDirectory: true)
        let target = itemDir.appendingPathComponent(fileName)
        let gen = clearGeneration

        ioQueue.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
                try imageData.write(to: target, options: .atomic)
            } catch {
                try? FileManager.default.removeItem(at: itemDir)
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.clearGeneration == gen else {
                    self.ioQueue.async { try? FileManager.default.removeItem(at: itemDir) }
                    return
                }
                self.items.insert(
                    ShelfItem(id: id, date: Date(), fileName: fileName, storedPath: target.path),
                    at: 0
                )
                self.persist()
            }
        }
    }

    func add(text: String) {
        let id = UUID()
        let fileName = "Nota-\(shortStamp()).txt"
        let itemDir = shelfDir.appendingPathComponent(id.uuidString, isDirectory: true)
        let target = itemDir.appendingPathComponent(fileName)
        let gen = clearGeneration

        ioQueue.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
                try text.write(to: target, atomically: true, encoding: .utf8)
            } catch {
                try? FileManager.default.removeItem(at: itemDir)
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.clearGeneration == gen else {
                    self.ioQueue.async { try? FileManager.default.removeItem(at: itemDir) }
                    return
                }
                self.items.insert(
                    ShelfItem(id: id, date: Date(), fileName: fileName, storedPath: target.path),
                    at: 0
                )
                self.persist()
            }
        }
    }

    /// Entry point for drops coming from SwiftUI `onDrop` providers.
    func handle(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    // Kaynak uygulamaya göre öğe Data (bookmark) ya da NSURL gelebilir.
                    let url: URL?
                    if let direct = item as? URL {
                        url = direct
                    } else if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = nil
                    }
                    guard let url else { return }
                    Task { @MainActor in self.add(fileURL: url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data,
                          let rep = NSBitmapImageRep(data: data),
                          let png = rep.representation(using: .png, properties: [:]) else { return }
                    Task { @MainActor in self.add(imageData: png) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    var text: String?
                    if let s = item as? String { text = s }
                    else if let d = item as? Data { text = String(data: d, encoding: .utf8) }
                    guard let text, !text.isEmpty else { return }
                    Task { @MainActor in self.add(text: text) }
                }
            }
        }
        return handled
    }

    // MARK: - Actions

    func airDrop(_ item: ShelfItem) {
        airDrop(urls: [item.storedURL])
    }

    func airDropAll() {
        airDrop(urls: items.map(\.storedURL))
    }

    func airDrop(urls: [URL]) {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.storedURL])
    }

    func remove(_ item: ShelfItem) {
        selectedIDs.remove(item.id)
        items.removeAll { $0.id == item.id }
        let dir = item.storedURL.deletingLastPathComponent()
        ioQueue.async { try? FileManager.default.removeItem(at: dir) }
        persist()
    }

    func removeAll() {
        clearGeneration += 1
        let dirs = items.map { $0.storedURL.deletingLastPathComponent() }
        selectedIDs.removeAll()
        items.removeAll()
        persist()
        guard !dirs.isEmpty else { return }
        ioQueue.async {
            for dir in dirs {
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }

    /// Clears the shelf UI/state immediately while deferring on-disk deletion of the backing
    /// copies so destination apps like Finder finish copying without error -8072.
    func clearAfterExternalDrop(cleanupDelay: TimeInterval = 15) {
        clearGeneration += 1
        let dirs = items.map { $0.storedURL.deletingLastPathComponent() }
        selectedIDs.removeAll()
        items.removeAll()
        persist()
        guard !dirs.isEmpty else { return }
        ioQueue.asyncAfter(deadline: .now() + cleanupDelay) {
            for dir in dirs {
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }

    func icon(for item: ShelfItem) -> NSImage {
        NSWorkspace.shared.icon(forFile: item.storedPath)
    }

    private func shortStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        return formatter.string(from: Date())
    }

    private func persist() {
        Persistence.save(items, to: "shelf.json")
    }
}

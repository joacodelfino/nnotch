import AppKit
import Combine
import UniformTypeIdentifiers

struct AppShortcut: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var path: String
}

/// Lanzadores rápidos de aplicaciones con soporte limpio de alta y baja directa.
@MainActor
final class AppShortcutsStore: ObservableObject {
    @Published var shortcuts: [AppShortcut] = [] { didSet { persist() } }

    private var offlineShortcuts: [AppShortcut] = []
    private var loading = true

    init() {
        let saved = Persistence.load([AppShortcut].self, from: "shortcuts.json") ?? []
        offlineShortcuts = saved.filter { !FileManager.default.fileExists(atPath: $0.path) }
        shortcuts = saved.filter { FileManager.default.fileExists(atPath: $0.path) }
        loading = false
    }

    func icon(for shortcut: AppShortcut) -> NSImage {
        NSWorkspace.shared.icon(forFile: shortcut.path)
    }

    func launch(_ shortcut: AppShortcut) {
        let url = URL(fileURLWithPath: shortcut.path)
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    func addViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Elegir aplicación"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            add(url: url)
        }
    }

    func add(url: URL) {
        let standardized = url.standardizedFileURL.path
        guard standardized.hasSuffix(".app"),
              !shortcuts.contains(where: { $0.path == standardized }),
              !offlineShortcuts.contains(where: { $0.path == standardized }) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        shortcuts.append(AppShortcut(id: UUID(), name: name, path: standardized))
    }

    func remove(_ shortcut: AppShortcut) {
        offlineShortcuts.removeAll { $0.id == shortcut.id || $0.path == shortcut.path }
        shortcuts.removeAll { $0.id == shortcut.id || $0.path == shortcut.path }
    }

    func removeAll() {
        offlineShortcuts.removeAll()
        shortcuts.removeAll()
    }

    private func persist() {
        guard !loading else { return }
        Persistence.save(shortcuts + offlineShortcuts, to: "shortcuts.json")
    }
}

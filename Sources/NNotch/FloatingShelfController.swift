import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FloatingShelfController {
    private let shelf: ShelfManager
    private var panel: NSPanel?
    private var detector = DragShakeDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var triggered = false
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount

    init(shelf: ShelfManager) {
        self.shelf = shelf
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        panel?.orderOut(nil)
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .leftMouseDragged else {
            detector.reset()
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            triggered = false
            return
        }
        guard !triggered, Preferences.shared.isTabEnabled(.shelf),
              NSPasteboard(name: .drag).changeCount != dragChangeCount,
              NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        if detector.sample(x: NSEvent.mouseLocation.x, time: event.timestamp) {
            triggered = true
            show()
        }
    }

    func show() {
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
                                 styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "Bandeja flotante"
            window.isFloatingPanel = true
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: FloatingShelfView().environmentObject(shelf))
            panel = window
        }
        guard let panel else { return }
        let point = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            var frame = panel.frame
            frame.origin.x = min(max(point.x + 24, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
            frame.origin.y = min(max(point.y - frame.height / 2, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }
}

private struct FloatingShelfView: View {
    @EnvironmentObject var shelf: ShelfManager
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            Label(targeted ? "Soltá los archivos acá" : "Bandeja · \(shelf.items.count)", systemImage: "tray.and.arrow.down")
                .font(.headline)
            if shelf.items.isEmpty {
                Spacer()
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 36))
                Text("Soltá archivos y después arrastralos a otra app")
                    .font(.callout).multilineTextAlignment(.center)
                Spacer()
            } else {
                ShelfSelectionBar()
                ConfirmingButton(title: "Vaciar bandeja", systemImage: "trash") { shelf.removeAll() }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(shelf.items) { ShelfItemView(item: $0) }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? Color.orange.opacity(0.2) : Color.black.opacity(0.15))
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { shelf.handle(providers: $0) }
    }
}

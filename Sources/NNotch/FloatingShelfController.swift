import Combine
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FloatingShelfController {
    private let shelf: ShelfManager
    private var panel: NSPanel?
    private var itemsObserver: AnyCancellable?
    private var detector = DragShakeDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var triggered = false
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var itemCountAtDragStart = 0
    private var dismissWork: DispatchWorkItem?

    init(shelf: ShelfManager) {
        self.shelf = shelf
        itemsObserver = shelf.$items.map { $0.isEmpty }.removeDuplicates()
            .dropFirst().sink { [weak self] empty in
                if empty { self?.panel?.orderOut(nil) }
            }
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
            if event.type == .leftMouseDown {
                dismissWork?.cancel()
                itemCountAtDragStart = shelf.items.count
            } else if event.type == .leftMouseUp, triggered, itemCountAtDragStart == 0, shelf.items.isEmpty {
                let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
                dismissWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
            }
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
        dismissWork?.cancel()
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isFloatingPanel = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.appearance = NSAppearance(named: .darkAqua)
            let hosting = NSHostingView(rootView: FloatingShelfView().environmentObject(shelf))
            hosting.wantsLayer = true
            hosting.layer?.cornerRadius = 22
            hosting.layer?.masksToBounds = true
            window.contentView = hosting
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
        VStack(spacing: 8) {
            if shelf.items.isEmpty {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    ConfirmingButton(title: "Vaciar", systemImage: "trash") { shelf.removeAll() }
                        .fixedSize()
                        .padding(4)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    Spacer()
                }
                .padding(.horizontal, 8)
                SelectableShelfGrid(columnCount: 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(targeted ? Color.orange.opacity(0.2) : Color.black.opacity(0.82))
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { shelf.handle(providers: $0) }
    }
}

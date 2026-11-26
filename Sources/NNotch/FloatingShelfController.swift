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
        itemsObserver = shelf.$items.dropFirst().sink { [weak self] items in
            guard let self else { return }
            if items.isEmpty {
                self.panel?.orderOut(nil)
            } else {
                self.dismissWork?.cancel()
                self.dismissWork = nil
            }
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

    func hide() {
        dismissWork?.cancel()
        dismissWork = nil
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
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
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 176, height: 196),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isFloatingPanel = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.appearance = NSAppearance(named: .darkAqua)
            let hosting = NSHostingView(
                rootView: FloatingShelfView(onClose: { [weak self] in self?.hide() })
                    .environmentObject(shelf)
            )
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
    let onClose: () -> Void
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            topDragBar
            if shelf.items.isEmpty {
                emptyState
            } else {
                DropoverStackView(items: shelf.items) {
                    shelf.removeAll()
                    onClose()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                clearBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(targeted ? Color.orange.opacity(0.24) : Color.black.opacity(0.84))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            targeted ? Color.orange.opacity(0.8) : Color.white.opacity(0.14),
                            lineWidth: targeted ? 1.5 : 1
                        )
                )
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier, UTType.plainText.identifier], isTargeted: $targeted) {
            shelf.handle(providers: $0)
        }
    }

    private var topDragBar: some View {
        ZStack {
            WindowDragHandle()
                .frame(maxWidth: .infinity)
                .frame(height: 24)
            Capsule()
                .fill(Color.white.opacity(hovering ? 0.28 : 0.14))
                .frame(width: 32, height: 3.5)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            if hovering && shelf.items.isEmpty {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .accessibilityLabel("Cerrar bandeja flotante")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 32))
                .foregroundStyle(targeted ? Color.orange : Color.white.opacity(0.65))
            Text("Soltá archivos acá")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clearBar: some View {
        HStack {
            Button {
                shelf.removeAll()
                onClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Vaciar")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Vaciar bandeja y cerrar")
        }
        .padding(.bottom, 10)
    }
}

/// Invisible AppKit view that initiates a native window drag when clicked and dragged.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView { DragHandleNSView() }
    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}

    final class DragHandleNSView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Dropover-style stacked pile of icons with count badge; dragging the stack drags all files
/// at once and clears/closes the floating shelf once dropped outside.
private struct DropoverStackView: View {
    @EnvironmentObject var shelf: ShelfManager
    let items: [ShelfItem]
    let onDragCompleted: () -> Void

    private var previewItems: [ShelfItem] {
        Array(items.prefix(3))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                ZStack {
                    ForEach(Array(previewItems.enumerated().reversed()), id: \.element.id) { index, item in
                        let angle = stackAngle(for: index, total: previewItems.count)
                        let offsetX = CGFloat(index) * 3.5 - CGFloat(previewItems.count - 1) * 1.75
                        let offsetY = -CGFloat(index) * 3.0
                        Image(nsImage: shelf.icon(for: item))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 58, height: 58)
                            .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                            .rotationEffect(.degrees(angle))
                            .offset(x: offsetX, y: offsetY)
                    }
                }
                .frame(width: 78, height: 74)
                .overlay(alignment: .topTrailing) {
                    Text("\(items.count)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .offset(x: 4, y: -2)
                }

                Text(items.count == 1 ? "1 archivo" : "\(items.count) archivos")
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }
            .allowsHitTesting(false)

            StackDragSource(
                urls: items.map(\.storedURL),
                onDropSucceeded: onDragCompleted
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .help("Arrastrá para llevar todos los archivos y cerrar")
    }

    private func stackAngle(for index: Int, total: Int) -> Double {
        guard total > 1 else { return 0 }
        switch index {
        case 0: return 0
        case 1: return -7
        default: return 8
        }
    }
}

/// Transparent AppKit drag source that drags all parked file URLs in one session
/// and invokes `onDropSucceeded` when the destination accepts the drop.
private struct StackDragSource: NSViewRepresentable {
    let urls: [URL]
    let onDropSucceeded: () -> Void

    func makeNSView(context: Context) -> StackDragNSView { StackDragNSView() }

    func updateNSView(_ view: StackDragNSView, context: Context) {
        view.urls = urls
        view.onDropSucceeded = onDropSucceeded
    }

    final class StackDragNSView: NSView, NSDraggingSource {
        var urls: [URL] = []
        var onDropSucceeded: (() -> Void)?
        private var mouseDownEvent: NSEvent?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
        }

        override func mouseDragged(with event: NSEvent) {
            guard !urls.isEmpty else { return }
            let startEvent = mouseDownEvent ?? event
            mouseDownEvent = nil
            let point = convert(event.locationInWindow, from: nil)
            let items: [NSDraggingItem] = urls.enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let shift = CGFloat(min(index, 4)) * 4
                let frame = NSRect(x: point.x - 24 + shift, y: point.y - 24 - shift, width: 48, height: 48)
                item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: url.path))
                return item
            }
            let session = beginDraggingSession(with: items, event: startEvent, source: self)
            session.draggingFormation = .pile
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : .copy
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            guard operation != [] else { return }
            Task { @MainActor [onDropSucceeded] in
                onDropSucceeded?()
            }
        }
    }
}

import AppKit
import SwiftUI

struct ShelfSelectionBar: View {
    @EnvironmentObject private var shelf: ShelfManager

    var body: some View {
        HStack(spacing: 8) {
            Button(shelf.selectedIDs.count == shelf.items.count ? "Deseleccionar" : "Seleccionar todos") {
                shelf.selectedIDs = shelf.selectedIDs.count == shelf.items.count ? [] : Set(shelf.items.map(\.id))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.orange)
            .font(.caption2)
            Spacer(minLength: 0)
            if !shelf.selectedItems.isEmpty {
                if shelf.selectedItems.count > 1 {
                    ShelfBatchDrag(urls: shelf.selectedItems.map(\.storedURL))
                        .frame(width: 110, height: 24)
                        .help("Arrastrá desde acá para llevar todos los seleccionados")
                }
                ConfirmingButton(title: "Quitar", systemImage: "trash") {
                    for item in shelf.selectedItems { shelf.remove(item) }
                }
            }
        }
    }
}

/// One pasteboard item per file so Finder and other apps receive the entire selection.
private struct ShelfBatchDrag: NSViewRepresentable {
    let urls: [URL]
    func makeNSView(context: Context) -> BatchDragView { BatchDragView() }
    func updateNSView(_ view: BatchDragView, context: Context) { view.urls = urls; view.needsDisplay = true }

    final class BatchDragView: NSView, NSDraggingSource {
        var urls: [URL] = []
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}
        override func draw(_ dirtyRect: NSRect) {
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
            let text = "Arrastrar \(urls.count)" as NSString
            text.draw(at: NSPoint(x: 8, y: 5), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        }
        override func mouseDragged(with event: NSEvent) {
            guard !urls.isEmpty else { return }
            let point = convert(event.locationInWindow, from: nil)
            let items = urls.enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                item.setDraggingFrame(NSRect(x: point.x + CGFloat(index % 4) * 5, y: point.y, width: 40, height: 40), contents: NSWorkspace.shared.icon(forFile: url.path))
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    }
}

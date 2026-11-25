import AppKit
import SwiftUI

private struct ShelfFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct SelectableShelfGrid: View {
    @EnvironmentObject private var shelf: ShelfManager
    let columnCount: Int
    var keyboardDelete = false
    @State private var frames: [UUID: CGRect] = [:]
    @State private var selectionRect: CGRect?
    @State private var initialSelection: Set<UUID> = []
    @State private var selecting = false
    @State private var ignored = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount), spacing: 10) {
                ForEach(shelf.items) { item in
                    ShelfItemView(item: item)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: ShelfFramesKey.self,
                                value: [item.id: geometry.frame(in: .named("shelfSelection"))])
                        })
                }
            }
            .padding(8)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                if let rect = selectionRect {
                    Rectangle().fill(Color.accentColor.opacity(0.18))
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "shelfSelection")
            .onPreferenceChange(ShelfFramesKey.self) { frames = $0 }
            .background {
                if keyboardDelete {
                    ShelfDeleteKeyHandler {
                        for item in shelf.selectedItems { shelf.remove(item) }
                    }
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("shelfSelection"))
                .onChanged { value in
                    if !selecting && !ignored {
                        ignored = frames.values.contains { $0.contains(value.startLocation) }
                        guard !ignored else { return }
                        selecting = true
                        initialSelection = NSEvent.modifierFlags.contains(.command) ? shelf.selectedIDs : []
                    }
                    guard selecting else { return }
                    let rect = CGRect(x: min(value.startLocation.x, value.location.x),
                                      y: min(value.startLocation.y, value.location.y),
                                      width: abs(value.location.x - value.startLocation.x),
                                      height: abs(value.location.y - value.startLocation.y))
                    selectionRect = rect
                    shelf.selectedIDs = initialSelection.union(frames.compactMap { rect.intersects($0.value) ? $0.key : nil })
                }
                .onEnded { _ in
                    selecting = false
                    ignored = false
                    selectionRect = nil
                })
        }
    }
}

private struct ShelfDeleteKeyHandler: NSViewRepresentable {
    let onDelete: () -> Void
    func makeNSView(context: Context) -> NSView { DeleteKeyView(onDelete: onDelete) }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? DeleteKeyView)?.onDelete = onDelete
    }

    private final class DeleteKeyView: NSView {
        var onDelete: () -> Void
        init(onDelete: @escaping () -> Void) { self.onDelete = onDelete; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 51 || event.keyCode == 117 { onDelete() }
            else { super.keyDown(with: event) }
        }
    }
}

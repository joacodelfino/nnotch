import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            IslandView()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

/// The black island itself: notch-sized when collapsed, a full panel when expanded.
struct IslandView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var shelf: ShelfManager
    @EnvironmentObject private var prefs: Preferences

    private var shape: NotchShape {
        NotchShape(bottomRadius: vm.isExpanded ? prefs.expandedCornerRadius : 12)
    }

    private var islandWidth: CGFloat {
        vm.isExpanded ? vm.expandedSize.width : vm.collapsedPillSize.width
    }

    private var islandHeight: CGFloat {
        vm.isExpanded ? vm.expandedSize.height : vm.collapsedPillSize.height
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .overlay(
                    shape.strokeBorder(
                        Color.white.opacity(vm.isExpanded ? 0.16 : 0),
                        lineWidth: 1
                    )
                )
            // Keep the drop destination mounted while the silhouette animates.
            // Removing it mid-drag can interrupt SwiftUI's drag session.
            ExpandedView()
                .frame(width: vm.expandedSize.width, height: vm.expandedSize.height)
                .frame(width: islandWidth, height: islandHeight, alignment: .top)
                .opacity(vm.isExpanded && vm.isContentVisible ? 1 : 0)
                .allowsHitTesting(vm.isExpanded && vm.isContentVisible)
                .accessibilityHidden(!vm.isExpanded || !vm.isContentVisible)
                .animation(nil, value: vm.isContentVisible)
            CollapsedView()
                .frame(width: vm.collapsedPillSize.width, height: vm.collapsedPillSize.height)
                .frame(width: islandWidth, height: islandHeight, alignment: .top)
                .opacity(vm.isExpanded ? 0 : 1)
                .allowsHitTesting(!vm.isExpanded)
                .accessibilityHidden(vm.isExpanded)

        }
        .frame(width: islandWidth, height: islandHeight)
        .clipShape(shape)
        .shadow(color: .black.opacity(vm.isExpanded ? 0.5 : 0),
                radius: vm.isExpanded ? 16 : 0, y: vm.isExpanded ? 5 : 0)
        .contentShape(shape)
        // Hover, SwiftUI `.onHover` ile DEĞİL (accessory app'te başka uygulama
        // önplandayken event vermiyor); NotchHostingView'daki .activeAlways
        // NSTrackingArea ile algılanıyor. Bkz NotchWindow.swift.
        .onTapGesture {
            vm.expand()
        }
        .onDrop(
            of: [UTType.fileURL, UTType.image, UTType.plainText],
            delegate: IslandDropDelegate(vm: vm, shelf: shelf)
        )
        // Animasyon VM'de imperatif olarak sürülür: expand → expandSpring,
        // collapse → collapseSpring. Burada ikinci bir .animation eklemek ikisini
        // çakıştırıp kapanışı da expandSpring'e zorluyordu (asimetri kaynağı).
    }
}

/// Dragging anything over the notch opens the shelf; dropping parks it there.
struct IslandDropDelegate: DropDelegate {
    let vm: NotchViewModel
    let shelf: ShelfManager

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            vm.isDragHovering = true
            vm.expand(tab: .shelf)
        }
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated {
            vm.isDragHovering = false
            // Sürükleme sırasında mouseMoved gelmez; imleç adayı sürüklemeyle
            // terk ettiği için içeride-sayma bayrağını elle düşür.
            vm.isMouseInside = false
            vm.collapse(afterDelay: Preferences.shared.collapseDelay)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL, UTType.image, UTType.plainText])
        return MainActor.assumeIsolated {
            vm.isDragHovering = false
            vm.expand(tab: .shelf)
            return shelf.handle(providers: providers)
        }
    }
}

/// Notch silhouette: flush with the screen's top edge, rounded bottom corners.
struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    var inset: CGFloat = 0

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

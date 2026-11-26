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

/// Inline alert strip seamlessly extending the right side of the collapsed notch.
private struct NotchInlineRightAlert: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var reminders: ReminderStore

    var body: some View {
        if let alert = vm.notchAlerts.first {
            let accent = Color(hex: alert.colorHex)
            let extraCount = max(vm.notchAlerts.count - 1, 0)
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: 14)

                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)

                Text(alert.stage == .upcoming15m ? "15m" : "Ahora")
                    .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(accent)

                Text(alert.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }

                if let url = alert.meetingURL {
                    Button {
                        NSWorkspace.shared.open(url)
                        dismiss(alert)
                    } label: {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.cyan)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.cyan.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .help("Unirse a la reunión")
                }

                Button {
                    dismiss(alert)
                } label: {
                    Image(systemName: alert.isSticky ? "checkmark" : "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(alert.isSticky ? accent.opacity(0.85) : Color.white.opacity(0.16)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(alert.isSticky ? "Listo / Sacar aviso" : "Cerrar aviso")
                .accessibilityLabel("Cerrar aviso")
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(width: NotchViewModel.rightAlertExtensionWidth, height: vm.collapsedPillSize.height)
            .contentShape(Rectangle())
        }
    }

    private func dismiss(_ alert: NotchAlertItem) {
        if let remID = alert.reminderID, alert.isSticky {
            reminders.markCompleted(remID)
        }
        vm.dismissNotchAlert(id: alert.id)
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
        vm.isExpanded ? vm.expandedSize.width : (vm.collapsedPillSize.width + vm.activeRightAlertExtension)
    }

    private var islandHeight: CGFloat {
        vm.isExpanded ? vm.expandedSize.height : vm.collapsedPillSize.height
    }

    /// Shift half of the right alert extension to the right so the physical notch stays perfectly centered.
    private var horizontalOffset: CGFloat {
        vm.isExpanded ? 0 : (vm.activeRightAlertExtension / 2)
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
            // Only mount ExpandedView while the island is expanded (or dragging over it)
            // so SwiftUI does not retain offscreen tab hierarchies & backing stores while idle.
            if vm.isExpanded || vm.isDragHovering {
                ExpandedView()
                    .frame(width: vm.expandedSize.width, height: vm.expandedSize.height)
                    .frame(width: islandWidth, height: islandHeight, alignment: .top)
                    .opacity(vm.isExpanded && vm.isContentVisible ? 1 : 0)
                    .allowsHitTesting(vm.isExpanded && vm.isContentVisible)
                    .accessibilityHidden(!vm.isExpanded || !vm.isContentVisible)
                    .animation(nil, value: vm.isContentVisible)
            }
            HStack(spacing: 0) {
                CollapsedView()
                    .frame(width: vm.collapsedPillSize.width, height: vm.collapsedPillSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.expand()
                    }
                if vm.hasRightAlert {
                    NotchInlineRightAlert()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
            .opacity(vm.isExpanded ? 0 : 1)
            .allowsHitTesting(!vm.isExpanded)
            .accessibilityHidden(vm.isExpanded)

        }
        .frame(width: islandWidth, height: islandHeight)
        .clipShape(shape)
        .shadow(color: .black.opacity(vm.isExpanded ? 0.5 : 0),
                radius: vm.isExpanded ? 16 : 0, y: vm.isExpanded ? 5 : 0)
        .contentShape(shape)
        .offset(x: horizontalOffset)
        .animation(Motion.standard, value: vm.activeRightAlertExtension)
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

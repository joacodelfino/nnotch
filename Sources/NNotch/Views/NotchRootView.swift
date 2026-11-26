import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @EnvironmentObject private var vm: NotchViewModel

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                IslandView()
                Spacer(minLength: 0)
            }
            if vm.hasRightAlert {
                NotchRightAlertStack()
                    .frame(width: NotchViewModel.rightAlertWidth)
                    .offset(
                        x: (vm.collapsedPillSize.width / 2) + NotchViewModel.rightAlertGap + (NotchViewModel.rightAlertWidth / 2),
                        y: 4
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

/// Compact notification cards anchored directly to the right side of the collapsed notch.
private struct NotchRightAlertStack: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var reminders: ReminderStore

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(vm.notchAlerts.prefix(3))) { alert in
                NotchRightAlertCard(alert: alert) {
                    if let remID = alert.reminderID, alert.isSticky {
                        reminders.markCompleted(remID)
                    }
                    vm.dismissNotchAlert(id: alert.id)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NotchRightAlertCard: View {
    let alert: NotchAlertItem
    let onDismiss: () -> Void

    private var accent: Color { Color(hex: alert.colorHex) }

    private var badgeText: String {
        switch alert.stage {
        case .upcoming15m:
            return "En 15 min · \(alert.scheduledDate.formatted(date: .omitted, time: .shortened))"
        case .dueNow:
            return "Ahora · \(alert.scheduledDate.formatted(date: .omitted, time: .shortened))"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: alert.isSticky ? "bell.badge.fill" : "clock.badge.exclamationmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(accent)
                    Text(badgeText)
                        .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
                Text(alert.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Button(action: onDismiss) {
                    Image(systemName: alert.isSticky ? "checkmark" : "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(alert.isSticky ? accent.opacity(0.85) : Color.white.opacity(0.14)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(alert.isSticky ? "Listo / Sacar aviso" : "Cerrar aviso")
                .accessibilityLabel("Cerrar aviso")

                if let url = alert.meetingURL {
                    Button {
                        NSWorkspace.shared.open(url)
                        onDismiss()
                    } label: {
                        Image(systemName: "video.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.cyan)
                            .frame(width: 20, height: 18)
                            .background(Capsule().fill(Color.cyan.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .help("Unirse a la reunión")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(alert.isSticky ? accent.opacity(0.65) : Color.white.opacity(0.16), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
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

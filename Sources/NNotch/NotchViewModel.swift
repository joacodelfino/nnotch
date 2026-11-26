import AppKit
import Combine
import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable {
    case home, shelf, clipboard, tools, calendar, reminders, notes, settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .tools: return "timer"
        case .calendar: return "calendar"
        case .reminders: return "bell.badge.fill"
        case .notes: return "note.text"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .shelf: return "Bandeja"
        case .clipboard: return "Portapapeles"
        case .tools: return "Herramientas"
        case .calendar: return "Calendario"
        case .reminders: return "Recordatorios"
        case .notes: return "Notas"
        case .settings: return "Ajustes"
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    /// Controla la visibilidad del contenido interno por separado de la silueta negra:
    /// al cerrar, el contenido desaparece de inmediato para que no deje estela/fantasma
    /// (ej. miniatura de YouTube) mientras la silueta negra se contrae con su animación suave.
    @Published var isContentVisible = false
    @Published var activeTab: IslandTab = .home
    @Published private(set) var calendarAlerts: [CalendarEventItem] = []
    @Published private(set) var notchAlerts: [NotchAlertItem] = []
    private var alertDismissWork: DispatchWorkItem?
    private var preAlertDismissWorks: [String: DispatchWorkItem] = [:]
    private var expandedForAlert = false
    @Published var isDragHovering = false
    @Published var collapsedSize = CGSize(width: 196, height: 32)

    /// Extra width added to the RIGHT side of the collapsed notch when an alert is active.
    static let rightAlertExtensionWidth: CGFloat = 232

    var hasRightAlert: Bool { !notchAlerts.isEmpty && !isExpanded }

    var activeRightAlertExtension: CGFloat {
        hasRightAlert ? Self.rightAlertExtensionWidth : 0
    }

    /// Set while the pointer sits inside the island so we can delay collapse.
    /// Hiçbir view okumadığı için yayınlanmaz (her mouse hareketinde
    /// objectWillChange tetiklememek için düz property).
    var isMouseInside = false

    var expandedSize: CGSize { Preferences.shared.expandedPanelSize }

    /// Kapalı moddaki görünür pill: çentik + iki yandaki içerik bölgeleri.
    /// Pencere, çizim ve hover tetikleme bölgesi hep bu boyuttan türetilir.
    var collapsedPillSize: CGSize {
        CGSize(width: collapsedSize.width + 156, height: collapsedSize.height)
    }

    private var collapseWorkItem: DispatchWorkItem?

    func showNotchAlerts(_ items: [NotchAlertItem]) {
        guard !items.isEmpty else { return }
        var addedSticky = false
        var addedPre = false

        withAnimation(Motion.standard) {
            for item in items {
                // If an event/reminder upgrades from 15m pre-alert to dueNow, replace the old entry.
                if let remID = item.reminderID {
                    notchAlerts.removeAll { $0.reminderID == remID }
                }
                notchAlerts.removeAll { $0.id == item.id }
                notchAlerts.insert(item, at: 0)

                preAlertDismissWorks[item.id]?.cancel()
                preAlertDismissWorks.removeValue(forKey: item.id)

                if item.isSticky {
                    addedSticky = true
                } else {
                    addedPre = true
                    let alertID = item.id
                    let work = DispatchWorkItem { [weak self] in
                        self?.dismissNotchAlert(id: alertID)
                    }
                    preAlertDismissWorks[alertID] = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 14, execute: work)
                }
            }
        }

        if addedSticky {
            NSSound(named: "Glass")?.play()
            Preferences.shared.performHaptic(.levelChange)
        } else if addedPre {
            NSSound(named: "Pop")?.play()
            Preferences.shared.performHaptic(.generic)
        }
    }

    func dismissNotchAlert(id: String) {
        preAlertDismissWorks[id]?.cancel()
        preAlertDismissWorks.removeValue(forKey: id)
        withAnimation(Motion.quick) {
            notchAlerts.removeAll { $0.id == id }
        }
    }

    func dismissAllNotchAlerts() {
        for work in preAlertDismissWorks.values { work.cancel() }
        preAlertDismissWorks.removeAll()
        withAnimation(Motion.quick) {
            notchAlerts = []
        }
    }

    func showCalendarAlerts(_ events: [CalendarEventItem]) {
        let items = events.map { ev in
            NotchAlertItem(
                id: "cal-due-\(ev.id)",
                title: ev.title,
                scheduledDate: ev.startDate,
                stage: .dueNow,
                colorHex: ev.colorHex,
                sourceLabel: ev.sourceLabel,
                meetingURL: ev.meetingURL,
                reminderID: nil
            )
        }
        showNotchAlerts(items)
    }

    func showUpcomingCalendarAlerts(_ events: [CalendarEventItem]) {
        let items = events.map { ev in
            NotchAlertItem(
                id: "cal-15m-\(ev.id)",
                title: ev.title,
                scheduledDate: ev.startDate,
                stage: .upcoming15m,
                colorHex: ev.colorHex,
                sourceLabel: ev.sourceLabel,
                meetingURL: ev.meetingURL,
                reminderID: nil
            )
        }
        showNotchAlerts(items)
    }

    func dismissCalendarAlerts(keepOpen: Bool = false) {
        alertDismissWork?.cancel()
        alertDismissWork = nil
        calendarAlerts = []
        let shouldCollapse = expandedForAlert && !keepOpen
        expandedForAlert = false
        if shouldCollapse { collapse() }
    }

    func refreshGeometry() {
        if let screen = ScreenGeometry.targetScreen {
            let size = screen.islandSize
            // Değer aynıysa yayınlama; @Published eşitlik kontrolü yapmadığından
            // gereksiz objectWillChange ve yeniden çizimleri burada eliyoruz.
            if size != collapsedSize { collapsedSize = size }
        }
    }

    func expand(tab: IslandTab? = nil) {
        collapseWorkItem?.cancel()
        if let tab { activeTab = tab }
        if !Preferences.shared.isTabEnabled(activeTab) {
            activeTab = .home
        }
        guard !isExpanded else {
            isContentVisible = true
            return
        }
        Preferences.shared.performHaptic()
        withAnimation(Preferences.shared.expandSpring) {
            isExpanded = true
            isContentVisible = true
        }
    }

    func collapse(afterDelay delay: TimeInterval = 0) {
        collapseWorkItem?.cancel()
        guard isExpanded else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isMouseInside, !self.isDragHovering, self.calendarAlerts.isEmpty else { return }
            self.performSmoothCollapse()
        }
        if delay <= 0 {
            collapseWorkItem = nil
            work.perform()
        } else {
            collapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func collapseNow() {
        dismissCalendarAlerts(keepOpen: true)
        collapseWorkItem?.cancel()
        isMouseInside = false
        isDragHovering = false
        performSmoothCollapse()
    }

    private func performSmoothCollapse() {
        // Ocultamos el contenido expandido de inmediato para que no se vea la miniatura
        // de YouTube ni los textos deformándose dentro de la estela negra que se contrae.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isContentVisible = false
        }
        withAnimation(Preferences.shared.collapseSpring) {
            isExpanded = false
        }
    }
}

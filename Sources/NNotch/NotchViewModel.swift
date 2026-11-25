import AppKit
import Combine
import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable {
    case home, shelf, clipboard, tools, calendar, notes, settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .tools: return "timer"
        case .calendar: return "calendar"
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
    private var alertDismissWork: DispatchWorkItem?
    private var expandedForAlert = false
    @Published var isDragHovering = false
    @Published var collapsedSize = CGSize(width: 196, height: 32)

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

    func showCalendarAlerts(_ events: [CalendarEventItem]) {
        guard !events.isEmpty else { return }
        if calendarAlerts.isEmpty { expandedForAlert = !isExpanded }
        calendarAlerts.append(contentsOf: events.filter { event in !calendarAlerts.contains(where: { $0.id == event.id }) })
        expand()
        alertDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissCalendarAlerts() }
        alertDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
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

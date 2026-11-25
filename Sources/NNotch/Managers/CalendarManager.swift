import AppKit
import Combine
import EventKit
import SwiftUI
import os

enum CalendarProvider: String, CaseIterable, Identifiable, Codable {
    case all = "all"
    case mac = "mac"
    case google = "google"
    case custom = "custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .mac: return "Mac"
        case .google: return "Google"
        case .custom: return "Otro (.ics)"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "tray.2.fill"
        case .mac: return "apple.logo"
        case .google: return "globe"
        case .custom: return "link"
        }
    }
}

struct ExternalCalendarFeed: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var urlString: String
    var provider: CalendarProvider // .google or .custom
    var colorHex: String
    var isEnabled: Bool = true
}

struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let colorHex: String
    let sourceLabel: String
    let provider: CalendarProvider
    let meetingURL: URL?
}

struct MacCalendarSourceInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let accountName: String
    let colorHex: String
    let isGoogleAccount: Bool
}

/// Gestor multi-calendario: soporta Calendario de Mac (EventKit), Google Calendar
/// (cuentas Google sincronizadas en macOS + feeds iCal .ics directos) y otros calendarios (.ics / Outlook / Notion).
@MainActor
final class CalendarManager: ObservableObject {
    enum Access {
        case unknown, granted, denied
    }

    @Published private(set) var eventAccess: Access = .unknown
    @Published private(set) var reminderAccess: Access = .unknown
    @Published private(set) var macCalendars: [MacCalendarSourceInfo] = []
    @Published private(set) var allEvents: [CalendarEventItem] = []
    @Published private(set) var openReminders: [EKReminder] = []
    @Published private(set) var isSyncingExternal = false
    @Published private(set) var externalError: String?

    @Published var selectedProvider: CalendarProvider {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "calendar.selectedProvider")
        }
    }

    @Published var disabledMacCalendarIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(disabledMacCalendarIDs).joined(separator: ","), forKey: "calendar.disabledMacIDs")
            refresh()
        }
    }

    @Published var externalFeeds: [ExternalCalendarFeed] = [] {
        didSet {
            guard !loading else { return }
            Persistence.save(externalFeeds, to: "calendar_feeds.json")
            refreshExternalFeeds()
        }
    }

    private var cachedExternalEvents: [CalendarEventItem] = []
    private let store = EKEventStore()
    private var loading = true
    private let log = Logger(subsystem: "com.joacodelfino.nnotch", category: "Calendar")

    init() {
        let savedProvider = UserDefaults.standard.string(forKey: "calendar.selectedProvider") ?? ""
        selectedProvider = CalendarProvider(rawValue: savedProvider) ?? .all

        if let rawDisabled = UserDefaults.standard.string(forKey: "calendar.disabledMacIDs"), !rawDisabled.isEmpty {
            disabledMacCalendarIDs = Set(rawDisabled.split(separator: ",").map(String.init))
        } else {
            disabledMacCalendarIDs = []
        }

        externalFeeds = Persistence.load([ExternalCalendarFeed].self, from: "calendar_feeds.json") ?? []
        loading = false

        updateAccessFromSystem()
        if eventAccess == .granted || reminderAccess == .granted {
            refresh()
        } else if !externalFeeds.isEmpty {
            refreshExternalFeeds()
        }
    }

    /// Eventos filtrados según el origen elegido en la barra superior de Calendario.
    var filteredEvents: [CalendarEventItem] {
        switch selectedProvider {
        case .all:
            return allEvents
        case .mac:
            return allEvents.filter { $0.provider == .mac }
        case .google:
            return allEvents.filter { $0.provider == .google }
        case .custom:
            return allEvents.filter { $0.provider == .custom }
        }
    }

    var hasGoogleSourceConfigured: Bool {
        macCalendars.contains(where: { $0.isGoogleAccount })
            || externalFeeds.contains(where: { $0.provider == .google && $0.isEnabled })
    }

    var hasCustomSourceConfigured: Bool {
        externalFeeds.contains(where: { $0.provider == .custom && $0.isEnabled })
    }

    func isMacCalendarEnabled(_ id: String) -> Bool {
        !disabledMacCalendarIDs.contains(id)
    }

    func toggleMacCalendar(_ id: String) {
        if disabledMacCalendarIDs.contains(id) {
            disabledMacCalendarIDs.remove(id)
        } else {
            disabledMacCalendarIDs.insert(id)
        }
    }

    func addExternalFeed(name: String, urlString: String, provider: CalendarProvider) {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("webcal://") {
            cleaned = "https://" + cleaned.dropFirst("webcal://".count)
        }
        guard !cleaned.isEmpty, URL(string: cleaned) != nil else {
            externalError = "La URL del calendario (.ics) no es válida."
            return
        }
        externalError = nil
        let defaultName = provider == .google ? "Google Calendar" : "Calendario Externo"
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultName : name
        let color = provider == .google ? "#0A84FF" : "#BF5AF2"
        externalFeeds.append(
            ExternalCalendarFeed(
                id: UUID(),
                name: finalName,
                urlString: cleaned,
                provider: provider,
                colorHex: color,
                isEnabled: true
            )
        )
    }

    func removeExternalFeed(_ feed: ExternalCalendarFeed) {
        externalFeeds.removeAll { $0.id == feed.id }
    }

    func toggleExternalFeed(_ feed: ExternalCalendarFeed) {
        guard let idx = externalFeeds.firstIndex(where: { $0.id == feed.id }) else { return }
        externalFeeds[idx].isEnabled.toggle()
    }

    func openExternalCalendarApp() {
        switch selectedProvider {
        case .google:
            if let url = URL(string: "https://calendar.google.com") {
                NSWorkspace.shared.open(url)
            }
        case .mac, .all:
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
            }
        case .custom:
            if let outlookURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Outlook") {
                NSWorkspace.shared.openApplication(at: outlookURL, configuration: .init(), completionHandler: nil)
            } else if let url = URL(string: "https://calendar.google.com") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - EventKit Access

    private func updateAccessFromSystem() {
        eventAccess = Self.access(for: .event)
        reminderAccess = Self.access(for: .reminder)
    }

    private static func access(for entity: EKEntityType) -> Access {
        let status = EKEventStore.authorizationStatus(for: entity)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess: return .granted
            case .notDetermined: return .unknown
            default: return .denied
            }
        } else {
            switch status {
            case .authorized: return .granted
            case .notDetermined: return .unknown
            default: return .denied
            }
        }
    }

    func requestAccessAndRefresh() {
        requestEventAccess { [weak self] in
            self?.requestReminderAccess {
                self?.refresh()
            }
        }
    }

    private func requestEventAccess(completion: @escaping () -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                Task { @MainActor in
                    self?.eventAccess = granted ? .granted : .denied
                    completion()
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.eventAccess = granted ? .granted : .denied
                    completion()
                }
            }
        }
    }

    private func requestReminderAccess(completion: @escaping () -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders { [weak self] granted, _ in
                Task { @MainActor in
                    self?.reminderAccess = granted ? .granted : .denied
                    completion()
                }
            }
        } else {
            store.requestAccess(to: .reminder) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.reminderAccess = granted ? .granted : .denied
                    completion()
                }
            }
        }
    }

    // MARK: - Refresh & Merge

    func refresh() {
        rebuildMacEvents()
        refreshExternalFeeds()
        if reminderAccess == .granted {
            let predicate = store.predicateForReminders(in: nil)
            store.fetchReminders(matching: predicate) { [weak self] reminders in
                let open = (reminders ?? [])
                    .filter { !$0.isCompleted }
                    .sorted { a, b in
                        let dateA = a.dueDateComponents?.date ?? .distantFuture
                        let dateB = b.dueDateComponents?.date ?? .distantFuture
                        return dateA < dateB
                    }
                Task { @MainActor in
                    self?.openReminders = Array(open.prefix(20))
                }
            }
        }
    }

    private var cachedMacEvents: [CalendarEventItem] = []

    private func rebuildMacEvents() {
        guard eventAccess == .granted else {
            macCalendars = []
            cachedMacEvents = []
            mergeAllEvents()
            return
        }

        let ekCalendars = store.calendars(for: .event)
        macCalendars = ekCalendars.map { cal in
            let sourceTitle = cal.source?.title ?? "Mac"
            let isGoogle = sourceTitle.localizedCaseInsensitiveContains("google")
                || sourceTitle.localizedCaseInsensitiveContains("gmail")
                || cal.title.localizedCaseInsensitiveContains("@gmail.com")
            let hex = cal.cgColor.flatMap { Color(cgColor: $0).hexString } ?? (isGoogle ? "#0A84FF" : "#FF375F")
            return MacCalendarSourceInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                accountName: sourceTitle,
                colorHex: hex,
                isGoogleAccount: isGoogle
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let activeCalendars = ekCalendars.filter { !disabledMacCalendarIDs.contains($0.calendarIdentifier) }
        guard !activeCalendars.isEmpty else {
            cachedMacEvents = []
            mergeAllEvents()
            return
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 14, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: activeCalendars)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay || $0.endDate >= start }
            .sorted { $0.startDate < $1.startDate }

        cachedMacEvents = events.prefix(40).map { ev in
            let cal = ev.calendar as EKCalendar?
            let sourceTitle = cal?.source?.title ?? "Mac"
            let calTitle = cal?.title ?? "Mac"
            let isGoogle = sourceTitle.localizedCaseInsensitiveContains("google")
                || sourceTitle.localizedCaseInsensitiveContains("gmail")
                || calTitle.localizedCaseInsensitiveContains("@gmail.com")
            let hex = cal?.cgColor.flatMap { Color(cgColor: $0).hexString } ?? (isGoogle ? "#0A84FF" : "#FF375F")
            let provider: CalendarProvider = isGoogle ? .google : .mac
            let meeting = Self.extractMeetingURL(from: [ev.url?.absoluteString, ev.location, ev.notes])
            return CalendarEventItem(
                id: "\(ev.eventIdentifier ?? UUID().uuidString)-\(ev.startDate.timeIntervalSince1970)",
                title: ev.title ?? "Evento",
                startDate: ev.startDate,
                endDate: ev.endDate,
                isAllDay: ev.isAllDay,
                colorHex: hex,
                sourceLabel: isGoogle ? "Google · \(calTitle)" : calTitle,
                provider: provider,
                meetingURL: meeting
            )
        }
        mergeAllEvents()
    }

    func refreshExternalFeeds() {
        let activeFeeds = externalFeeds.filter(\.isEnabled)
        guard !activeFeeds.isEmpty else {
            cachedExternalEvents = []
            mergeAllEvents()
            return
        }

        isSyncingExternal = true
        externalError = nil
        Task {
            var collected: [CalendarEventItem] = []
            var firstError: String?
            for feed in activeFeeds {
                guard let url = URL(string: feed.urlString) else { continue }
                do {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 8
                    let (data, _) = try await URLSession.shared.data(for: req)
                    if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                        let parsed = Self.parseICS(text: text, feed: feed)
                        collected.append(contentsOf: parsed)
                    }
                } catch {
                    firstError = "No se pudo sincronizar \(feed.name)"
                }
            }
            self.cachedExternalEvents = collected
            self.isSyncingExternal = false
            self.externalError = firstError
            self.mergeAllEvents()
        }
    }

    private func mergeAllEvents() {
        let combined = (cachedMacEvents + cachedExternalEvents)
            .sorted { $0.startDate < $1.startDate }
        allEvents = Array(combined.prefix(50))
    }

    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            openReminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
        } catch {
            reminder.isCompleted = false
            log.error("Recordatorio no completado: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Meeting Link & ICS Parser

    nonisolated private static func extractMeetingURL(from texts: [String?]) -> URL? {
        let pattern = #"https://(?:meet\.google\.com/[a-z0-9\-]+|[a-z0-9\-]+\.zoom\.us/j/[^\s"<>]+|teams\.microsoft\.com/l/meetup-join/[^\s"<>]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        for raw in texts.compactMap({ $0 }) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            if let match = regex.firstMatch(in: raw, options: [], range: range),
               let swiftRange = Range(match.range, in: raw),
               let url = URL(string: String(raw[swiftRange])) {
                return url
            }
        }
        return nil
    }

    nonisolated private static func parseICS(text: String, feed: ExternalCalendarFeed) -> [CalendarEventItem] {
        // Desplegar líneas plegadas RFC 5545 (CRLF + espacio/tab)
        let unfolded = text
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")

        let lines = unfolded.components(separatedBy: .newlines)
        let cal = Calendar.current
        let windowStart = cal.startOfDay(for: Date())
        let windowEnd = cal.date(byAdding: .day, value: 14, to: windowStart) ?? windowStart

        var results: [CalendarEventItem] = []
        var inEvent = false
        var uid = ""
        var summary = ""
        var location = ""
        var description = ""
        var urlStr = ""
        var dtStart: Date?
        var dtEnd: Date?
        var isAllDay = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "BEGIN:VEVENT" {
                inEvent = true
                uid = UUID().uuidString
                summary = ""
                location = ""
                description = ""
                urlStr = ""
                dtStart = nil
                dtEnd = nil
                isAllDay = false
                continue
            }
            if trimmed == "END:VEVENT" {
                if inEvent, let start = dtStart {
                    let end = dtEnd ?? start.addingTimeInterval(isAllDay ? 86400 : 3600)
                    if end >= windowStart && start <= windowEnd {
                        let meeting = extractMeetingURL(from: [urlStr, location, description])
                        results.append(
                            CalendarEventItem(
                                id: "\(feed.id.uuidString)-\(uid)-\(start.timeIntervalSince1970)",
                                title: summary.isEmpty ? "Evento" : unescapeICS(summary),
                                startDate: start,
                                endDate: end,
                                isAllDay: isAllDay,
                                colorHex: feed.colorHex,
                                sourceLabel: feed.name,
                                provider: feed.provider,
                                meetingURL: meeting
                            )
                        )
                    }
                }
                inEvent = false
                continue
            }
            guard inEvent, let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let keyPart = String(trimmed[..<colonIdx]).uppercased()
            let valuePart = String(trimmed[trimmed.index(after: colonIdx)...])
            let baseKey = keyPart.split(separator: ";").first.map(String.init) ?? keyPart

            switch baseKey {
            case "UID":
                uid = valuePart
            case "SUMMARY":
                summary = valuePart
            case "LOCATION":
                location = valuePart
            case "DESCRIPTION":
                description = valuePart
            case "URL":
                urlStr = valuePart
            case "DTSTART":
                let parsed = parseICSDate(valuePart, keyParams: keyPart)
                dtStart = parsed.date
                if parsed.isAllDay { isAllDay = true }
            case "DTEND":
                dtEnd = parseICSDate(valuePart, keyParams: keyPart).date
            default:
                break
            }
        }
        return results
    }

    nonisolated private static func parseICSDate(_ raw: String, keyParams: String) -> (date: Date?, isAllDay: Bool) {
        let val = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyParams.contains("VALUE=DATE") || val.count == 8 {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyyMMdd"
            return (df.date(from: String(val.prefix(8))), true)
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        if val.hasSuffix("Z") {
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            if let d = df.date(from: val) { return (d, false) }
        }
        df.timeZone = .current
        df.dateFormat = "yyyyMMdd'T'HHmmss"
        let clean = val.replacingOccurrences(of: "Z", with: "")
        return (df.date(from: String(clean.prefix(15))), false)
    }

    nonisolated private static func unescapeICS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
    }
}

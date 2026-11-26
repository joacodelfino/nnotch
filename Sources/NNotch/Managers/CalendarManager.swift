import AppKit
import Combine
import EventKit
import SwiftUI

/// Gestor multi-calendario: soporta Calendario de Mac (EventKit), Google Calendar
/// (cuentas Google sincronizadas en macOS + feeds iCal .ics directos) y otros calendarios (.ics / Outlook / Notion).
@MainActor
final class CalendarManager: ObservableObject {
    enum Access {
        case unknown, granted, denied
    }

    @Published private(set) var eventAccess: Access = .unknown
    @Published private(set) var macCalendars: [MacCalendarSourceInfo] = []
    @Published private(set) var allEvents: [CalendarEventItem] = []
    @Published private(set) var isSyncingExternal = false
    @Published private(set) var externalError: String?
    var hasGoogleAccountOnMac: Bool { macCalendars.contains(where: \.isGoogleAccount) }

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

    @Published private(set) var displayedMonth = CalendarLayout.monthStart(Date())
    @Published var selectedDate = CalendarLayout.calendar.startOfDay(for: Date())
    @Published var alertsEnabled = UserDefaults.standard.object(forKey: "calendar.alertsEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(alertsEnabled, forKey: "calendar.alertsEnabled")
            scheduleNextWake()
        }
    }
    var onEventsStarting: (([CalendarEventItem]) -> Void)? {
        didSet { scheduleNextWake() }
    }
    private var alertLedger = CalendarAlertLedger(
        delivered: UserDefaults.standard.dictionary(forKey: "calendar.deliveredAlerts") as? [String: Double] ?? [:]
    )
    private var timer: Timer?
    private var moduleObserver: AnyCancellable?
    private var moduleEnabled = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var nextRefresh = Date.distantPast
    private var externalTask: Task<Void, Never>?

    func showMonth(offset: Int) {
        guard let month = CalendarLayout.calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        selectDay(month)
    }

    func selectDay(_ date: Date) {
        selectedDate = date
        let month = CalendarLayout.monthStart(date)
        if month != displayedMonth {
            displayedMonth = month
            refresh()
        }
    }

    func showToday() { selectDay(CalendarLayout.calendar.startOfDay(for: Date())) }

    private var eventIntervals: [DateInterval] {
        let today = CalendarLayout.calendar.startOfDay(for: Date())
        let tomorrow = CalendarLayout.calendar.date(byAdding: .day, value: 2, to: today)!
        return CalendarLayout.mergedIntervals([CalendarLayout.interval(for: displayedMonth), DateInterval(start: today, end: tomorrow)])
    }

    private func checkEventAlerts() {
        guard alertsEnabled, moduleEnabled, onEventsStarting != nil else { return }
        let due = alertLedger.takeDue(events: allEvents, now: Date())
        guard !due.isEmpty else { return }
        UserDefaults.standard.set(alertLedger.delivered, forKey: "calendar.deliveredAlerts")
        onEventsStarting?(due)
    }

    private var cachedExternalEvents: [CalendarEventItem] = []
    private let store = EKEventStore()
    private var loading = true

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

        observe(.EKEventStoreChanged, object: store) { [weak self] in self?.rebuildMacEvents() }
        observe(NSApplication.didBecomeActiveNotification) { [weak self] in self?.refresh() }
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.refresh()
        }
        observe(.NSSystemClockDidChange) { [weak self] in self?.refresh() }
        observe(.NSSystemTimeZoneDidChange) { [weak self] in self?.refresh() }

        moduleObserver = Preferences.shared.$enabledTabs
            .map { $0.contains(IslandTab.calendar.rawValue) }
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.moduleEnabled = enabled
                if enabled {
                    self.refresh()
                } else {
                    self.timer?.invalidate()
                    self.timer = nil
                    self.externalTask?.cancel()
                    self.externalTask = nil
                    self.isSyncingExternal = false
                }
            }
    }

    deinit {
        timer?.invalidate()
        externalTask?.cancel()
        for (center, token) in observers { center.removeObserver(token) }
    }

    private func observe(_ name: Notification.Name, object: Any? = nil,
                         center: NotificationCenter = .default, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { _ in
            Task { @MainActor in action() }
        }
        observers.append((center, token))
    }

    private func scheduleNextWake() {
        timer?.invalidate()
        timer = nil
        guard moduleEnabled else { return }
        let now = Date()
        let fireDate = alertLedger.nextWake(events: allEvents, now: now, refresh: nextRefresh,
                                           alertsEnabled: alertsEnabled && onEventsStarting != nil)
        let timer = Timer(fire: max(fireDate, now.addingTimeInterval(0.01)), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.wake() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func wake() {
        guard moduleEnabled else { return }
        // Deliver cached events before potentially slow EventKit refresh work.
        checkEventAlerts()
        if Date() >= nextRefresh { refresh() }
        scheduleNextWake()
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
        hasGoogleAccountOnMac
            || externalFeeds.contains(where: { $0.provider == .google && $0.isEnabled })
    }

    func openMacInternetAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
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
        let access = Self.access(for: .event)
        if eventAccess != access { eventAccess = access }
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

    func requestCalendarAccessAndRefresh() {
        requestEventAccess { [weak self] in self?.refresh() }
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

    // MARK: - Refresh & Merge

    func refresh() {
        guard moduleEnabled else { return }
        defer { scheduleNextWake() }
        nextRefresh = Date().addingTimeInterval(60)
        updateAccessFromSystem()
        rebuildMacEvents()
        refreshExternalFeeds()
    }

    private var cachedMacEvents: [CalendarEventItem] = []

    private func rebuildMacEvents() {
        guard moduleEnabled else { return }
        guard eventAccess == .granted else {
            if !macCalendars.isEmpty { macCalendars = [] }
            cachedMacEvents = []
            mergeAllEvents()
            return
        }

        let ekCalendars = store.calendars(for: .event)
        let calendars = ekCalendars.map { cal in
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

        if macCalendars != calendars { macCalendars = calendars }

        let activeCalendars = ekCalendars.filter { !disabledMacCalendarIDs.contains($0.calendarIdentifier) }
        guard !activeCalendars.isEmpty else {
            cachedMacEvents = []
            mergeAllEvents()
            return
        }

        let events = eventIntervals.flatMap { interval in
            let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: activeCalendars)
            return store.events(matching: predicate)
        }.sorted { $0.startDate < $1.startDate }

        cachedMacEvents = events.map { ev in
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
        externalTask?.cancel()
        guard moduleEnabled else { return }
        let activeFeeds = externalFeeds.filter(\.isEnabled)
        guard !activeFeeds.isEmpty else {
            cachedExternalEvents = []
            isSyncingExternal = false
            mergeAllEvents()
            return
        }

        isSyncingExternal = true
        externalError = nil
        let intervals = eventIntervals
        externalTask = Task {
            var collected: [CalendarEventItem] = []
            var firstError: String?
            for feed in activeFeeds {
                guard !Task.isCancelled else { return }
                guard let url = URL(string: feed.urlString) else { continue }
                do {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 8
                    let (data, _) = try await URLSession.shared.data(for: req)
                    if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                        let parsed = await Task.detached(priority: .utility) {
                            intervals.flatMap { Self.parseICS(text: text, feed: feed, window: $0) }
                        }.value
                        guard !Task.isCancelled else { return }
                        collected.append(contentsOf: parsed)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    firstError = "No se pudo sincronizar \(feed.name)"
                }
            }
            guard !Task.isCancelled else { return }
            self.cachedExternalEvents = collected
            self.isSyncingExternal = false
            self.externalError = firstError
            self.mergeAllEvents()
        }
    }

    private func mergeAllEvents() {
        var seenKeys = Set<String>()
        var deduped: [CalendarEventItem] = []
        let all = (cachedMacEvents + cachedExternalEvents)
            .sorted { $0.startDate < $1.startDate }

        for item in all {
            let dedupKey = "\(item.id)|\(item.startDate.timeIntervalSince1970)"
            if seenKeys.insert(dedupKey).inserted {
                deduped.append(item)
            }
        }
        if allEvents != deduped { allEvents = deduped }
        scheduleNextWake()
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

    nonisolated static func parseICS(text: String, feed: ExternalCalendarFeed, window: DateInterval? = nil) -> [CalendarEventItem] {
        // Desplegar líneas plegadas RFC 5545 (CRLF + espacio/tab)
        let unfolded = text
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")

        let lines = unfolded.components(separatedBy: .newlines)
        let cal = Calendar.current
        let windowStart = window?.start ?? cal.startOfDay(for: Date())
        let windowEnd = window?.end ?? cal.date(byAdding: .day, value: 14, to: windowStart)!

        var results: [CalendarEventItem] = []
        var inEvent = false
        var uid = ""
        var summary = ""
        var location = ""
        var description = ""
        var urlStr = ""
        var rrule = ""
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
                rrule = ""
                dtStart = nil
                dtEnd = nil
                isAllDay = false
                continue
            }
            if trimmed == "END:VEVENT" {
                if inEvent, let start = dtStart {
                    let duration = max((dtEnd ?? start.addingTimeInterval(isAllDay ? 86400 : 3600)).timeIntervalSince(start), 0)
                    let occurrences = expandOccurrences(start: start, duration: duration, rrule: rrule, windowStart: windowStart, windowEnd: windowEnd)
                    let cleanTitle = summary.isEmpty ? "Evento" : unescapeICS(summary)
                    let meeting = extractMeetingURL(from: [urlStr, location, description])
                    for occStart in occurrences {
                        let occEnd = occStart.addingTimeInterval(duration)
                        results.append(
                            CalendarEventItem(
                                id: "\(feed.id.uuidString)-\(uid)-\(occStart.timeIntervalSince1970)",
                                title: cleanTitle,
                                startDate: occStart,
                                endDate: occEnd,
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
            case "RRULE":
                rrule = valuePart.uppercased()
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

    nonisolated private static func expandOccurrences(
        start: Date,
        duration: TimeInterval,
        rrule: String,
        windowStart: Date,
        windowEnd: Date
    ) -> [Date] {
        let end = start.addingTimeInterval(duration)
        if rrule.isEmpty {
            return (end >= windowStart && start <= windowEnd) ? [start] : []
        }

        var params: [String: String] = [:]
        for part in rrule.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[String(kv[0])] = String(kv[1])
            }
        }
        if let untilStr = params["UNTIL"],
           let untilDate = parseICSDate(untilStr, keyParams: "").date,
           untilDate < windowStart {
            return []
        }

        let cal = Calendar.current
        let freq = params["FREQ"] ?? ""
        var dates: [Date] = []

        if freq == "DAILY" {
            let interval = max(Int(params["INTERVAL"] ?? "1") ?? 1, 1)
            var current = start
            var guardCount = 0
            while current <= windowEnd && guardCount < 1500 {
                if current.addingTimeInterval(duration) >= windowStart {
                    dates.append(current)
                }
                guard let next = cal.date(byAdding: .day, value: interval, to: current) else { break }
                current = next
                guardCount += 1
            }
        } else if freq == "WEEKLY" {
            let timeComps = cal.dateComponents([.hour, .minute, .second], from: start)
            let dayMap: [String: Int] = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
            if let byDayRaw = params["BYDAY"] {
                let targetWeekdays = Set(byDayRaw.split(separator: ",").compactMap { dayMap[String($0.suffix(2))] })
                for offset in 0...(cal.dateComponents([.day], from: windowStart, to: windowEnd).day ?? 42) {
                    guard let dayDate = cal.date(byAdding: .day, value: offset, to: windowStart) else { continue }
                    let wd = cal.component(.weekday, from: dayDate)
                    if targetWeekdays.contains(wd),
                       let candidate = cal.date(
                           bySettingHour: timeComps.hour ?? 0,
                           minute: timeComps.minute ?? 0,
                           second: timeComps.second ?? 0,
                           of: dayDate
                       ),
                       candidate >= start,
                       candidate <= windowEnd {
                        dates.append(candidate)
                    }
                }
            } else {
                let interval = max(Int(params["INTERVAL"] ?? "1") ?? 1, 1)
                var current = start
                var guardCount = 0
                while current <= windowEnd && guardCount < 600 {
                    if current.addingTimeInterval(duration) >= windowStart {
                        dates.append(current)
                    }
                    guard let next = cal.date(byAdding: .weekOfYear, value: interval, to: current) else { break }
                    current = next
                    guardCount += 1
                }
            }
        } else if end >= windowStart && start <= windowEnd {
            dates.append(start)
        }
        return dates
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

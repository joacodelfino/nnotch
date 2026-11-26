import Foundation

enum CalendarLayout {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }

    static func monthStart(_ date: Date, calendar: Calendar = calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    static func days(in month: Date, calendar: Calendar = calendar) -> [Date] {
        let first = monthStart(month, calendar: calendar)
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: first)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    static func interval(for month: Date) -> DateInterval {
        let days = days(in: month)
        return DateInterval(start: days[0], end: calendar.date(byAdding: .day, value: 1, to: days[41])!)
    }

    /// Avoid querying/parsing the same dates twice when the month includes today.
    static func mergedIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    static func occurs(_ event: CalendarEventItem, on day: Date, calendar: Calendar = calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        // EventKit's all-day end is exclusive. Zero-length events belong to their start day.
        return event.startDate < end && (event.endDate > start ||
            (event.endDate == event.startDate && event.startDate >= start))
    }
}

/// Pure scheduling logic, independent of timers and the UI.
struct CalendarAlertLedger {
    static let leadTime: TimeInterval = 15 * 60
    var delivered: [String: Double] = [:]

    /// Next useful wakeup: an undelivered event (start time or optional 15m pre-alert) or the periodic refresh.
    func nextWake(events: [CalendarEventItem], now: Date, refresh: Date, alertsEnabled: Bool, includePreAlerts: Bool = false) -> Date {
        guard alertsEnabled else { return max(now, refresh) }
        var candidates: [Date] = []
        for event in events {
            guard !event.isAllDay, event.endDate >= now else { continue }
            let dueKey = "\(event.id)|\(event.startDate.timeIntervalSince1970)"
            if event.startDate > now.addingTimeInterval(-60), delivered[dueKey] == nil {
                candidates.append(event.startDate)
            }
            if includePreAlerts {
                let preTime = event.startDate.addingTimeInterval(-Self.leadTime)
                let preKey = "pre15|\(event.id)|\(event.startDate.timeIntervalSince1970)"
                if preTime > now.addingTimeInterval(-60), event.startDate > now, delivered[preKey] == nil {
                    candidates.append(preTime)
                }
            }
        }
        return max(now, min(refresh, candidates.min() ?? refresh))
    }

    mutating func takeDue(events: [CalendarEventItem], now: Date) -> [CalendarEventItem] {
        delivered = delivered.filter { $0.value > now.addingTimeInterval(-172_800).timeIntervalSince1970 }
        var due: [CalendarEventItem] = []
        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            let key = "\(event.id)|\(event.startDate.timeIntervalSince1970)"
            guard !event.isAllDay,
                  event.startDate <= now,
                  event.startDate > now.addingTimeInterval(-60),
                  event.endDate >= now,
                  delivered[key] == nil else { continue }
            delivered[key] = event.startDate.timeIntervalSince1970
            due.append(event)
        }
        return due
    }

    mutating func takeUpcoming15m(events: [CalendarEventItem], now: Date) -> [CalendarEventItem] {
        delivered = delivered.filter { $0.value > now.addingTimeInterval(-172_800).timeIntervalSince1970 }
        var upcoming: [CalendarEventItem] = []
        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            let preTime = event.startDate.addingTimeInterval(-Self.leadTime)
            let key = "pre15|\(event.id)|\(event.startDate.timeIntervalSince1970)"
            guard !event.isAllDay,
                  preTime <= now,
                  preTime > now.addingTimeInterval(-60),
                  event.startDate > now,
                  delivered[key] == nil else { continue }
            delivered[key] = event.startDate.timeIntervalSince1970
            upcoming.append(event)
        }
        return upcoming
    }
}

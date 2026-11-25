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
    var delivered: [String: Double] = [:]

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
}

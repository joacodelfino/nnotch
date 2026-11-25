import Foundation

@main
struct CalendarLogicTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        let leapDays = CalendarLayout.days(in: date(2024, 2, 10), calendar: calendar)
        check(leapDays.count == 42, "Always six complete weeks")
        check(calendar.component(.weekday, from: leapDays[0]) == 2, "Monday first")
        check(leapDays.filter { calendar.component(.month, from: $0) == 2 }.count == 29, "Leap February")
        let march = CalendarLayout.days(in: date(2024, 3, 1), calendar: calendar)
        check(Set(march).count == 42, "DST does not duplicate days")
        check(march.contains(date(2024, 3, 10)) && march.contains(date(2024, 3, 11)), "DST boundary preserved")
        let rollover = CalendarLayout.days(in: date(2026, 12, 1), calendar: calendar)
        check(calendar.component(.year, from: rollover.last!) == 2027, "Year boundary")

        func event(_ id: String, start: Date, end: Date, allDay: Bool = false) -> CalendarEventItem {
            CalendarEventItem(id: id, title: "Meeting", startDate: start, endDate: end,
                              isAllDay: allDay, colorHex: "#0A84FF", sourceLabel: "Tests",
                              provider: .google, meetingURL: nil)
        }
        let overnight = event("overnight", start: date(2024, 3, 9, 23), end: date(2024, 3, 11))
        check(CalendarLayout.occurs(overnight, on: date(2024, 3, 10), calendar: calendar), "Overnight event")
        check(!CalendarLayout.occurs(overnight, on: date(2024, 3, 11), calendar: calendar), "Exclusive midnight end")
        let allDay = event("all-day", start: date(2024, 3, 10), end: date(2024, 3, 11), allDay: true)
        check(CalendarLayout.occurs(allDay, on: date(2024, 3, 10), calendar: calendar), "All-day on DST day")
        check(!CalendarLayout.occurs(allDay, on: date(2024, 3, 11), calendar: calendar), "All-day exclusive end")

        let now = date(2026, 11, 25, 10)
        let one = event("one", start: now, end: now.addingTimeInterval(3600))
        let two = event("two", start: now, end: now.addingTimeInterval(3600))
        let future = event("future", start: now.addingTimeInterval(30), end: now.addingTimeInterval(3600))
        let old = event("old", start: now.addingTimeInterval(-61), end: now.addingTimeInterval(3600))
        let ended = event("ended", start: now.addingTimeInterval(-30), end: now.addingTimeInterval(-1))
        let untimed = event("untimed", start: now, end: now.addingTimeInterval(86400), allDay: true)
        var ledger = CalendarAlertLedger()
        let due = ledger.takeDue(events: [one, two, future, old, ended, untimed, one], now: now)
        check(Set(due.map(\.id)) == ["one", "two"], "Simultaneous events, no future/old/all-day/duplicates")
        check(ledger.takeDue(events: [one, two], now: now.addingTimeInterval(1)).isEmpty, "No repeat on tick")
        var restored = CalendarAlertLedger(delivered: ledger.delivered)
        check(restored.takeDue(events: [one, two], now: now.addingTimeInterval(2)).isEmpty, "No repeat after restart")
        check(restored.takeDue(events: [future], now: now.addingTimeInterval(30)).count == 1, "Alert at scheduled time")
        let moved = event("one", start: now.addingTimeInterval(60), end: now.addingTimeInterval(3600))
        check(restored.takeDue(events: [moved], now: now.addingTimeInterval(60)).count == 1, "Rescheduled event alerts again")
        print("Calendar checks passed: month grid, DST, overlapping dates and alert scheduling.")
    }
}

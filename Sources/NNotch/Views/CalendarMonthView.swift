import SwiftUI

struct CalendarMonthView: View {
    @EnvironmentObject private var calendar: CalendarManager
    @EnvironmentObject private var prefs: Preferences
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private let weekdays = ["L", "M", "X", "J", "V", "S", "D"]

    private var dayEvents: [CalendarEventItem] {
        calendar.events(on: calendar.selectedDate)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    monthHeader
                    HStack(spacing: 3) {
                        ForEach(Array(weekdays.enumerated()), id: \.offset) { index, name in
                            Text(name)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(index > 4 ? 0.3 : 0.55))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(CalendarLayout.days(in: calendar.displayedMonth), id: \.self) { day in
                            dayCell(day)
                                .frame(height: max(24, (geometry.size.height - 70) / 6))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width * 0.54)

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(calendar.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_UY"))))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("\(dayEvents.count) eventos · \(calendar.selectedProvider.title)")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    if let error = calendar.externalError {
                        Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2).help(error)
                    }
                    if dayEvents.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.checkmark").font(.system(size: 25))
                            Text("Sin eventos este día").font(.caption)
                        }
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 7) {
                                ForEach(dayEvents) { event in
                                    CalendarEventRow(event: event)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 6) {
            Text(calendar.displayedMonth.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "es_UY"))).capitalized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button("Hoy") { calendar.showToday() }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(prefs.accentColor)
            Button { calendar.showMonth(offset: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 22, height: 24)
            }
            .accessibilityLabel("Mes anterior")
            Button { calendar.showMonth(offset: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 22, height: 24)
            }
            .accessibilityLabel("Mes siguiente")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.7))
        .frame(height: 26)
    }

    private func dayCell(_ date: Date) -> some View {
        let cal = CalendarLayout.calendar
        let selected = cal.isDate(date, inSameDayAs: calendar.selectedDate)
        let today = cal.isDateInToday(date)
        let inMonth = cal.isDate(date, equalTo: calendar.displayedMonth, toGranularity: .month)
        let events = calendar.events(on: date)
        return Button { calendar.selectDay(date) } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 11, weight: selected || today ? .bold : .medium))
                    .foregroundStyle(selected ? .black : (today ? prefs.accentColor : .white.opacity(inMonth ? 0.85 : 0.25)))
                HStack(spacing: 2) {
                    ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, event in
                        Circle().fill(selected ? Color.black.opacity(0.65) : Color(hex: event.colorHex))
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? prefs.accentColor : .white.opacity(today ? 0.08 : 0.025)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(events.count) eventos")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CalendarEventRow: View {
    let event: CalendarEventItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: event.colorHex)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(3)
                Text(event.isAllDay ? "Todo el día" : "\(event.startDate.formatted(date: .omitted, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.65))
                Text(event.sourceLabel).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                if let url = event.meetingURL {
                    Button("Unirse", systemImage: "video.fill") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.plain).font(.caption2).foregroundStyle(.cyan)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
        .help(event.title)
    }
}

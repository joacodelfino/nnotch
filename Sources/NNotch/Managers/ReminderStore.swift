import AppKit
import Combine
import Foundation

struct ReminderItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var scheduledDate: Date
    var isCompleted: Bool = false
    var notified15m: Bool = false
    var notifiedDue: Bool = false
}

enum NotchAlertStage: Equatable {
    /// Fires 15 minutes before the scheduled time and auto-dismisses after a few seconds.
    case upcoming15m
    /// Fires at the exact scheduled time and stays visible until the user dismisses it.
    case dueNow
}

struct NotchAlertItem: Identifiable, Equatable {
    let id: String
    let title: String
    let scheduledDate: Date
    let stage: NotchAlertStage
    let colorHex: String
    let sourceLabel: String
    let meetingURL: URL?
    let reminderID: UUID?

    var isSticky: Bool { stage == .dueNow }
}

/// Manages user-created reminders with 2-stage scheduling (15 min before + at scheduled time)
/// using a single non-repeating Timer so there are zero idle wakeups.
@MainActor
final class ReminderStore: ObservableObject {
    static let leadTime: TimeInterval = 15 * 60

    @Published private(set) var reminders: [ReminderItem] = []

    var onAlertsTriggered: (([NotchAlertItem]) -> Void)? {
        didSet { scheduleNextWake() }
    }

    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        reminders = Persistence.load([ReminderItem].self, from: "reminders.json") ?? []
        sortReminders()
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.checkAndSchedule()
        }
        observe(.NSSystemClockDidChange) { [weak self] in self?.checkAndSchedule() }
        observe(.NSSystemTimeZoneDidChange) { [weak self] in self?.checkAndSchedule() }
        scheduleNextWake()
    }

    deinit {
        timer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter = .default, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        }
        observers.append((center, token))
    }

    // MARK: - CRUD

    func add(title: String, date: Date) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        // If created with less than 15 minutes remaining, skip the 15-min pre-alert so it only alerts at the exact time.
        let alreadyInsideLeadWindow = date.timeIntervalSince(now) <= Self.leadTime
        let item = ReminderItem(
            id: UUID(),
            title: trimmed,
            scheduledDate: date,
            isCompleted: false,
            notified15m: alreadyInsideLeadWindow,
            notifiedDue: false
        )
        reminders.append(item)
        sortReminders()
        persist()
        scheduleNextWake()
    }

    func toggleCompleted(_ id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[idx].isCompleted.toggle()
        if !reminders[idx].isCompleted {
            let now = Date()
            reminders[idx].notified15m = reminders[idx].scheduledDate.timeIntervalSince(now) <= Self.leadTime
            reminders[idx].notifiedDue = reminders[idx].scheduledDate <= now
        }
        sortReminders()
        persist()
        scheduleNextWake()
    }

    func markCompleted(_ id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        guard !reminders[idx].isCompleted else { return }
        reminders[idx].isCompleted = true
        sortReminders()
        persist()
        scheduleNextWake()
    }

    func remove(_ id: UUID) {
        reminders.removeAll { $0.id == id }
        persist()
        scheduleNextWake()
    }

    func clearCompleted() {
        reminders.removeAll { $0.isCompleted }
        persist()
        scheduleNextWake()
    }

    // MARK: - Scheduling

    private func sortReminders() {
        reminders.sort { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            return a.scheduledDate < b.scheduledDate
        }
    }

    private func persist() {
        Persistence.save(reminders, to: "reminders.json")
    }

    private func checkAndSchedule() {
        let now = Date()
        var triggered: [NotchAlertItem] = []
        var mutated = false

        for idx in reminders.indices {
            guard !reminders[idx].isCompleted else { continue }
            let dueDate = reminders[idx].scheduledDate
            let preDate = dueDate.addingTimeInterval(-Self.leadTime)

            // 2nd alert: exact scheduled time (sticky until user dismisses)
            if !reminders[idx].notifiedDue && dueDate <= now {
                reminders[idx].notifiedDue = true
                reminders[idx].notified15m = true
                mutated = true
                // Only fire if it hasn't been missed by more than 2 minutes (e.g., long Mac sleep)
                if now.timeIntervalSince(dueDate) <= 120 {
                    triggered.append(
                        NotchAlertItem(
                            id: "rem-due-\(reminders[idx].id.uuidString)",
                            title: reminders[idx].title,
                            scheduledDate: dueDate,
                            stage: .dueNow,
                            colorHex: "#FF9F0A",
                            sourceLabel: "Recordatorio",
                            meetingURL: nil,
                            reminderID: reminders[idx].id
                        )
                    )
                }
                continue
            }

            // 1st alert: 15 minutes before (auto-dismisses after a few seconds)
            if !reminders[idx].notified15m && preDate <= now && dueDate > now {
                reminders[idx].notified15m = true
                mutated = true
                if now.timeIntervalSince(preDate) <= 120 {
                    triggered.append(
                        NotchAlertItem(
                            id: "rem-15m-\(reminders[idx].id.uuidString)",
                            title: reminders[idx].title,
                            scheduledDate: dueDate,
                            stage: .upcoming15m,
                            colorHex: "#FF9F0A",
                            sourceLabel: "Recordatorio",
                            meetingURL: nil,
                            reminderID: reminders[idx].id
                        )
                    )
                }
            }
        }

        if mutated { persist() }
        if !triggered.isEmpty {
            onAlertsTriggered?(triggered)
        }
        scheduleNextWake()
    }

    private func scheduleNextWake() {
        timer?.invalidate()
        timer = nil
        guard onAlertsTriggered != nil else { return }

        let now = Date()
        var nextFire: Date?

        for item in reminders where !item.isCompleted {
            if !item.notified15m {
                let pre = item.scheduledDate.addingTimeInterval(-Self.leadTime)
                if nextFire == nil || pre < nextFire! { nextFire = pre }
            }
            if !item.notifiedDue {
                if nextFire == nil || item.scheduledDate < nextFire! { nextFire = item.scheduledDate }
            }
        }

        guard let fireDate = nextFire else { return }
        let target = max(fireDate, now.addingTimeInterval(0.05))
        let newTimer = Timer(fire: target, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkAndSchedule() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }
}

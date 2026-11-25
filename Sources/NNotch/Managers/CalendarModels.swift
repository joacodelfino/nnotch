import Foundation

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

struct CalendarEventItem: Identifiable, Codable, Equatable {
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


import Foundation

enum OverviewTab: String, CaseIterable, Identifiable, Sendable {
    case keyChanges
    case idleStables
    case idleMajors
    case borrowing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyChanges:
            return "Key Changes"
        case .idleStables:
            return "Idle Stables"
        case .idleMajors:
            return "Idle Majors"
        case .borrowing:
            return "Borrowing"
        }
    }
}

import Foundation

enum AccountFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case inactive

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
        }
    }
}

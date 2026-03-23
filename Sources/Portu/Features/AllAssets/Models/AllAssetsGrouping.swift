import Foundation

enum AllAssetsGrouping: String, CaseIterable, Identifiable, Sendable {
    case category
    case priceSource
    case accountGroup

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .category:
            return "Category"
        case .priceSource:
            return "Price Source"
        case .accountGroup:
            return "Account Group"
        }
    }
}

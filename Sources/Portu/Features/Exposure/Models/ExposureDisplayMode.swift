import Foundation

enum ExposureDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case category
    case asset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .category:
            "By Category"
        case .asset:
            "By Asset"
        }
    }
}

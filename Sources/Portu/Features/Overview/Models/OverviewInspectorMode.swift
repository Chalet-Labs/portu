import Foundation

enum OverviewInspectorMode: String, CaseIterable, Identifiable, Sendable {
    case byAsset
    case byCategory

    var id: Self { self }

    var title: String {
        switch self {
        case .byAsset:
            return "By Asset"
        case .byCategory:
            return "By Category"
        }
    }
}

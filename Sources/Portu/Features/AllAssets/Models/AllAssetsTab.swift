import Foundation

enum AllAssetsTab: String, CaseIterable, Identifiable, Sendable {
    case assets
    case nfts
    case platforms
    case networks

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .assets:
            return "Assets"
        case .nfts:
            return "NFTs"
        case .platforms:
            return "Platforms"
        case .networks:
            return "Networks"
        }
    }

    var systemImage: String {
        switch self {
        case .assets:
            return "bitcoinsign.square"
        case .nfts:
            return "photo.stack"
        case .platforms:
            return "building.columns"
        case .networks:
            return "globe"
        }
    }
}

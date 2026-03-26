import Foundation

enum AssetComparison: String, CaseIterable, Identifiable, Sendable {
    case bitcoin
    case solana

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .bitcoin:
            "BTC"
        case .solana:
            "SOL"
        }
    }

    var coinGeckoID: String {
        switch self {
        case .bitcoin:
            "bitcoin"
        case .solana:
            "solana"
        }
    }
}

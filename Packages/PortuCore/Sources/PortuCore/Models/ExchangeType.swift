import Foundation

public enum ExchangeType: String, Codable, CaseIterable, Sendable {
    case binance
    case coinbase
    case kraken
}

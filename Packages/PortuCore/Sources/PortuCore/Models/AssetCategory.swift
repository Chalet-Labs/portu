import Foundation

/// Groups assets for exposure and performance views.
public enum AssetCategory: String, Codable, CaseIterable, Sendable {
    case major
    case stablecoin
    case defi
    case meme
    case privacy
    case fiat
    case governance
    case other
}

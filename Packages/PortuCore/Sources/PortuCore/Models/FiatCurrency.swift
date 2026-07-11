import Foundation

public enum FiatCurrency: String, CaseIterable, Codable, Sendable, Equatable, Hashable {
    case usd
    case eur
    case chf

    public static let `default`: Self = .usd

    public var displayCode: String {
        rawValue.uppercased()
    }

    public var storageCode: String {
        rawValue
    }

    public var coinGeckoParameter: String {
        rawValue
    }

    public init(storageCode: String?) {
        let normalized = storageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = normalized.flatMap(Self.init(rawValue:)) ?? .default
    }
}

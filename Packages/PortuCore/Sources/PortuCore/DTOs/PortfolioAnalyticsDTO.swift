import CryptoKit
import Foundation

public enum PortfolioAnalyticsProvider: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case zerion
}

public enum PortfolioAnalyticsCoverage: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case noFilter
    case providerReported
}

public enum PortfolioAnalyticsAddressFamily: String, Codable, CaseIterable, Sendable, Equatable, Hashable, Comparable {
    case evm
    case solana

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct PortfolioAnalyticsAddress: Codable, Sendable, Equatable, Hashable, Comparable {
    public let family: PortfolioAnalyticsAddressFamily
    public let value: String

    public init(family: PortfolioAnalyticsAddressFamily, value: String) {
        self.family = family
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = family == .evm ? trimmed.lowercased() : trimmed
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.family != rhs.family {
            return lhs.family < rhs.family
        }
        return lhs.value < rhs.value
    }

    public var isValid: Bool {
        switch family {
        case .evm:
            value.count == 42
                && value.hasPrefix("0x")
                && value.dropFirst(2).allSatisfy(\.isHexDigit)
        case .solana:
            (32 ... 44).contains(value.count)
                && value.allSatisfy {
                    "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".contains($0)
                }
        }
    }
}

public struct PortfolioAnalyticsScope: Codable, Sendable, Equatable, Hashable {
    public let accountID: UUID
    public let dataSource: DataSource
    public let addresses: [PortfolioAnalyticsAddress]
    public let chainIDs: [String]
    public let fingerprint: String

    public init(
        accountID: UUID,
        dataSource: DataSource,
        addresses: [PortfolioAnalyticsAddress],
        chainIDs: [String] = []) {
        self.accountID = accountID
        self.dataSource = dataSource
        self.addresses = Array(Set(addresses)).sorted()
        self.chainIDs = Array(Set(chainIDs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { $0.isEmpty == false })).sorted()

        let identity = ([
            accountID.uuidString.lowercased(),
            dataSource.rawValue
        ] + self.addresses.map { "\($0.family.rawValue):\($0.value)" }
            + self.chainIDs.map { "chain:\($0)" })
            .joined(separator: "|")
        self.fingerprint = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum ProviderPnLRange: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case allTime
    case oneDay
    case oneWeek
    case oneMonth
    case oneYear
    case yearToDate

    public var displayName: String {
        switch self {
        case .allTime: "All"
        case .oneDay: "1D"
        case .oneWeek: "1W"
        case .oneMonth: "1M"
        case .oneYear: "1Y"
        case .yearToDate: "YTD"
        }
    }
}

public enum ProviderPnLFreshness: String, Codable, Sendable, Equatable, Hashable {
    case fresh
    case stale
    case expired

    public static let freshTTL: TimeInterval = 24 * 60 * 60
    public static let bootstrapAge: TimeInterval = 30 * 24 * 60 * 60

    public static func evaluate(fetchedAt: Date, now: Date) -> Self {
        let age = max(0, now.timeIntervalSince(fetchedAt))
        if age < freshTTL {
            return .fresh
        }
        if age < bootstrapAge {
            return .stale
        }
        return .expired
    }
}

public struct ProviderPortfolioValueDTO: Codable, Sendable, Equatable, Hashable {
    public let timestamp: Date
    public let usdValue: Decimal
    public let provider: PortfolioAnalyticsProvider
    public let coverage: PortfolioAnalyticsCoverage

    public init(
        timestamp: Date,
        usdValue: Decimal,
        provider: PortfolioAnalyticsProvider,
        coverage: PortfolioAnalyticsCoverage) {
        self.timestamp = timestamp
        self.usdValue = usdValue
        self.provider = provider
        self.coverage = coverage
    }

    public var day: Date {
        HistoricalPriceCalendar.utcStartOfDay(for: timestamp)
    }
}

public struct ProviderPnLAssetDTO: Sendable, Equatable, Hashable {
    public let implementationID: String
    public let identity: OnchainTokenIdentity?
    public let averageBuyPrice: Decimal?
    public let averageSellPrice: Decimal?
    public let totalGain: Decimal?
    public let realizedGain: Decimal?
    public let unrealizedGain: Decimal?
    public let relativeTotalGain: Decimal?
    public let relativeRealizedGain: Decimal?
    public let relativeUnrealizedGain: Decimal?
    public let totalFee: Decimal?
    public let totalInvested: Decimal?
    public let realizedCostBasis: Decimal?
    public let netInvested: Decimal?
    public let receivedExternal: Decimal?
    public let sentExternal: Decimal?
    public let sentForNFTs: Decimal?
    public let receivedForNFTs: Decimal?

    public init(
        implementationID: String,
        identity: OnchainTokenIdentity? = nil,
        averageBuyPrice: Decimal? = nil,
        averageSellPrice: Decimal? = nil,
        totalGain: Decimal? = nil,
        realizedGain: Decimal? = nil,
        unrealizedGain: Decimal? = nil,
        relativeTotalGain: Decimal? = nil,
        relativeRealizedGain: Decimal? = nil,
        relativeUnrealizedGain: Decimal? = nil,
        totalFee: Decimal? = nil,
        totalInvested: Decimal? = nil,
        realizedCostBasis: Decimal? = nil,
        netInvested: Decimal? = nil,
        receivedExternal: Decimal? = nil,
        sentExternal: Decimal? = nil,
        sentForNFTs: Decimal? = nil,
        receivedForNFTs: Decimal? = nil) {
        self.implementationID = implementationID
        self.identity = identity
        self.averageBuyPrice = averageBuyPrice
        self.averageSellPrice = averageSellPrice
        self.totalGain = totalGain
        self.realizedGain = realizedGain
        self.unrealizedGain = unrealizedGain
        self.relativeTotalGain = relativeTotalGain
        self.relativeRealizedGain = relativeRealizedGain
        self.relativeUnrealizedGain = relativeUnrealizedGain
        self.totalFee = totalFee
        self.totalInvested = totalInvested
        self.realizedCostBasis = realizedCostBasis
        self.netInvested = netInvested
        self.receivedExternal = receivedExternal
        self.sentExternal = sentExternal
        self.sentForNFTs = sentForNFTs
        self.receivedForNFTs = receivedForNFTs
    }
}

public struct ProviderPnLDTO: Sendable, Equatable, Hashable {
    public let range: ProviderPnLRange
    public let currency: FiatCurrency
    public let totalGain: Decimal
    public let realizedGain: Decimal?
    public let unrealizedGain: Decimal?
    public let relativeTotalGain: Decimal?
    public let relativeRealizedGain: Decimal?
    public let relativeUnrealizedGain: Decimal?
    public let totalFee: Decimal?
    public let totalInvested: Decimal?
    public let realizedCostBasis: Decimal?
    public let netInvested: Decimal?
    public let receivedExternal: Decimal?
    public let sentExternal: Decimal?
    public let sentForNFTs: Decimal?
    public let receivedForNFTs: Decimal?
    public let excludedIdentifiers: [String]
    public let assets: [ProviderPnLAssetDTO]
    public let fetchedAt: Date

    public init(
        range: ProviderPnLRange,
        currency: FiatCurrency,
        totalGain: Decimal,
        realizedGain: Decimal? = nil,
        unrealizedGain: Decimal? = nil,
        relativeTotalGain: Decimal? = nil,
        relativeRealizedGain: Decimal? = nil,
        relativeUnrealizedGain: Decimal? = nil,
        totalFee: Decimal? = nil,
        totalInvested: Decimal? = nil,
        realizedCostBasis: Decimal? = nil,
        netInvested: Decimal? = nil,
        receivedExternal: Decimal? = nil,
        sentExternal: Decimal? = nil,
        sentForNFTs: Decimal? = nil,
        receivedForNFTs: Decimal? = nil,
        excludedIdentifiers: [String] = [],
        assets: [ProviderPnLAssetDTO] = [],
        fetchedAt: Date) {
        self.range = range
        self.currency = currency
        self.totalGain = totalGain
        self.realizedGain = realizedGain
        self.unrealizedGain = unrealizedGain
        self.relativeTotalGain = relativeTotalGain
        self.relativeRealizedGain = relativeRealizedGain
        self.relativeUnrealizedGain = relativeUnrealizedGain
        self.totalFee = totalFee
        self.totalInvested = totalInvested
        self.realizedCostBasis = realizedCostBasis
        self.netInvested = netInvested
        self.receivedExternal = receivedExternal
        self.sentExternal = sentExternal
        self.sentForNFTs = sentForNFTs
        self.receivedForNFTs = receivedForNFTs
        self.excludedIdentifiers = excludedIdentifiers.sorted()
        self.assets = assets.sorted { $0.implementationID < $1.implementationID }
        self.fetchedAt = fetchedAt
    }
}

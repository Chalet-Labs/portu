import Foundation
import SwiftData

@Model
public final class ProviderPnLSnapshot {
    #Index<ProviderPnLSnapshot>([\.accountID], [\.scopeFingerprint], [\.fetchedAt])

    @Attribute(.unique) public var cacheKey: String
    public var accountID: UUID
    public var scopeFingerprint: String
    public var provider: PortfolioAnalyticsProvider
    public var range: ProviderPnLRange
    public var currency: FiatCurrency
    public var totalGain: Decimal
    public var realizedGain: Decimal?
    public var unrealizedGain: Decimal?
    public var relativeTotalGain: Decimal?
    public var relativeRealizedGain: Decimal?
    public var relativeUnrealizedGain: Decimal?
    public var totalFee: Decimal?
    public var totalInvested: Decimal?
    public var realizedCostBasis: Decimal?
    public var netInvested: Decimal?
    public var receivedExternal: Decimal?
    public var sentExternal: Decimal?
    public var sentForNFTs: Decimal?
    public var receivedForNFTs: Decimal?
    private var excludedIdentifiersData: Data
    public var fetchedAt: Date

    public var excludedIdentifiers: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: excludedIdentifiersData)) ?? []
        }
        set {
            let normalized = Array(Set(newValue)).sorted()
            excludedIdentifiersData = (try? JSONEncoder().encode(normalized)) ?? Data("[]".utf8)
        }
    }

    @Relationship(deleteRule: .cascade, inverse: \ProviderPnLAssetBreakdown.snapshot)
    public var assetBreakdowns: [ProviderPnLAssetBreakdown]

    public init(
        accountID: UUID,
        scopeFingerprint: String,
        provider: PortfolioAnalyticsProvider,
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
        fetchedAt: Date,
        assetBreakdowns: [ProviderPnLAssetBreakdown] = []) {
        self.cacheKey = Self.cacheKey(
            accountID: accountID,
            scopeFingerprint: scopeFingerprint,
            provider: provider,
            range: range,
            currency: currency)
        self.accountID = accountID
        self.scopeFingerprint = scopeFingerprint
        self.provider = provider
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
        let normalizedExcludedIdentifiers = Array(Set(excludedIdentifiers)).sorted()
        self.excludedIdentifiersData =
            (try? JSONEncoder().encode(normalizedExcludedIdentifiers)) ?? Data("[]".utf8)
        self.fetchedAt = fetchedAt
        self.assetBreakdowns = assetBreakdowns
    }

    public static func cacheKey(
        accountID: UUID,
        scopeFingerprint: String,
        provider: PortfolioAnalyticsProvider,
        range: ProviderPnLRange,
        currency: FiatCurrency) -> String {
        [
            accountID.uuidString.lowercased(),
            scopeFingerprint,
            provider.rawValue,
            range.rawValue,
            currency.rawValue
        ].joined(separator: "|")
    }
}

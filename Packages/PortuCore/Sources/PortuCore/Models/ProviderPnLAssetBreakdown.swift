import Foundation
import SwiftData

@Model
public final class ProviderPnLAssetBreakdown {
    @Attribute(.unique) public var id: UUID
    public var implementationID: String
    public var chain: Chain?
    public var contractAddress: String?
    public var averageBuyPrice: Decimal?
    public var averageSellPrice: Decimal?
    public var totalGain: Decimal?
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
    public var snapshot: ProviderPnLSnapshot?

    public init(
        id: UUID = UUID(),
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
        receivedForNFTs: Decimal? = nil,
        snapshot: ProviderPnLSnapshot? = nil) {
        self.id = id
        self.implementationID = implementationID
        self.chain = identity?.chain
        self.contractAddress = identity?.contractAddress
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
        self.snapshot = snapshot
    }

    public var identity: OnchainTokenIdentity? {
        guard let chain, let contractAddress else { return nil }
        return OnchainTokenIdentity(chain: chain, contractAddress: contractAddress)
    }
}

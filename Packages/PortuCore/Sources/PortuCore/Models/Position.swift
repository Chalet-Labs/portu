import Foundation
import SwiftData

@Model
public final class Position {
    @Attribute(.unique) public var id: UUID

    public var positionType: PositionType

    /// nil = off-chain (exchange custody, manual entry)
    public var chain: Chain?

    /// Zapper protocol identifier
    public var protocolId: String?
    public var protocolName: String?

    /// String, not URL — SwiftData predicate compatibility
    public var protocolLogoURL: String?

    /// Lending positions only
    public var healthFactor: Double?

    /// Pre-computed signed total by SyncEngine
    public var netUSDValue: Decimal

    @Relationship(deleteRule: .cascade, inverse: \PositionToken.position)
    public var tokens: [PositionToken]

    public var account: Account?

    public var syncedAt: Date

    public init(
        id: UUID = UUID(),
        positionType: PositionType,
        chain: Chain? = nil,
        protocolId: String? = nil,
        protocolName: String? = nil,
        protocolLogoURL: String? = nil,
        healthFactor: Double? = nil,
        netUSDValue: Decimal = 0,
        tokens: [PositionToken] = [],
        account: Account? = nil,
        syncedAt: Date = .now) {
        self.id = id
        self.positionType = positionType
        self.chain = chain
        self.protocolId = protocolId
        self.protocolName = protocolName
        self.protocolLogoURL = protocolLogoURL
        self.healthFactor = healthFactor
        self.netUSDValue = netUSDValue
        self.tokens = tokens
        self.account = account
        self.syncedAt = syncedAt
    }
}

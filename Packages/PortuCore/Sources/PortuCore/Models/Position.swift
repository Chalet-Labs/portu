import Foundation
import SwiftData

/// A persisted portfolio position such as an idle balance, lending position, or LP position.
@Model
public final class Position {
    public var id: UUID
    public var positionType: PositionType
    public var chain: Chain?
    public var protocolId: String?
    public var protocolName: String?
    public var protocolLogoURL: String?
    public var healthFactor: Double?
    public var netUSDValue: Decimal
    public var account: Account?
    public var syncedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PositionToken.position)
    public var tokens: [PositionToken]

    public init(
        positionType: PositionType,
        netUSDValue: Decimal,
        chain: Chain? = nil,
        protocolId: String? = nil,
        protocolName: String? = nil,
        protocolLogoURL: String? = nil,
        healthFactor: Double? = nil,
        account: Account? = nil,
        syncedAt: Date = .now
    ) {
        self.id = UUID()
        self.positionType = positionType
        self.chain = chain
        self.protocolId = protocolId
        self.protocolName = protocolName
        self.protocolLogoURL = protocolLogoURL
        self.healthFactor = healthFactor
        self.netUSDValue = netUSDValue
        self.account = account
        self.syncedAt = syncedAt
        self.tokens = []
    }
}

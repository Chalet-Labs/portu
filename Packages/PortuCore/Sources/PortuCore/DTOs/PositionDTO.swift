import Foundation

/// Returned by PortfolioDataProvider. SyncEngine maps these to @Model objects.
public struct PositionDTO: Sendable {
    public let positionType: PositionType
    public let chain: Chain?
    public let protocolId: String?
    public let protocolName: String?
    public let protocolLogoURL: String?
    public let healthFactor: Double?
    public let tokens: [TokenDTO]

    public init(positionType: PositionType, chain: Chain?, protocolId: String?, protocolName: String?, protocolLogoURL: String?, healthFactor: Double?, tokens: [TokenDTO]) {
        self.positionType = positionType
        self.chain = chain
        self.protocolId = protocolId
        self.protocolName = protocolName
        self.protocolLogoURL = protocolLogoURL
        self.healthFactor = healthFactor
        self.tokens = tokens
    }
}

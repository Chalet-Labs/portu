import Foundation

/// Account-scoped input DTO used by providers and the sync engine.
public struct SyncContext: Sendable {
    public let accountId: UUID
    public let kind: AccountKind
    public let addresses: [(address: String, chain: Chain?)]
    public let exchangeType: ExchangeType?

    public init(
        accountId: UUID,
        kind: AccountKind,
        addresses: [(address: String, chain: Chain?)],
        exchangeType: ExchangeType?
    ) {
        self.accountId = accountId
        self.kind = kind
        self.addresses = addresses
        self.exchangeType = exchangeType
    }
}

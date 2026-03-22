import Foundation

/// Lightweight DTO constructed by SyncEngine from an Account @Model.
/// Carries only the data a provider needs — no SwiftData types.
public struct SyncContext: Sendable {
    public let accountId: UUID
    public let kind: AccountKind
    public let addresses: [(address: String, chain: Chain?)]
    public let exchangeType: ExchangeType?

    public init(accountId: UUID, kind: AccountKind, addresses: [(address: String, chain: Chain?)], exchangeType: ExchangeType?) {
        self.accountId = accountId
        self.kind = kind
        self.addresses = addresses
        self.exchangeType = exchangeType
    }
}

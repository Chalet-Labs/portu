import Foundation
import SwiftData

/// A wallet address tracked for an account, optionally scoped to a specific chain.
@Model
public final class WalletAddress {
    public var id: UUID
    public var chain: Chain?
    public var address: String
    public var account: Account?

    public init(
        address: String,
        chain: Chain? = nil,
        account: Account? = nil
    ) {
        self.id = UUID()
        self.chain = chain
        self.address = address
        self.account = account
    }
}

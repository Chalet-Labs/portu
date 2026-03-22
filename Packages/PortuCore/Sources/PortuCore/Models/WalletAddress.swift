import Foundation
import SwiftData

@Model
public final class WalletAddress {
    @Attribute(.unique) public var id: UUID

    /// nil = EVM address (provider queries all EVM chains)
    /// Set (e.g., .solana) = restrict to that chain
    public var chain: Chain?

    public var address: String

    public var account: Account?

    public init(
        id: UUID = UUID(),
        chain: Chain? = nil,
        address: String,
        account: Account? = nil
    ) {
        self.id = id
        self.chain = chain
        self.address = address
        self.account = account
    }
}

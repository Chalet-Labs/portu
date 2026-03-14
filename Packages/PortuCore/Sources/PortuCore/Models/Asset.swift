import Foundation
import SwiftData

@Model
public final class Asset {
    public var id: UUID
    public var symbol: String
    public var name: String
    public var coinGeckoId: String
    public var chain: Chain?
    public var contractAddress: String?

    // Back-reference from Holding.asset. No @Relationship here — it's on Holding side.
    // nullify = optional. Assets are shared reference data, never cascade-deleted.
    public var holdings: [Holding]

    public init(symbol: String, name: String, coinGeckoId: String) {
        self.id = UUID()
        self.symbol = symbol
        self.name = name
        self.coinGeckoId = coinGeckoId
        self.holdings = []
    }
}

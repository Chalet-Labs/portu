import Foundation

/// Carries inline asset metadata — there is no separate AssetDTO.
/// amount and usdValue are ALWAYS POSITIVE (role provides sign).
public struct TokenDTO: Sendable {
    public let role: TokenRole
    public let symbol: String
    public let name: String
    public let amount: Decimal
    public let usdValue: Decimal
    public let chain: Chain?
    public let contractAddress: String?
    public let debankId: String?
    public let coinGeckoId: String?
    public let sourceKey: String?
    public let logoURL: String?
    public let category: AssetCategory
    public let isVerified: Bool

    public init(
        role: TokenRole,
        symbol: String,
        name: String,
        amount: Decimal,
        usdValue: Decimal,
        chain: Chain?,
        contractAddress: String?,
        debankId: String?,
        coinGeckoId: String?,
        sourceKey: String?,
        logoURL: String?,
        category: AssetCategory,
        isVerified: Bool
    ) {
        self.role = role
        self.symbol = symbol
        self.name = name
        self.amount = amount
        self.usdValue = usdValue
        self.chain = chain
        self.contractAddress = contractAddress
        self.debankId = debankId
        self.coinGeckoId = coinGeckoId
        self.sourceKey = sourceKey
        self.logoURL = logoURL
        self.category = category
        self.isVerified = isVerified
    }
}

import Foundation
import PortuCore

struct ExchangeResponseDTO: Decodable, Sendable {
    let balances: [BalanceRecord]

    struct BalanceRecord: Decodable, Sendable {
        let symbol: String
        let name: String
        let amount: Decimal
        let usdValue: Decimal
        let coinGeckoId: String?
        let sourceKey: String?
        let logoURL: String?
        let category: AssetCategory
        let isVerified: Bool

        func positionDTO(sourceKeyPrefix: String?) -> PositionDTO {
            let token = TokenDTO(
                role: .balance,
                symbol: symbol,
                name: name,
                amount: amount,
                usdValue: usdValue,
                chain: nil,
                contractAddress: nil,
                debankId: nil,
                coinGeckoId: coinGeckoId,
                sourceKey: sourceKey ?? sourceKeyPrefix,
                logoURL: logoURL,
                category: category,
                isVerified: isVerified
            )

            return PositionDTO(
                positionType: .idle,
                chain: nil,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [token]
            )
        }
    }
}

import Foundation
import PortuCore

struct ZapperResponseDTO: Decodable, Sendable {
    let positions: [PositionRecord]

    struct PositionRecord: Decodable, Sendable {
        let positionType: PositionType
        let chain: Chain?
        let protocolId: String?
        let protocolName: String?
        let protocolLogoURL: String?
        let healthFactor: Double?
        let tokens: [TokenRecord]

        var positionDTO: PositionDTO {
            PositionDTO(
                positionType: positionType,
                chain: chain,
                protocolId: protocolId,
                protocolName: protocolName,
                protocolLogoURL: protocolLogoURL,
                healthFactor: healthFactor,
                tokens: tokens.map(\.tokenDTO)
            )
        }
    }

    struct TokenRecord: Decodable, Sendable {
        let role: TokenRole
        let symbol: String
        let name: String
        let amount: Decimal
        let usdValue: Decimal
        let chain: Chain?
        let contractAddress: String?
        let debankId: String?
        let coinGeckoId: String?
        let sourceKey: String?
        let logoURL: String?
        let category: AssetCategory
        let isVerified: Bool

        var tokenDTO: TokenDTO {
            TokenDTO(
                role: role,
                symbol: symbol,
                name: name,
                amount: amount,
                usdValue: usdValue,
                chain: chain,
                contractAddress: contractAddress,
                debankId: debankId,
                coinGeckoId: coinGeckoId,
                sourceKey: sourceKey,
                logoURL: logoURL,
                category: category,
                isVerified: isVerified
            )
        }
    }
}

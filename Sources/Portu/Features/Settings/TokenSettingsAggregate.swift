import Foundation
import PortuCore

struct TokenSettingsAggregate {
    var base: TokenEntry
    var coinGeckoId: String?
    var onchainIdentity: OnchainTokenIdentity?
    var logoURL: String?
    var positiveAmount: Decimal = 0
    var borrowAmount: Decimal = 0
    var positiveUSDValue: Decimal = 0
    var borrowUSDValue: Decimal = 0

    var netAmount: Decimal {
        positiveAmount - borrowAmount
    }

    var netUSDValue: Decimal {
        positiveUSDValue - borrowUSDValue
    }

    init(_ token: TokenEntry) {
        self.base = token
        self.coinGeckoId = token.coinGeckoId
        self.onchainIdentity = token.onchainIdentity
        self.logoURL = token.logoURL
        add(token)
    }

    mutating func add(_ token: TokenEntry) {
        if coinGeckoId == nil {
            coinGeckoId = token.coinGeckoId
        }
        if onchainIdentity == nil {
            onchainIdentity = token.onchainIdentity
        }
        if logoURL == nil {
            logoURL = token.logoURL
        }

        if token.role.isBorrow {
            borrowAmount += token.amount
            borrowUSDValue += token.usdValue
        } else {
            positiveAmount += token.amount
            positiveUSDValue += token.usdValue
        }
    }
}

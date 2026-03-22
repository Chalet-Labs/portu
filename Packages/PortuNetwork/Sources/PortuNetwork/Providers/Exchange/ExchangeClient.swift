import Foundation
import PortuCore

protocol ExchangeClient: Sendable {
    func fetchBalances(apiKey: String, apiSecret: String, passphrase: String?) async throws -> [TokenDTO]
}

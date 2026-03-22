import Foundation
import PortuCore

struct CoinbaseClient: ExchangeClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func fetchBalances(apiKey: String, apiSecret: String, passphrase: String?) async throws -> [TokenDTO] {
        throw ExchangeError.notImplemented("Coinbase")
    }
}

import Foundation
import PortuCore

struct CoinbaseClient: ExchangeClient {
    private let session: URLSession
    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchBalances(apiKey _: String, apiSecret _: String, passphrase _: String?) async throws -> [TokenDTO] {
        throw ExchangeError.notImplemented("Coinbase")
    }
}

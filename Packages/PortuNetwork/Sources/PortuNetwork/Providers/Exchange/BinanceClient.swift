import Foundation
import PortuCore

struct BinanceClient: ExchangeClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func fetchBalances(apiKey: String, apiSecret: String, passphrase: String?) async throws -> [TokenDTO] {
        throw ExchangeError.notImplemented("Binance")
    }
}

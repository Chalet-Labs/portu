import CryptoKit
import Foundation
import PortuCore

struct KrakenClient: ExchangeClient {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://api.kraken.com")!) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchBalances(apiKey: String, apiSecret: String, passphrase _: String?) async throws -> [TokenDTO] {
        let path = "/0/private/Balance"
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000))
        let postData = "nonce=\(nonce)"
        let signature = try generateSignature(path: path, nonce: nonce, postData: postData, apiSecret: apiSecret)

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = postData.data(using: .utf8)
        request.setValue(apiKey, forHTTPHeaderField: "API-Key")
        request.setValue(signature, forHTTPHeaderField: "API-Sign")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ExchangeError.httpError
        }
        return try parseKrakenBalances(data: data)
    }

    private func generateSignature(path: String, nonce: String, postData: String, apiSecret: String) throws -> String {
        guard let secretData = Data(base64Encoded: apiSecret) else {
            throw ExchangeError.invalidCredentials
        }
        let message = nonce + postData
        let pathData = path.data(using: .utf8)!
        let messageHash = SHA256.hash(data: Data(message.utf8))
        let hmacInput = pathData + Data(messageHash)
        let hmac = HMAC<SHA512>.authenticationCode(for: hmacInput, using: SymmetricKey(data: secretData))
        return Data(hmac).base64EncodedString()
    }

    private func parseKrakenBalances(data: Data) throws -> [TokenDTO] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errors = json["error"] as? [String]
        else {
            throw ExchangeError.decodingFailed
        }
        if !errors.isEmpty {
            throw ExchangeError.apiError(messages: errors)
        }
        guard let result = json["result"] as? [String: String] else {
            throw ExchangeError.decodingFailed
        }
        return result.compactMap { ticker, balanceStr -> TokenDTO? in
            guard let balance = Decimal(string: balanceStr), balance > 0 else { return nil }
            let symbol = normalizeKrakenSymbol(ticker)
            return TokenDTO(
                role: .balance, symbol: symbol, name: symbol,
                amount: balance, usdValue: 0,
                chain: nil, contractAddress: nil, debankId: nil,
                coinGeckoId: nil, sourceKey: "kraken:\(ticker)",
                logoURL: nil, category: .other, isVerified: true)
        }
    }

    private func normalizeKrakenSymbol(_ ticker: String) -> String {
        let mapping: [String: String] = [
            "XXBT": "BTC", "XETH": "ETH", "XLTC": "LTC",
            "XXRP": "XRP", "XXLM": "XLM", "XZEC": "ZEC",
            "ZUSD": "USD", "ZEUR": "EUR", "ZGBP": "GBP"
        ]
        return mapping[ticker] ?? ticker
    }
}

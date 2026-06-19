struct ExchangeCredentialSnapshot: Equatable {
    var apiKey: String?
    var apiSecret: String?
    var passphrase: String?

    static let empty = Self(apiKey: nil, apiSecret: nil, passphrase: nil)
}

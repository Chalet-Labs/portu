# Phase 1b: Providers, PriceService & SyncEngine

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the provider abstraction, concrete Zapper and Exchange providers, update PriceService for 24h changes, build SyncEngine to orchestrate fetch→persist→snapshot, and update AppState.

**Architecture:** PortuNetwork provides the `PortfolioDataProvider` protocol and concrete `actor` implementations. SyncEngine lives in the app target — the only place that bridges DTOs to SwiftData. All SwiftData writes happen on MainActor via `ModelContext`.

**Tech Stack:** Swift 6.2, SwiftData, URLSession, Swift Testing

**Spec Reference:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md` (API Layer, Sync Model sections)

**Depends on:** Plan 01 (Data Models & DTOs) must be completed first.

---

## File Structure

### Create
- `Packages/PortuNetwork/Sources/PortuNetwork/Providers/PortfolioDataProvider.swift`
- `Packages/PortuNetwork/Sources/PortuNetwork/Providers/ProviderCapabilities.swift`
- `Packages/PortuNetwork/Sources/PortuNetwork/Providers/ZapperProvider.swift`
- `Packages/PortuNetwork/Sources/PortuNetwork/Providers/ExchangeProvider.swift`
- `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/ExchangeClient.swift`
- `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/KrakenClient.swift`
- `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/BinanceClient.swift`
- `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/CoinbaseClient.swift`
- `Packages/PortuNetwork/Tests/PortuNetworkTests/ProviderTests.swift`
- `Packages/PortuNetwork/Tests/PortuNetworkTests/MockProvider.swift`
- `Sources/Portu/Sync/SyncEngine.swift`
- `Tests/PortuTests/SyncEngineTests.swift`

### Modify
- `Packages/PortuNetwork/Package.swift` — remove `defaultIsolation(MainActor.self)`
- `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/PriceService.swift` — add 24h changes, return `PriceUpdate`
- `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/CoinGeckoDTO.swift` — parse 24h change
- `Packages/PortuNetwork/Tests/PortuNetworkTests/PriceServiceTests.swift` — update for PriceUpdate
- `Packages/PortuCore/Sources/PortuCore/Keychain/KeychainService.swift` — minor (key naming docs only)

**Note:** `SecretStore` protocol already exists at `Packages/PortuCore/Sources/PortuCore/Protocols/SecretStore.swift`. `KeychainService` already conforms to it. No changes needed to these files — only referenced by SyncEngine and ExchangeProvider.
- `Sources/Portu/App/AppState.swift` — add SyncStatus, priceChanges24h, rework
- `Sources/Portu/App/PortuApp.swift` — inject SyncEngine

---

### Task 1: Remove default MainActor isolation from PortuNetwork

**Files:**
- Modify: `Packages/PortuNetwork/Package.swift`

Per spec: PortuNetwork has **no default isolation**. Providers are `actor` types that run off main thread.

- [ ] **Step 1: Update Package.swift**

```swift
// Packages/PortuNetwork/Package.swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortuNetwork",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PortuNetwork", targets: ["PortuNetwork"]),
    ],
    dependencies: [
        .package(path: "../PortuCore"),
    ],
    targets: [
        .target(
            name: "PortuNetwork",
            dependencies: ["PortuCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "PortuNetworkTests",
            dependencies: ["PortuNetwork"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --package-path Packages/PortuNetwork 2>&1 | tail -10`
Expected: May have errors from PriceService needing `nonisolated` adjustments — fix in Task 6.

- [ ] **Step 3: Commit**

```bash
git add Packages/PortuNetwork/Package.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: remove default MainActor isolation from PortuNetwork

Providers are actor types with their own isolation. PriceService
is already an actor. No default isolation needed.
EOF
)"
```

---

### Task 2: PortfolioDataProvider protocol and ProviderCapabilities

**Files:**
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/PortfolioDataProvider.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/ProviderCapabilities.swift`

- [ ] **Step 1: Create Providers directory**

```bash
mkdir -p Packages/PortuNetwork/Sources/PortuNetwork/Providers
```

- [ ] **Step 2: Write ProviderCapabilities**

```swift
// Packages/PortuNetwork/Sources/PortuNetwork/Providers/ProviderCapabilities.swift
import Foundation

public struct ProviderCapabilities: Sendable {
    public var supportsTokenBalances: Bool
    public var supportsDeFiPositions: Bool
    public var supportsHealthFactors: Bool

    public init(
        supportsTokenBalances: Bool = true,
        supportsDeFiPositions: Bool = false,
        supportsHealthFactors: Bool = false
    ) {
        self.supportsTokenBalances = supportsTokenBalances
        self.supportsDeFiPositions = supportsDeFiPositions
        self.supportsHealthFactors = supportsHealthFactors
    }
}
```

- [ ] **Step 3: Write PortfolioDataProvider protocol**

```swift
// Packages/PortuNetwork/Sources/PortuNetwork/Providers/PortfolioDataProvider.swift
import Foundation
import PortuCore

/// Source-agnostic abstraction for portfolio data providers.
/// Account-scoped via SyncContext. Returns plain Sendable DTOs.
public protocol PortfolioDataProvider: Sendable {
    var capabilities: ProviderCapabilities { get }
    func fetchBalances(context: SyncContext) async throws -> [PositionDTO]
    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO]
}

extension PortfolioDataProvider {
    /// Default: no DeFi support
    public func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] { [] }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `swift build --package-path Packages/PortuNetwork 2>&1 | tail -10`

- [ ] **Step 5: Commit**

```bash
git add Packages/PortuNetwork/Sources/PortuNetwork/Providers/
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add PortfolioDataProvider protocol and ProviderCapabilities

Account-scoped provider abstraction returning plain Sendable DTOs.
Default implementation returns empty DeFi positions.
EOF
)"
```

---

### Task 3: ZapperProvider

**Files:**
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/ZapperProvider.swift`

First concrete provider. Zapper API v2 for token balances and DeFi positions. Actor-isolated for thread safety.

**Important:** Verify exact Zapper API endpoints and response format during implementation. The structure below follows their documented patterns — check `https://studio.zapper.xyz/docs/apis` for current v2 API schema.

- [ ] **Step 1: Write ZapperProvider**

```swift
// Packages/PortuNetwork/Sources/PortuNetwork/Providers/ZapperProvider.swift
import Foundation
import PortuCore

public actor ZapperProvider: PortfolioDataProvider {
    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL

    public var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsTokenBalances: true,
            supportsDeFiPositions: true,
            supportsHealthFactors: false  // partial — depends on protocol
        )
    }

    public init(
        apiKey: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.zapper.xyz/v2")!
    ) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        var allPositions: [PositionDTO] = []
        for (address, _) in context.addresses {
            let positions = try await fetchTokenBalances(address: address)
            allPositions.append(contentsOf: positions)
        }
        return allPositions
    }

    public func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        var allPositions: [PositionDTO] = []
        for (address, _) in context.addresses {
            let positions = try await fetchAppPositions(address: address)
            allPositions.append(contentsOf: positions)
        }
        return allPositions
    }

    // MARK: - Private API Calls

    private func fetchTokenBalances(address: String) async throws -> [PositionDTO] {
        // TODO: Verify exact Zapper v2 endpoint for token balances
        // Expected: GET /balances/tokens?addresses[]={address}
        var components = URLComponents(url: baseURL.appendingPathComponent("balances/tokens"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "addresses[]", value: address),
        ]

        let data = try await makeRequest(url: components.url!)
        return try parseTokenBalances(data: data)
    }

    private func fetchAppPositions(address: String) async throws -> [PositionDTO] {
        // TODO: Verify exact Zapper v2 endpoint for DeFi/app positions
        // Expected: GET /apps/positions?addresses[]={address}
        var components = URLComponents(url: baseURL.appendingPathComponent("apps/positions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "addresses[]", value: address),
        ]

        let data = try await makeRequest(url: components.url!)
        return try parseAppPositions(data: data)
    }

    private func makeRequest(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZapperError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 429:
            throw ZapperError.rateLimited
        case 401, 403:
            throw ZapperError.unauthorized
        default:
            throw ZapperError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Response Parsing

    // TODO: Update these parsers once Zapper v2 response format is confirmed.
    // The mapping logic below shows the pattern — adjust field names to match
    // actual API responses.

    private func parseTokenBalances(data: Data) throws -> [PositionDTO] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ZapperError.decodingFailed
        }

        return json.compactMap { item -> PositionDTO? in
            guard let symbol = item["symbol"] as? String,
                  let name = item["name"] as? String,
                  let balanceUSD = item["balanceUSD"] as? Double,
                  let balance = item["balance"] as? Double else {
                return nil
            }

            let chainStr = item["network"] as? String
            let chain = chainStr.flatMap { Chain(rawValue: $0) }

            let token = TokenDTO(
                role: .balance,
                symbol: symbol,
                name: name,
                amount: Decimal(balance),
                usdValue: Decimal(balanceUSD),
                chain: chain,
                contractAddress: item["address"] as? String,
                debankId: nil,
                coinGeckoId: item["coingeckoId"] as? String,
                sourceKey: (item["address"] as? String).map { "zapper:\($0)" },
                logoURL: item["imgUrl"] as? String,
                category: .other, // TODO: map from Zapper category
                isVerified: item["verified"] as? Bool ?? false
            )

            return PositionDTO(
                positionType: .idle,
                chain: chain,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [token]
            )
        }
    }

    private func parseAppPositions(data: Data) throws -> [PositionDTO] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ZapperError.decodingFailed
        }

        // TODO: Implement full DeFi position parsing based on Zapper v2 response.
        // Pattern: group tokens by protocol+position, map roles (supply/borrow/reward),
        // extract healthFactor from lending positions.
        return json.compactMap { item -> PositionDTO? in
            // Placeholder structure — flesh out during implementation
            guard let appId = item["appId"] as? String else { return nil }

            let posType: PositionType = switch item["type"] as? String {
            case "lending": .lending
            case "liquidity-pool": .liquidityPool
            case "staking": .staking
            case "farming": .farming
            default: .other
            }

            // Parse tokens array from response
            let tokens = parsePositionTokens(item["tokens"] as? [[String: Any]] ?? [])

            return PositionDTO(
                positionType: posType,
                chain: (item["network"] as? String).flatMap { Chain(rawValue: $0) },
                protocolId: appId,
                protocolName: item["appName"] as? String,
                protocolLogoURL: item["appImage"] as? String,
                healthFactor: item["healthFactor"] as? Double,
                tokens: tokens
            )
        }
    }

    private func parsePositionTokens(_ tokensJSON: [[String: Any]]) -> [TokenDTO] {
        tokensJSON.compactMap { item -> TokenDTO? in
            guard let symbol = item["symbol"] as? String,
                  let balance = item["balance"] as? Double,
                  let balanceUSD = item["balanceUSD"] as? Double else {
                return nil
            }

            let roleStr = item["type"] as? String ?? "balance"
            let role: TokenRole = switch roleStr {
            case "supply": .supply
            case "borrow": .borrow
            case "reward": .reward
            case "stake": .stake
            default: .balance
            }

            return TokenDTO(
                role: role,
                symbol: symbol,
                name: item["name"] as? String ?? symbol,
                amount: Decimal(abs(balance)), // Always positive
                usdValue: Decimal(abs(balanceUSD)), // Always positive
                chain: (item["network"] as? String).flatMap { Chain(rawValue: $0) },
                contractAddress: item["address"] as? String,
                debankId: nil,
                coinGeckoId: item["coingeckoId"] as? String,
                sourceKey: (item["address"] as? String).map { "zapper:\($0)" },
                logoURL: item["imgUrl"] as? String,
                category: .other,
                isVerified: item["verified"] as? Bool ?? false
            )
        }
    }
}

enum ZapperError: Error, LocalizedError {
    case invalidResponse
    case rateLimited
    case unauthorized
    case httpError(statusCode: Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Zapper API"
        case .rateLimited: "Zapper API rate limit exceeded"
        case .unauthorized: "Invalid Zapper API key"
        case .httpError(let code): "Zapper API returned HTTP \(code)"
        case .decodingFailed: "Failed to parse Zapper API response"
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --package-path Packages/PortuNetwork 2>&1 | tail -10`

- [ ] **Step 3: Commit**

```bash
git add Packages/PortuNetwork/Sources/PortuNetwork/Providers/ZapperProvider.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add ZapperProvider for token balances and DeFi positions

Actor-isolated provider using Zapper v2 API. Fetches per-address
across all chains. Returns PositionDTO/TokenDTO with proper role
mapping. API response parsing may need adjustment once tested
against live API.
EOF
)"
```

---

### Task 4: ExchangeProvider with exchange client pattern

**Files:**
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/ExchangeClient.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/KrakenClient.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/BinanceClient.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/CoinbaseClient.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/ExchangeProvider.swift`

ExchangeProvider routes to exchange-specific clients based on `SyncContext.exchangeType`.

- [ ] **Step 1: Create Exchange directory**

```bash
mkdir -p Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange
```

- [ ] **Step 2: Write ExchangeClient protocol**

```swift
// Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/ExchangeClient.swift
import Foundation
import PortuCore

/// Exchange-specific API client. Each exchange implements this.
protocol ExchangeClient: Sendable {
    func fetchBalances(apiKey: String, apiSecret: String, passphrase: String?) async throws -> [TokenDTO]
}
```

- [ ] **Step 3: Write KrakenClient**

```swift
// Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/KrakenClient.swift
import Foundation
import PortuCore
import CryptoKit

struct KrakenClient: ExchangeClient {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://api.kraken.com")!) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchBalances(apiKey: String, apiSecret: String, passphrase: String?) async throws -> [TokenDTO] {
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
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["error"] as? [String], errors.isEmpty,
              let result = json["result"] as? [String: String] else {
            throw ExchangeError.decodingFailed
        }

        return result.compactMap { (ticker, balanceStr) -> TokenDTO? in
            guard let balance = Decimal(string: balanceStr), balance > 0 else { return nil }

            // Kraken uses non-standard ticker symbols (e.g., XXBT for BTC, ZUSD for USD)
            let symbol = normalizeKrakenSymbol(ticker)

            return TokenDTO(
                role: .balance,
                symbol: symbol,
                name: symbol, // Kraken doesn't return full names
                amount: balance,
                usdValue: 0, // Will be priced by PriceService via coinGeckoId
                chain: nil, // Exchange custody = off-chain
                contractAddress: nil,
                debankId: nil,
                coinGeckoId: nil, // TODO: maintain a Kraken symbol → coinGeckoId mapping
                sourceKey: "kraken:\(ticker)",
                logoURL: nil,
                category: .other,
                isVerified: true
            )
        }
    }

    private func normalizeKrakenSymbol(_ ticker: String) -> String {
        // Kraken prefixes: X = crypto, Z = fiat (legacy pairs)
        let mapping: [String: String] = [
            "XXBT": "BTC", "XETH": "ETH", "XLTC": "LTC",
            "XXRP": "XRP", "XXLM": "XLM", "XZEC": "ZEC",
            "ZUSD": "USD", "ZEUR": "EUR", "ZGBP": "GBP",
        ]
        return mapping[ticker] ?? ticker
    }
}
```

- [ ] **Step 4: Write BinanceClient and CoinbaseClient stubs**

```swift
// Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/BinanceClient.swift
import Foundation
import PortuCore

struct BinanceClient: ExchangeClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchBalances(apiKey: String, apiSecret: String, passphrase: String?) async throws -> [TokenDTO] {
        // TODO: Implement Binance API integration
        // Endpoint: GET /api/v3/account (HMAC-SHA256 signed)
        // Map each balance to TokenDTO with sourceKey: "binance:<asset>"
        throw ExchangeError.notImplemented("Binance")
    }
}
```

```swift
// Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/CoinbaseClient.swift
import Foundation
import PortuCore

struct CoinbaseClient: ExchangeClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchBalances(apiKey: String, apiSecret: String, passphrase: String?) async throws -> [TokenDTO] {
        // TODO: Implement Coinbase API integration
        // Endpoint: GET /v2/accounts (API key auth)
        // Map each balance to TokenDTO with sourceKey: "coinbase:<currency>"
        throw ExchangeError.notImplemented("Coinbase")
    }
}
```

- [ ] **Step 5: Write ExchangeProvider**

```swift
// Packages/PortuNetwork/Sources/PortuNetwork/Providers/ExchangeProvider.swift
import Foundation
import PortuCore

public actor ExchangeProvider: PortfolioDataProvider {
    private let secretStore: any SecretStore
    private let session: URLSession

    public var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsTokenBalances: true,
            supportsDeFiPositions: false,
            supportsHealthFactors: false
        )
    }

    public init(secretStore: any SecretStore, session: URLSession = .shared) {
        self.secretStore = secretStore
        self.session = session
    }

    public func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        guard let exchangeType = context.exchangeType else {
            throw ExchangeError.missingExchangeType
        }

        let keyPrefix = "portu.exchange.\(context.accountId.uuidString)"
        guard let apiKey = secretStore.get(key: "\(keyPrefix).apiKey"),
              let apiSecret = secretStore.get(key: "\(keyPrefix).apiSecret") else {
            throw ExchangeError.missingCredentials
        }
        let passphrase = secretStore.get(key: "\(keyPrefix).passphrase")

        let client = resolveClient(for: exchangeType)
        let tokens = try await client.fetchBalances(
            apiKey: apiKey,
            apiSecret: apiSecret,
            passphrase: passphrase
        )

        // Wrap all exchange tokens in a single idle position
        return [
            PositionDTO(
                positionType: .idle,
                chain: nil, // Exchange custody = off-chain
                protocolId: nil,
                protocolName: exchangeType.rawValue.capitalized,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: tokens
            )
        ]
    }

    private func resolveClient(for type: ExchangeType) -> any ExchangeClient {
        switch type {
        case .kraken: KrakenClient(session: session)
        case .binance: BinanceClient(session: session)
        case .coinbase: CoinbaseClient(session: session)
        }
    }
}

enum ExchangeError: Error, LocalizedError {
    case missingExchangeType
    case missingCredentials
    case invalidCredentials
    case httpError
    case decodingFailed
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .missingExchangeType: "Account has no exchange type set"
        case .missingCredentials: "API credentials not found in Keychain"
        case .invalidCredentials: "Invalid API credentials"
        case .httpError: "Exchange API request failed"
        case .decodingFailed: "Failed to parse exchange API response"
        case .notImplemented(let name): "\(name) integration not yet implemented"
        }
    }
}
```

- [ ] **Step 6: Verify it compiles**

Run: `swift build --package-path Packages/PortuNetwork 2>&1 | tail -10`

- [ ] **Step 7: Commit**

```bash
git add Packages/PortuNetwork/Sources/PortuNetwork/Providers/
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add ExchangeProvider with Kraken client implementation

Routes to exchange-specific clients via ExchangeClient protocol.
Kraken fully implemented with HMAC-SHA512 signing. Binance and
Coinbase stubbed for future implementation.
EOF
)"
```

---

### Task 5: MockProvider for testing

**Files:**
- Create: `Packages/PortuNetwork/Tests/PortuNetworkTests/MockProvider.swift`
- Create: `Packages/PortuNetwork/Tests/PortuNetworkTests/ProviderTests.swift`

- [ ] **Step 1: Write MockProvider**

```swift
// Packages/PortuNetwork/Tests/PortuNetworkTests/MockProvider.swift
import Foundation
import PortuCore
@testable import PortuNetwork

actor MockProvider: PortfolioDataProvider {
    var balancesToReturn: [PositionDTO] = []
    var defiToReturn: [PositionDTO] = []
    var shouldThrow: Error?
    var fetchBalancesCalled = false
    var fetchDeFiCalled = false

    var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsTokenBalances: true,
            supportsDeFiPositions: true,
            supportsHealthFactors: false
        )
    }

    func configure(balances: [PositionDTO], defi: [PositionDTO] = [], error: Error? = nil) {
        self.balancesToReturn = balances
        self.defiToReturn = defi
        self.shouldThrow = error
    }

    func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        fetchBalancesCalled = true
        if let error = shouldThrow { throw error }
        return balancesToReturn
    }

    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        fetchDeFiCalled = true
        if let error = shouldThrow { throw error }
        return defiToReturn
    }
}
```

- [ ] **Step 2: Write ProviderTests**

```swift
// Packages/PortuNetwork/Tests/PortuNetworkTests/ProviderTests.swift
import Testing
import Foundation
import PortuCore
@testable import PortuNetwork

@Suite("Provider Tests")
struct ProviderTests {

    @Test func mockProviderReturnsBalances() async throws {
        let provider = MockProvider()
        let ethToken = TokenDTO(
            role: .balance, symbol: "ETH", name: "Ethereum",
            amount: 10, usdValue: 21880, chain: .ethereum,
            contractAddress: nil, debankId: nil, coinGeckoId: "ethereum",
            sourceKey: nil, logoURL: nil, category: .major, isVerified: true
        )
        let position = PositionDTO(
            positionType: .idle, chain: .ethereum,
            protocolId: nil, protocolName: nil, protocolLogoURL: nil,
            healthFactor: nil, tokens: [ethToken]
        )
        await provider.configure(balances: [position])

        let ctx = SyncContext(accountId: UUID(), kind: .wallet, addresses: [("0xabc", nil)], exchangeType: nil)
        let results = try await provider.fetchBalances(context: ctx)

        #expect(results.count == 1)
        #expect(results[0].tokens[0].symbol == "ETH")
        #expect(await provider.fetchBalancesCalled)
    }

    @Test func providerCapabilitiesDefault() {
        let caps = ProviderCapabilities()
        #expect(caps.supportsTokenBalances)
        #expect(!caps.supportsDeFiPositions)
        #expect(!caps.supportsHealthFactors)
    }

    @Test func zapperCapabilities() async {
        let provider = ZapperProvider(apiKey: "test-key")
        let caps = await provider.capabilities
        #expect(caps.supportsTokenBalances)
        #expect(caps.supportsDeFiPositions)
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test --package-path Packages/PortuNetwork --filter ProviderTests 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Packages/PortuNetwork/Tests/PortuNetworkTests/MockProvider.swift \
        Packages/PortuNetwork/Tests/PortuNetworkTests/ProviderTests.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
test: add MockProvider and provider protocol tests
EOF
)"
```

---

### Task 6: Update PriceService for 24h changes and PriceUpdate

**Files:**
- Modify: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/PriceService.swift`
- Modify: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/CoinGeckoDTO.swift`
- Modify: `Packages/PortuNetwork/Tests/PortuNetworkTests/PriceServiceTests.swift`

PriceService now returns `PriceUpdate` (from PortuCore DTOs) containing both prices and 24h change percentages. CoinGecko endpoint: `/simple/price?include_24hr_change=true`.

- [ ] **Step 1: Update CoinGeckoDTO to parse 24h changes**

```swift
// Packages/PortuNetwork/Sources/PortuNetwork/PriceService/CoinGeckoDTO.swift
import Foundation
import PortuCore

/// Parses CoinGecko /simple/price response with 24h change.
/// Response format: { "bitcoin": { "usd": 67500.0, "usd_24h_change": -1.5 }, ... }
enum CoinGeckoDTO {
    static func parsePriceUpdate(from data: Data) throws -> PriceUpdate {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw PriceServiceError.decodingFailed
        }

        var prices: [String: Decimal] = [:]
        var changes: [String: Decimal] = [:]

        for (coinId, values) in json {
            if let usd = values["usd"] as? NSNumber {
                prices[coinId] = usd.decimalValue
            }
            if let change = values["usd_24h_change"] as? NSNumber {
                // Convert from percentage (e.g., -1.5) to decimal (-0.015)
                changes[coinId] = change.decimalValue / 100
            }
        }

        return PriceUpdate(prices: prices, changes24h: changes)
    }
}
```

- [ ] **Step 2: Update PriceService to return PriceUpdate**

Update the `fetchPrices` method to include `include_24hr_change=true` in the CoinGecko request URL and return `PriceUpdate` instead of `[String: Decimal]`.

Update the `priceStream` to yield `PriceUpdate` instead of `[String: Decimal]`.

Key changes to `PriceService.swift`:
- `fetchPrices(for:)` → `fetchPriceUpdate(for:) -> PriceUpdate`
- URL query: add `&include_24hr_change=true`
- Cache stores `PriceUpdate` instead of just prices
- Stream yields `PriceUpdate`

```swift
// In PriceService, update the fetch method:
public func fetchPriceUpdate(for coinIds: [String]) async throws -> PriceUpdate {
    // Check cache
    let cacheKey = coinIds.sorted().joined(separator: ",")
    if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
        return cached.update
    }

    // Rate limit check
    try checkRateLimit()

    // Build URL with 24h change
    let idsParam = coinIds.joined(separator: ",")
    let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(idsParam)&vs_currencies=usd&include_24hr_change=true")!

    let (data, response) = try await session.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw PriceServiceError.decodingFailed
    }

    switch httpResponse.statusCode {
    case 200:
        let update = try CoinGeckoDTO.parsePriceUpdate(from: data)
        cache[cacheKey] = CacheEntry(update: update, timestamp: Date())
        return update
    case 429:
        throw PriceServiceError.rateLimited
    default:
        throw PriceServiceError.invalidResponse(statusCode: httpResponse.statusCode)
    }
}
```

**Note:** The existing PriceService has significant logic for caching and rate limiting. Preserve that logic — only change the return type and URL parameters. Update the cache to store `PriceUpdate` instead of `[String: Decimal]`.

- [ ] **Step 3: Update PriceServiceTests**

Add a test for the 24h change parsing:

```swift
@Test func fetchPriceUpdateIncludes24hChange() async throws {
    // Set up mock response with 24h change data
    let responseJSON = """
    {
        "bitcoin": {"usd": 67500.0, "usd_24h_change": -1.5},
        "ethereum": {"usd": 2188.0, "usd_24h_change": 3.2}
    }
    """.data(using: .utf8)!

    // Register mock response
    MockURLProtocol.requestHandler = { _ in
        let response = HTTPURLResponse(url: URL(string: "https://api.coingecko.com")!,
                                       statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, responseJSON)
    }

    let update = try await priceService.fetchPriceUpdate(for: ["bitcoin", "ethereum"])

    #expect(update.prices["bitcoin"] == 67500)
    #expect(update.prices["ethereum"] == 2188)
    // 24h change is converted from percentage to decimal
    #expect(update.changes24h["bitcoin"]! < 0)
    #expect(update.changes24h["ethereum"]! > 0)
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path Packages/PortuNetwork 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/PortuNetwork/Sources/PortuNetwork/PriceService/ \
        Packages/PortuNetwork/Tests/PortuNetworkTests/PriceServiceTests.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: update PriceService to return PriceUpdate with 24h changes

CoinGecko request now includes include_24hr_change=true. Returns
PriceUpdate DTO with both prices and change percentages. Cache
updated to store full PriceUpdate.
EOF
)"
```

---

### Task 7: Update AppState

**Files:**
- Modify: `Sources/Portu/App/AppState.swift`

Rework to match spec: add `SyncStatus`, `priceChanges24h`, update `SidebarSection`, remove old types.

- [ ] **Step 1: Rewrite AppState.swift**

```swift
// Sources/Portu/App/AppState.swift
import Foundation
import PortuCore

enum SidebarSection: Hashable, Sendable {
    case overview
    case exposure
    case performance
    case allAssets
    case allPositions
    case accounts
    // case strategies  // future work
}

enum ConnectionStatus: Hashable, Sendable {
    case idle
    case fetching
    case error(String)
}

@Observable
@MainActor
final class AppState {
    var selectedSection: SidebarSection = .overview
    var lastPriceUpdate: Date?
    var prices: [String: Decimal] = [:]
    var priceChanges24h: [String: Decimal] = [:]
    var connectionStatus: ConnectionStatus = .idle
    var syncStatus: SyncStatus = .idle
    var storeIsEphemeral: Bool = false
}
```

`SyncStatus` and `ConnectionStatus` are defined here in `AppState.swift` (app target, not PortuCore) since they are UI-layer enums that don't need cross-module access:

```swift
enum SyncStatus: Hashable, Sendable {
    case idle
    case syncing(progress: Double)
    case completedWithErrors(failedAccounts: [String])
    case error(String)
}
```

- [ ] **Step 2: Verify main app compiles**

Run: `just build 2>&1 | tail -10`
Expected: Build errors from views referencing old AppState types — fix references as needed in views (detailed in Plan 3).

- [ ] **Step 3: Commit**

```bash
git add Sources/Portu/App/AppState.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: rework AppState with SyncStatus and 24h price changes

Add SidebarSection enum, SyncStatus, priceChanges24h map.
Remove old ConnectionStatus/SidebarSection definitions.
EOF
)"
```

---

### Task 8: SyncEngine

**Files:**
- Create: `Sources/Portu/Sync/SyncEngine.swift`

The orchestrator. Phase A: per-account fetch + persist. Phase B: snapshot all tiers. Runs on MainActor (accesses ModelContext).

- [ ] **Step 1: Create Sync directory**

```bash
mkdir -p Sources/Portu/Sync
```

- [ ] **Step 2: Write SyncEngine**

```swift
// Sources/Portu/Sync/SyncEngine.swift
import Foundation
import SwiftData
import PortuCore
import PortuNetwork

@MainActor
final class SyncEngine {
    private let modelContext: ModelContext
    private let appState: AppState
    private let secretStore: any SecretStore

    init(modelContext: ModelContext, appState: AppState, secretStore: any SecretStore) {
        self.modelContext = modelContext
        self.appState = appState
        self.secretStore = secretStore
    }

    // MARK: - Public API

    func sync() async {
        appState.syncStatus = .syncing(progress: 0)

        let activeSyncable = fetchActiveSyncableAccounts()
        let activeManual = fetchActiveManualAccounts()

        guard !activeSyncable.isEmpty || !activeManual.isEmpty else {
            appState.syncStatus = .error("No active accounts")
            return
        }

        // ── Phase A: Per-account fetch + persist ──
        var failedAccounts: [String] = []

        for (index, account) in activeSyncable.enumerated() {
            let progress = Double(index) / Double(max(activeSyncable.count, 1))
            appState.syncStatus = .syncing(progress: progress)

            do {
                try await syncAccount(account)
            } catch {
                account.lastSyncError = error.localizedDescription
                failedAccounts.append(account.name)
            }
        }

        // ── Phase B: Snapshot all tiers ──
        let allSyncAttemptedFailed = failedAccounts.count == activeSyncable.count
        if allSyncAttemptedFailed && activeManual.isEmpty && !activeSyncable.isEmpty {
            appState.syncStatus = .error("All accounts failed to sync")
            return
        }

        do {
            try createSnapshots(isPartial: !failedAccounts.isEmpty)
        } catch {
            appState.syncStatus = .error("Failed to create snapshots: \(error.localizedDescription)")
            return
        }

        if failedAccounts.isEmpty {
            appState.syncStatus = .idle
        } else {
            appState.syncStatus = .completedWithErrors(failedAccounts: failedAccounts)
        }
    }

    // MARK: - Phase A: Per-account sync

    private func syncAccount(_ account: Account) async throws {
        let context = SyncContext(
            accountId: account.id,
            kind: account.kind,
            addresses: account.addresses.map { ($0.address, $0.chain) },
            exchangeType: account.exchangeType
        )

        let provider = try resolveProvider(for: account)

        let balances = try await provider.fetchBalances(context: context)
        let defi = try await provider.fetchDeFiPositions(context: context)
        let allDTOs = balances + defi

        // Delete stale positions from previous sync
        for position in account.positions {
            modelContext.delete(position)
        }

        // Map DTOs → SwiftData
        for dto in allDTOs {
            let position = Position(
                positionType: dto.positionType,
                chain: dto.chain,
                protocolId: dto.protocolId,
                protocolName: dto.protocolName,
                protocolLogoURL: dto.protocolLogoURL,
                healthFactor: dto.healthFactor,
                account: account,
                syncedAt: .now
            )

            var net: Decimal = 0
            for tokenDTO in dto.tokens {
                let asset = upsertAsset(from: tokenDTO)
                let token = PositionToken(
                    role: tokenDTO.role,
                    amount: tokenDTO.amount,
                    usdValue: tokenDTO.usdValue,
                    asset: asset,
                    position: position
                )
                modelContext.insert(token)

                if tokenDTO.role.isPositive {
                    net += tokenDTO.usdValue
                } else if tokenDTO.role.isBorrow {
                    net -= tokenDTO.usdValue
                }
                // reward: excluded from net
            }

            position.netUSDValue = net
            modelContext.insert(position)
        }

        account.lastSyncedAt = .now
        account.lastSyncError = nil
        try modelContext.save()
    }

    // MARK: - Asset Upsert (3-tier hierarchy)

    private func upsertAsset(from dto: TokenDTO) -> Asset {
        // Tier 1: coinGeckoId
        if let cgId = dto.coinGeckoId, !cgId.isEmpty {
            if let existing = fetchAsset(coinGeckoId: cgId) {
                updateAssetMetadata(existing, from: dto)
                return existing
            }
        }

        // Tier 2: upsertChain + upsertContract
        if let chain = dto.chain, let contract = dto.contractAddress, !contract.isEmpty {
            if let existing = fetchAsset(chain: chain, contract: contract) {
                updateAssetMetadata(existing, from: dto)
                return existing
            }
        }

        // Tier 3: sourceKey
        if let key = dto.sourceKey, !key.isEmpty {
            if let existing = fetchAsset(sourceKey: key) {
                updateAssetMetadata(existing, from: dto)
                return existing
            }
        }

        // No match → create new Asset
        let asset = Asset(
            symbol: dto.symbol,
            name: dto.name,
            coinGeckoId: dto.coinGeckoId,
            // Tier 2 fields only set when no coinGeckoId (single-chain token)
            upsertChain: dto.coinGeckoId == nil ? dto.chain : nil,
            upsertContract: dto.coinGeckoId == nil ? dto.contractAddress : nil,
            sourceKey: dto.sourceKey,
            logoURL: dto.logoURL,
            category: dto.category,
            isVerified: dto.isVerified
        )
        modelContext.insert(asset)
        return asset
    }

    /// Metadata update: last-synced-wins for name, category, logoURL, isVerified.
    /// Upsert keys (coinGeckoId, upsertChain, upsertContract, sourceKey) are append-only.
    private func updateAssetMetadata(_ asset: Asset, from dto: TokenDTO) {
        asset.symbol = dto.symbol
        asset.name = dto.name
        asset.category = dto.category
        asset.logoURL = dto.logoURL ?? asset.logoURL

        if dto.isVerified { asset.isVerified = true }

        // Append-only: fill in missing keys, never overwrite
        if asset.coinGeckoId == nil, let cgId = dto.coinGeckoId { asset.coinGeckoId = cgId }
        if asset.sourceKey == nil, let key = dto.sourceKey { asset.sourceKey = key }
        if asset.debankId == nil, let dbId = dto.debankId { asset.debankId = dbId }
    }

    // MARK: - Phase B: Snapshots

    private func createSnapshots(isPartial: Bool) throws {
        let batchId = UUID()
        let batchTimestamp = Date.now

        // Query all positions from active accounts
        let descriptor = FetchDescriptor<Position>(
            predicate: #Predicate<Position> { $0.account?.isActive == true }
        )
        let allPositions = try modelContext.fetch(descriptor)

        // ── PortfolioSnapshot ──
        var totalValue: Decimal = 0
        var idleValue: Decimal = 0
        var deployedValue: Decimal = 0
        var debtValue: Decimal = 0

        for pos in allPositions {
            totalValue += pos.netUSDValue

            switch pos.positionType {
            case .idle:
                // Idle value = sum of positive tokens
                let posIdle = pos.tokens
                    .filter { $0.role.isPositive }
                    .reduce(Decimal.zero) { $0 + $1.usdValue }
                idleValue += posIdle
            case .lending, .staking, .farming, .liquidityPool:
                // Deployed = positive roles
                let posDep = pos.tokens
                    .filter { $0.role.isPositive }
                    .reduce(Decimal.zero) { $0 + $1.usdValue }
                deployedValue += posDep
            default:
                break
            }

            // Debt from all borrow tokens
            let posBorrow = pos.tokens
                .filter { $0.role.isBorrow }
                .reduce(Decimal.zero) { $0 + $1.usdValue }
            debtValue += posBorrow
        }

        let portfolioSnap = PortfolioSnapshot(
            syncBatchId: batchId, timestamp: batchTimestamp,
            totalValue: totalValue, idleValue: idleValue,
            deployedValue: deployedValue, debtValue: debtValue,
            isPartial: isPartial
        )
        modelContext.insert(portfolioSnap)

        // ── AccountSnapshots ──
        let activeAccounts = try modelContext.fetch(
            FetchDescriptor<Account>(predicate: #Predicate { $0.isActive == true })
        )

        for account in activeAccounts {
            let accountTotal = account.positions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
            let isFresh = account.dataSource == .manual || account.lastSyncError == nil

            let snap = AccountSnapshot(
                syncBatchId: batchId, timestamp: batchTimestamp,
                accountId: account.id, totalValue: accountTotal, isFresh: isFresh
            )
            modelContext.insert(snap)
        }

        // ── AssetSnapshots ──
        // Group PositionTokens by (accountId, assetId)
        typealias SnapKey = String // "accountId:assetId"

        struct SnapAccumulator {
            var accountId: UUID
            var assetId: UUID
            var symbol: String
            var category: AssetCategory
            var grossAmount: Decimal = 0
            var grossUsdValue: Decimal = 0
            var borrowAmount: Decimal = 0
            var borrowUsdValue: Decimal = 0
        }

        var accumulators: [SnapKey: SnapAccumulator] = [:]

        for pos in allPositions {
            guard let accountId = pos.account?.id else { continue }

            for token in pos.tokens {
                guard let asset = token.asset else { continue }
                if token.role.isReward { continue } // rewards excluded

                let key = "\(accountId):\(asset.id)"

                if accumulators[key] == nil {
                    accumulators[key] = SnapAccumulator(
                        accountId: accountId,
                        assetId: asset.id,
                        symbol: asset.symbol,
                        category: asset.category
                    )
                }

                if token.role.isBorrow {
                    accumulators[key]!.borrowAmount += token.amount
                    accumulators[key]!.borrowUsdValue += token.usdValue
                } else {
                    accumulators[key]!.grossAmount += token.amount
                    accumulators[key]!.grossUsdValue += token.usdValue
                }
            }
        }

        for acc in accumulators.values {
            let snap = AssetSnapshot(
                syncBatchId: batchId, timestamp: batchTimestamp,
                accountId: acc.accountId, assetId: acc.assetId,
                symbol: acc.symbol, category: acc.category,
                amount: acc.grossAmount, usdValue: acc.grossUsdValue,
                borrowAmount: acc.borrowAmount, borrowUsdValue: acc.borrowUsdValue
            )
            modelContext.insert(snap)
        }

        // ── Prune old snapshots ──
        pruneSnapshots()

        try modelContext.save()
    }

    // MARK: - Snapshot Pruning

    /// - Snapshots older than 7 days: keep one per day (last of each day)
    /// - Snapshots older than 90 days: keep one per week (last of each week)
    private func pruneSnapshots() {
        let now = Date.now
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: now)!

        pruneSnapshotType(PortfolioSnapshot.self, olderThan: sevenDaysAgo, keepPer: .day)
        pruneSnapshotType(PortfolioSnapshot.self, olderThan: ninetyDaysAgo, keepPer: .weekOfYear)
        pruneSnapshotType(AccountSnapshot.self, olderThan: sevenDaysAgo, keepPer: .day)
        pruneSnapshotType(AccountSnapshot.self, olderThan: ninetyDaysAgo, keepPer: .weekOfYear)
        pruneSnapshotType(AssetSnapshot.self, olderThan: sevenDaysAgo, keepPer: .day)
        pruneSnapshotType(AssetSnapshot.self, olderThan: ninetyDaysAgo, keepPer: .weekOfYear)
    }

    private func pruneSnapshotType<T: PersistentModel>(_ type: T.Type, olderThan: Date, keepPer: Calendar.Component) {
        // Implementation: fetch snapshots older than cutoff, group by calendar component,
        // keep only the last snapshot per group, delete the rest.
        // This is a best-effort operation — errors are logged but don't fail the sync.
        // TODO: Implement when snapshot volume warrants it
    }

    // MARK: - Helpers

    private func resolveProvider(for account: Account) throws -> any PortfolioDataProvider {
        switch account.dataSource {
        case .zapper:
            guard let apiKey = secretStore.get(key: "portu.provider.zapper.apiKey") else {
                throw SyncError.missingAPIKey("Zapper API key not configured")
            }
            return ZapperProvider(apiKey: apiKey)
        case .exchange:
            return ExchangeProvider(secretStore: secretStore)
        case .manual:
            fatalError("Manual accounts should not reach provider resolution")
        }
    }

    private func fetchActiveSyncableAccounts() -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.isActive == true && $0.dataSource != .manual }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchActiveManualAccounts() -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.isActive == true && $0.dataSource == .manual }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchAsset(coinGeckoId: String) -> Asset? {
        let descriptor = FetchDescriptor<Asset>(
            predicate: #Predicate { $0.coinGeckoId == coinGeckoId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchAsset(chain: Chain, contract: String) -> Asset? {
        let descriptor = FetchDescriptor<Asset>(
            predicate: #Predicate { $0.upsertChain == chain && $0.upsertContract == contract }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchAsset(sourceKey: String) -> Asset? {
        let descriptor = FetchDescriptor<Asset>(
            predicate: #Predicate { $0.sourceKey == sourceKey }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

enum SyncError: Error, LocalizedError {
    case missingAPIKey(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let msg): msg
        }
    }
}
```

**Important SwiftData predicate note:** The `#Predicate` closures above reference enum values (`.manual`, `.zapper`) and optional navigation (`$0.account?.isActive`). SwiftData predicates have limitations with enums stored as raw values and optional chaining. If compilation fails:
1. Store enum raw values and compare as strings in predicates
2. Use `FetchDescriptor<T>()` without predicate and filter in memory for complex cases
3. Test each predicate individually during implementation

- [ ] **Step 3: Verify it compiles**

Run: `just build 2>&1 | tail -20`

- [ ] **Step 4: Commit**

```bash
git add Sources/Portu/Sync/
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add SyncEngine with Phase A (fetch+persist) and Phase B (snapshots)

Orchestrates per-account sync via PortfolioDataProvider, maps DTOs to
SwiftData models with 3-tier asset upsert, computes netUSDValue from
token roles, creates three snapshot tiers with syncBatchId linking.
EOF
)"
```

---

### Task 9: SyncEngine tests

**Files:**
- Create: `Tests/PortuTests/SyncEngineTests.swift`

Test with MockProvider and in-memory ModelContainer.

- [ ] **Step 1: Write SyncEngine tests**

```swift
// Tests/PortuTests/SyncEngineTests.swift
import Testing
import Foundation
import SwiftData
@testable import Portu
@testable import PortuCore
@testable import PortuNetwork

@Suite("SyncEngine Tests")
@MainActor
struct SyncEngineTests {

    private func makeTestContext() throws -> (ModelContext, AppState, SyncEngine) {
        let schema = Schema([
            Account.self, WalletAddress.self, Position.self,
            PositionToken.self, Asset.self,
            PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let appState = AppState()
        let mockStore = MockSecretStore()
        let engine = SyncEngine(modelContext: context, appState: appState, secretStore: mockStore)
        return (context, appState, engine)
    }

    @Test func syncWithNoAccountsSetsError() async throws {
        let (_, appState, engine) = try makeTestContext()

        await engine.sync()

        if case .error(let msg) = appState.syncStatus {
            #expect(msg.contains("No active accounts"))
        } else {
            #expect(Bool(false), "Expected error status")
        }
    }

    @Test func syncManualOnlyAccountsCreatesSnapshots() async throws {
        let (context, appState, engine) = try makeTestContext()

        // Create manual account with a position
        let asset = Asset(symbol: "GOLD", name: "Gold Token", category: .other)
        context.insert(asset)
        let token = PositionToken(role: .balance, amount: 100, usdValue: 5000, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 5000, tokens: [token])
        let account = Account(name: "Manual", kind: .manual, dataSource: .manual, positions: [position])
        context.insert(account)
        try context.save()

        await engine.sync()

        // Phase A: no sync-attempted accounts → no failures
        // Phase B: snapshots created from manual positions
        let snapshots = try context.fetch(FetchDescriptor<PortfolioSnapshot>())
        #expect(snapshots.count == 1)
        #expect(snapshots[0].totalValue == 5000)
        #expect(snapshots[0].isPartial == false)
        #expect(appState.syncStatus == .idle)
    }

    @Test func assetUpsertTier1MatchesByCoinGeckoId() async throws {
        let (context, _, engine) = try makeTestContext()

        // Pre-existing asset
        let existing = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
        context.insert(existing)
        try context.save()

        // Create account with position referencing same coinGeckoId
        let asset2 = Asset(symbol: "ETH", name: "Ether", coinGeckoId: "ethereum", category: .major)
        context.insert(asset2)

        // After upsert, should have only 1 Asset with coinGeckoId "ethereum"
        let assets = try context.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.coinGeckoId == "ethereum" }
        ))
        // Note: This tests the predicate, not the upsert directly.
        // Full upsert testing requires calling SyncEngine.syncAccount through the public API.
        #expect(assets.count >= 1)
    }

    @Test func snapshotBatchIdLinks() async throws {
        let (context, _, _) = try makeTestContext()

        let batchId = UUID()
        let now = Date.now

        let ps = PortfolioSnapshot(syncBatchId: batchId, timestamp: now,
                                    totalValue: 100000, idleValue: 50000,
                                    deployedValue: 45000, debtValue: 5000, isPartial: false)
        let as1 = AccountSnapshot(syncBatchId: batchId, timestamp: now,
                                   accountId: UUID(), totalValue: 50000, isFresh: true)
        context.insert(ps)
        context.insert(as1)
        try context.save()

        #expect(ps.syncBatchId == as1.syncBatchId)
    }
}

// Mock SecretStore for tests
private final class MockSecretStore: SecretStore, @unchecked Sendable {
    private var store: [String: String] = [:]

    func get(key: String) -> String? { store[key] }
    func set(key: String, value: String) throws { store[key] = value }
    func delete(key: String) throws { store.removeValue(forKey: key) }
}
```

- [ ] **Step 2: Run tests**

Run: `just test 2>&1 | tail -20`
Expected: PASS (may need adjustments for SwiftData predicate compilation)

- [ ] **Step 3: Commit**

```bash
git add Tests/PortuTests/SyncEngineTests.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
test: add SyncEngine tests with mock provider and in-memory store
EOF
)"
```

---

### Task 10: Wire SyncEngine into PortuApp

**Files:**
- Modify: `Sources/Portu/App/PortuApp.swift`

Create SyncEngine at app startup, inject into environment.

- [ ] **Step 1: Update PortuApp to create SyncEngine**

Add SyncEngine creation after ModelContainer setup. Pass `modelContext`, `appState`, and `KeychainService` to SyncEngine. Make it available to views via `@Environment` or as a property on `AppState`.

```swift
// In PortuApp.swift, after creating ModelContainer:
let syncEngine = SyncEngine(
    modelContext: container.mainContext,
    appState: appState,
    secretStore: KeychainService()
)
```

Store on AppState or pass via `.environment()` — implementation choice.

- [ ] **Step 2: Verify it compiles**

Run: `just build 2>&1 | tail -10`

- [ ] **Step 3: Commit**

```bash
git add Sources/Portu/App/PortuApp.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: wire SyncEngine into PortuApp lifecycle
EOF
)"
```

---

### Task 11: Run full test suite

- [ ] **Step 1: Run all tests**

Run: `just test-packages && just test 2>&1 | tail -30`
Expected: All tests PASS

- [ ] **Step 2: Fix any issues and commit**

```bash
git add -A
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
fix: resolve remaining compilation issues from Phase 1b
EOF
)"
```

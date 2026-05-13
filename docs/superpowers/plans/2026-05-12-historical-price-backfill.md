# Historical Price Backfill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add manual CoinGecko historical price backfill while keeping Portu snapshots authoritative and estimated chart data visually separate.

**Architecture:** Store CoinGecko historical prices in a separate SwiftData cache model owned by `PortuCore`. Fetch and parse historical market chart data in `PortuNetwork`, then orchestrate candidate selection, cache writes, Settings state, and chart derivation in the app target. Real chart data continues to come from `PortfolioSnapshot`, `AccountSnapshot`, and `AssetSnapshot`; estimated data is derived at render time and never saved as snapshot rows.

**Tech Stack:** Swift 6.2, SwiftData, SwiftUI, TCA, Swift Charts, Swift Testing, XcodeGen, CoinGecko API.

---

## File Structure

Create:

- `Packages/PortuCore/Sources/PortuCore/Models/HistoricalPricePoint.swift`
  - SwiftData cache row for one CoinGecko USD price on one UTC day.
- `Packages/PortuCore/Sources/PortuCore/DTOs/HistoricalPriceDTO.swift`
  - Sendable network/cache transfer values.
- `Sources/Portu/Features/Settings/HistoricalPriceBackfillSettings.swift`
  - AppStorage keys and user-facing labels for historical backfill.
- `Sources/Portu/Features/Settings/HistoricalPriceBackfillClient.swift`
  - TCA dependency that runs manual backfill and clears cache.
- `Sources/Portu/Features/Settings/HistoricalPriceBackfillFeature.swift`
  - State, actions, result types, candidate resolver, cache writer, and reducer.
- `Sources/Portu/Features/Shared/HistoricalPortfolioEstimator.swift`
  - Pure chart derivation for estimated pre-snapshot values.
- `Tests/PortuTests/HistoricalPriceBackfillFeatureTests.swift`
  - Candidate selection, cache writer, reducer state tests.
- `Tests/PortuTests/HistoricalPortfolioEstimatorTests.swift`
  - Estimated chart data tests.

Modify:

- `Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift`
  - Historical price model and schema tests.
- `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/CoinGeckoDTO.swift`
  - Market chart parser.
- `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/PriceService.swift`
  - Historical price fetch method and optional CoinGecko API key header.
- `Packages/PortuNetwork/Tests/PortuNetworkTests/PriceServiceTests.swift`
  - Historical fetch URL, parse, malformed payload, and 429 tests.
- `Sources/Portu/App/ModelContainerFactory.swift`
  - Add `HistoricalPricePoint.self` to the app schema.
- `Sources/Portu/App/AppFeature.swift`
  - Add backfill dependency, child state/actions, reducer effects, and `PriceServiceClient.fetchHistoricalPrices`.
- `Sources/Portu/App/ContentView.swift`
  - Pass `store` into Settings.
- `Sources/Portu/App/PortuApp.swift`
  - Configure `PriceService` with a CoinGecko API key provider and configure the backfill client.
- `Sources/Portu/Features/Settings/SettingsView.swift`
  - Add store-aware Settings plumbing and Historical Prices UI in General.
- `Sources/Portu/Features/Overview/PortfolioValueChart.swift`
  - Render estimated pre-snapshot values when enabled.
- `Sources/Portu/Features/Performance/ValueChartMode.swift`
  - Render estimated pre-snapshot values for all-account and account-scoped value charts.
- `Sources/Portu/Features/Performance/PerformanceBottomPanel.swift`
  - Show top asset period price changes from cached historical prices.
- `Sources/Portu/Features/Performance/PerformanceFeature.swift`
  - Pure helper for period price changes.
- `Sources/Portu/Features/AssetDetail/AssetPriceChart.swift`
  - Replace the current empty price chart branch with cached historical price chart data.
- `Tests/PortuTests/AppFeatureTests.swift`
  - Backfill reducer tests.
- `Tests/PortuTests/SettingsTabTests.swift`
  - Historical settings labels and persistence tests.
- `Tests/PortuTests/ViewRenderSmokeTests.swift`
  - Add `HistoricalPricePoint.self` to any explicit schemas.
- `Tests/PortuTests/AssetPriceChartTests.swift`
  - Add `HistoricalPricePoint.self` to explicit schemas and price chart query tests.
- `Tests/PortuTests/DebugEndpointsTests.swift`
  - Add `HistoricalPricePoint.self` to explicit schemas.
- `Tests/PortuTests/SyncEngineTests.swift`
  - Add `HistoricalPricePoint.self` to explicit schemas.

After adding app-target files, run `just generate` before Xcode builds because the Xcode project is generated from `project.yml`.

---

## Task 1: Core Historical Price Cache Model

**Files:**

- Create: `Packages/PortuCore/Sources/PortuCore/Models/HistoricalPricePoint.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/DTOs/HistoricalPriceDTO.swift`
- Modify: `Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift`
- Modify: `Sources/Portu/App/ModelContainerFactory.swift`
- Modify explicit test schemas listed in the file structure section.

- [ ] **Step 1: Write the failing model tests**

Add these tests to `Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift`. Also add `HistoricalPricePoint.self` to `makeTestContainer()` only after the first failure is confirmed.

```swift
@Test func `historical price point stores utc day cache data`() throws {
    let container = try makeTestContainer()
    let context = container.mainContext
    let rawDate = Date(timeIntervalSince1970: 1_704_110_456)
    let fetchedAt = Date(timeIntervalSince1970: 1_704_200_000)

    let point = HistoricalPricePoint(
        coinGeckoId: "bitcoin",
        day: rawDate,
        usdPrice: Decimal(string: "43123.45")!,
        fetchedAt: fetchedAt)

    context.insert(point)
    try context.save()

    let fetched = try #require(try context.fetch(FetchDescriptor<HistoricalPricePoint>()).first)
    #expect(fetched.coinGeckoId == "bitcoin")
    #expect(fetched.day == HistoricalPriceCalendar.utcStartOfDay(for: rawDate))
    #expect(fetched.usdPrice == Decimal(string: "43123.45")!)
    #expect(fetched.source == .coingecko)
    #expect(fetched.fetchedAt == fetchedAt)
}

@Test func `historical price dto is sendable and normalizes day`() {
    let rawDate = Date(timeIntervalSince1970: 1_704_110_456)
    let dto = HistoricalPriceDTO(
        coinGeckoId: "ethereum",
        timestamp: rawDate,
        usdPrice: 2500)

    let sendable: any Sendable = dto
    #expect(sendable is HistoricalPriceDTO)
    #expect(dto.day == HistoricalPriceCalendar.utcStartOfDay(for: rawDate))
}
```

- [ ] **Step 2: Run the focused failing test**

Run:

```bash
swift test --package-path Packages/PortuCore --filter "historical price point stores utc day cache data"
```

Expected: FAIL because `HistoricalPricePoint` does not exist.

- [ ] **Step 3: Add the DTO file**

Create `Packages/PortuCore/Sources/PortuCore/DTOs/HistoricalPriceDTO.swift`:

```swift
import Foundation

public enum HistoricalPriceCalendar {
    public static func utcStartOfDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.startOfDay(for: date)
    }
}

public struct HistoricalPriceDTO: Sendable, Equatable {
    public let coinGeckoId: String
    public let timestamp: Date
    public let day: Date
    public let usdPrice: Decimal

    public init(
        coinGeckoId: String,
        timestamp: Date,
        usdPrice: Decimal) {
        self.coinGeckoId = coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.timestamp = timestamp
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: timestamp)
        self.usdPrice = usdPrice
    }
}
```

- [ ] **Step 4: Add the SwiftData model**

Create `Packages/PortuCore/Sources/PortuCore/Models/HistoricalPricePoint.swift`:

```swift
import Foundation
import SwiftData

public enum HistoricalPriceSource: String, Codable, Sendable, Equatable {
    case coingecko
}

@Model
public final class HistoricalPricePoint {
    @Attribute(.unique) public var id: UUID
    public var coinGeckoId: String
    public var day: Date
    public var usdPrice: Decimal
    public var source: HistoricalPriceSource
    public var fetchedAt: Date

    public init(
        id: UUID = UUID(),
        coinGeckoId: String,
        day: Date,
        usdPrice: Decimal,
        source: HistoricalPriceSource = .coingecko,
        fetchedAt: Date = .now) {
        self.id = id
        self.coinGeckoId = coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: day)
        self.usdPrice = usdPrice
        self.source = source
        self.fetchedAt = fetchedAt
    }

    public convenience init(dto: HistoricalPriceDTO, fetchedAt: Date = .now) {
        self.init(
            coinGeckoId: dto.coinGeckoId,
            day: dto.day,
            usdPrice: dto.usdPrice,
            source: .coingecko,
            fetchedAt: fetchedAt)
    }
}
```

- [ ] **Step 5: Add the model to every explicit SwiftData schema**

Add `HistoricalPricePoint.self` immediately after `TokenPricingOverride.self` in:

```swift
Schema([
    Account.self,
    WalletAddress.self,
    Position.self,
    PositionToken.self,
    Asset.self,
    TokenPricingOverride.self,
    HistoricalPricePoint.self,
    PortfolioCategory.self,
    CategorySymbolRule.self,
    PortfolioSnapshot.self,
    AccountSnapshot.self,
    AssetSnapshot.self
])
```

Update all explicit schemas named in the file structure section. Keep files without `PortfolioCategory.self` in their existing shape and only insert `HistoricalPricePoint.self` after `TokenPricingOverride.self`.

- [ ] **Step 6: Run the focused tests**

Run:

```bash
swift test --package-path Packages/PortuCore --filter "historical price"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/Models/HistoricalPricePoint.swift \
  Packages/PortuCore/Sources/PortuCore/DTOs/HistoricalPriceDTO.swift \
  Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift \
  Sources/Portu/App/ModelContainerFactory.swift \
  Tests/PortuTests/DebugEndpointsTests.swift \
  Tests/PortuTests/SyncEngineTests.swift \
  Tests/PortuTests/ViewRenderSmokeTests.swift \
  Tests/PortuTests/AssetPriceChartTests.swift
git commit -m "feat: add historical price cache model"
```

---

## Task 2: CoinGecko Historical Price Fetching

**Files:**

- Modify: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/CoinGeckoDTO.swift`
- Modify: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/PriceService.swift`
- Modify: `Packages/PortuNetwork/Tests/PortuNetworkTests/PriceServiceTests.swift`
- Modify: `Sources/Portu/App/AppFeature.swift`
- Modify: `Sources/Portu/App/PortuApp.swift`

- [ ] **Step 1: Write failing network tests**

Add these tests to `Packages/PortuNetwork/Tests/PortuNetworkTests/PriceServiceTests.swift`:

```swift
@Test func `fetch historical prices builds market chart request and dedupes by utc day`() async throws {
    var capturedURL: URL?
    MockURLProtocol.requestHandler = { request in
        capturedURL = request.url
        return ("""
        {
          "prices": [
            [1704067200000, 42000.25],
            [1704150000000, 43000.50],
            [1704153600000, 43100.75]
          ],
          "market_caps": [],
          "total_volumes": []
        }
        """.data(using: .utf8), 200)
    }

    let service = PriceService(session: session, cacheTTL: 0)
    let prices = try await service.fetchHistoricalPrices(for: " Bitcoin ", days: 365)

    #expect(capturedURL?.path == "/api/v3/coins/bitcoin/market_chart")
    let query = try #require(URLComponents(url: #require(capturedURL), resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "vs_currency", value: "usd")))
    #expect(query.contains(URLQueryItem(name: "days", value: "365")))
    #expect(prices.map(\.coinGeckoId) == ["bitcoin", "bitcoin"])
    #expect(prices.map(\.usdPrice) == [Decimal(string: "42000.25")!, Decimal(string: "43100.75")!])
}

@Test func `fetch historical prices rejects malformed payload`() async {
    MockURLProtocol.requestHandler = { _ in
        ("{\"prices\":[[\"bad\", 42]]}".data(using: .utf8), 200)
    }

    let service = PriceService(session: session, cacheTTL: 0)
    await #expect(throws: PriceServiceError.decodingFailed) {
        try await service.fetchHistoricalPrices(for: "bitcoin", days: 365)
    }
}

@Test func `fetch historical prices maps http 429 to rate limited`() async {
    MockURLProtocol.requestHandler = { _ in (nil, 429) }

    let service = PriceService(session: session, cacheTTL: 0)
    await #expect(throws: PriceServiceError.rateLimited) {
        try await service.fetchHistoricalPrices(for: "bitcoin", days: 365)
    }
}

@Test func `fetch historical prices sends demo api key header when provider returns a key`() async throws {
    var header: String?
    MockURLProtocol.requestHandler = { request in
        header = request.value(forHTTPHeaderField: "x-cg-demo-api-key")
        return ("{\"prices\":[]}".data(using: .utf8), 200)
    }

    let service = PriceService(
        session: session,
        cacheTTL: 0,
        coinGeckoAPIKey: { "demo-key" })
    _ = try await service.fetchHistoricalPrices(for: "bitcoin", days: 365)

    #expect(header == "demo-key")
}
```

- [ ] **Step 2: Run the failing network tests**

Run:

```bash
swift test --package-path Packages/PortuNetwork --filter "historical prices"
```

Expected: FAIL because `fetchHistoricalPrices` and `coinGeckoAPIKey` do not exist.

- [ ] **Step 3: Add market chart parsing**

Add this type to `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/CoinGeckoDTO.swift`:

```swift
nonisolated struct CoinGeckoMarketChartResponse {
    let prices: [HistoricalPriceDTO]

    init(coinGeckoId: String, data: Data) throws(PriceServiceError) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = json["prices"] as? [[Any]]
        else {
            throw .decodingFailed
        }

        var latestByDay: [Date: HistoricalPriceDTO] = [:]
        for row in rows {
            guard
                row.count >= 2,
                let timestampNumber = row[0] as? NSNumber,
                let priceNumber = row[1] as? NSNumber
            else {
                throw .decodingFailed
            }
            let timestamp = Date(timeIntervalSince1970: timestampNumber.doubleValue / 1000)
            let dto = HistoricalPriceDTO(
                coinGeckoId: coinGeckoId,
                timestamp: timestamp,
                usdPrice: priceNumber.decimalValue)
            if let existing = latestByDay[dto.day], existing.timestamp >= dto.timestamp {
                continue
            }
            latestByDay[dto.day] = dto
        }

        self.prices = latestByDay.values.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            return $0.timestamp < $1.timestamp
        }
    }
}
```

- [ ] **Step 4: Add optional API key support and historical fetch to `PriceService`**

Change the `PriceService` stored properties and initializer:

```swift
private let coinGeckoAPIKey: @Sendable () async -> String?

public init(
    session: URLSession = .shared,
    cacheTTL: TimeInterval = 10,
    maxRequestsPerWindow: Int = 10,
    windowDuration: TimeInterval = 60,
    coinGeckoAPIKey: @escaping @Sendable () async -> String? = { nil }) {
    self.session = session
    self.cacheTTL = cacheTTL
    self.maxRequestsPerWindow = maxRequestsPerWindow
    self.windowDuration = windowDuration
    self.coinGeckoAPIKey = coinGeckoAPIKey
}
```

Add this public method:

```swift
public func fetchHistoricalPrices(
    for coinId: String,
    days: Int = 365) async throws(PriceServiceError) -> [HistoricalPriceDTO] {
    let normalized = coinId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return [] }
    let data = try await rateLimitedFetch(
        pathComponents: ["coins", normalized, "market_chart"],
        queryItems: [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "days", value: "\(max(days, 1))")
        ])
    return try CoinGeckoMarketChartResponse(coinGeckoId: normalized, data: data).prices
}
```

Replace the current private `rateLimitedFetch(coinIds:extraParams:)` with two helpers:

```swift
private func rateLimitedFetch(
    coinIds: [String],
    extraParams: [URLQueryItem]) async throws(PriceServiceError) -> Data {
    let ids = Set(coinIds).joined(separator: ",")
    var params = [
        URLQueryItem(name: "ids", value: ids),
        URLQueryItem(name: "vs_currencies", value: "usd")
    ]
    params.append(contentsOf: extraParams)
    return try await rateLimitedFetch(pathComponents: ["simple", "price"], queryItems: params)
}

private func rateLimitedFetch(
    pathComponents: [String],
    queryItems: [URLQueryItem]) async throws(PriceServiceError) -> Data {
    let now = Date.now
    requestTimestamps.removeAll { now.timeIntervalSince($0.date) > windowDuration }
    guard requestTimestamps.count < maxRequestsPerWindow else {
        throw .rateLimited
    }

    let stamp = RequestStamp(id: UUID(), date: .now)
    requestTimestamps.append(stamp)

    var url = baseURL
    for component in pathComponents {
        url = url.appending(path: component)
    }
    url = url.appending(queryItems: queryItems)

    var request = URLRequest(url: url)
    if let key = await coinGeckoAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
        request.setValue(key, forHTTPHeaderField: "x-cg-demo-api-key")
    }

    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await session.data(for: request)
    } catch {
        requestTimestamps.removeAll { $0.id == stamp.id }
        throw .networkUnavailable
    }

    guard let http = response as? HTTPURLResponse else {
        throw .invalidResponse(statusCode: 0)
    }
    switch http.statusCode {
    case 200: return data
    case 429: throw .rateLimited
    default: throw .invalidResponse(statusCode: http.statusCode)
    }
}
```

- [ ] **Step 5: Extend `PriceServiceClient`**

In `Sources/Portu/App/AppFeature.swift`, extend `PriceServiceClient`:

```swift
struct PriceServiceClient {
    var fetchPrices: @Sendable ([String]) async throws -> PriceUpdate
    var fetchHistoricalPrices: @Sendable (String, Int) async throws -> [HistoricalPriceDTO]
    var invalidateCache: @Sendable () async -> Void
}
```

Update `liveValue`, `testValue`, and `.live(service:)`:

```swift
static let liveValue = Self(
    fetchPrices: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
    fetchHistoricalPrices: { _, _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
    invalidateCache: { fatalError("PriceServiceClient.liveValue must be overridden at Store creation") })

static let testValue = Self(
    fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
    fetchHistoricalPrices: { _, _ in [] },
    invalidateCache: {})

static func live(service: PriceService) -> Self {
    Self(
        fetchPrices: { coinIds in try await service.fetchPriceUpdate(for: coinIds) },
        fetchHistoricalPrices: { coinId, days in try await service.fetchHistoricalPrices(for: coinId, days: days) },
        invalidateCache: { await service.invalidateCache() })
}
```

Update every test initializer for `PriceServiceClient` to pass `fetchHistoricalPrices: { _, _ in [] }`.

- [ ] **Step 6: Wire the CoinGecko API key provider**

In `Sources/Portu/App/PortuApp.swift`, create one `KeychainService` and pass it to both provider factory and `PriceService`:

```swift
let secretStore = KeychainService()
let syncEngine = SyncEngine(
    modelContext: container.mainContext,
    providerFactory: ProviderFactory(secretStore: secretStore, session: session))
let priceService = PriceService(session: session) {
    try? secretStore.get(key: .serviceAPIKey("coingecko"))
}
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
swift test --package-path Packages/PortuNetwork --filter "historical prices"
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/AppFeatureTests test
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Packages/PortuNetwork/Sources/PortuNetwork/PriceService/CoinGeckoDTO.swift \
  Packages/PortuNetwork/Sources/PortuNetwork/PriceService/PriceService.swift \
  Packages/PortuNetwork/Tests/PortuNetworkTests/PriceServiceTests.swift \
  Sources/Portu/App/AppFeature.swift \
  Sources/Portu/App/PortuApp.swift \
  Tests/PortuTests/AppFeatureTests.swift \
  Tests/PortuTests/DebugServerTCATests.swift \
  Tests/PortuTests/ViewRenderSmokeTests.swift
git commit -m "feat: fetch coingecko historical prices"
```

---

## Task 3: Backfill Candidate Selection and Cache Writer

**Files:**

- Create: `Sources/Portu/Features/Settings/HistoricalPriceBackfillSettings.swift`
- Create: `Sources/Portu/Features/Settings/HistoricalPriceBackfillFeature.swift`
- Create: `Sources/Portu/Features/Settings/HistoricalPriceBackfillClient.swift`
- Test: `Tests/PortuTests/HistoricalPriceBackfillFeatureTests.swift`

- [ ] **Step 1: Write failing candidate and cache writer tests**

Create `Tests/PortuTests/HistoricalPriceBackfillFeatureTests.swift`:

```swift
import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct HistoricalPriceBackfillFeatureTests {
    @Test func `candidate selection prefers overrides and skips manual only assets`() {
        let bitcoin = token(assetId: uuid(1), symbol: "BTC", coinGeckoId: "bitcoin", amount: 1, usdValue: 60000)
        let mapped = token(assetId: uuid(2), symbol: "MAP", coinGeckoId: "old-id", amount: 2, usdValue: 20)
        let manualOnly = token(assetId: uuid(3), symbol: "MANUAL", amount: 3, usdValue: 0)
        let noPrice = token(assetId: uuid(4), symbol: "LOCAL", amount: 1, usdValue: 5)

        let candidates = HistoricalBackfillCandidateResolver.candidates(
            tokens: [bitcoin, mapped, manualOnly, noPrice],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: mapped.assetId, coinGeckoIdOverride: "new-id"),
                TokenPricingOverrideSnapshot(assetId: manualOnly.assetId, manualPriceUSD: 1.25)
            ])

        #expect(candidates.map(\.coinGeckoId) == ["bitcoin", "new-id"])
        #expect(candidates.map(\.assetIds) == [[bitcoin.assetId], [mapped.assetId]])
    }

    @Test func `candidate selection groups assets by normalized coingecko id`() {
        let first = token(assetId: uuid(1), symbol: "AAVE", coinGeckoId: " AAVE ", amount: 1, usdValue: 100)
        let second = token(assetId: uuid(2), symbol: "AAVE.e", coinGeckoId: "aave", amount: 2, usdValue: 200)

        let candidates = HistoricalBackfillCandidateResolver.candidates(tokens: [second, first], overrides: [])

        #expect(candidates.count == 1)
        #expect(candidates.first?.coinGeckoId == "aave")
        #expect(candidates.first?.assetIds == [first.assetId, second.assetId])
    }

    @Test func `cache writer upserts by coin gecko id and day`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        context.insert(HistoricalPricePoint(
            coinGeckoId: "bitcoin",
            day: day,
            usdPrice: 40000,
            fetchedAt: Date(timeIntervalSince1970: 10)))
        try context.save()

        let result = try HistoricalPriceCacheWriter.upsert(
            [
                HistoricalPriceDTO(coinGeckoId: "bitcoin", timestamp: day.addingTimeInterval(3600), usdPrice: 41000),
                HistoricalPriceDTO(coinGeckoId: "ethereum", timestamp: day, usdPrice: 2500)
            ],
            in: context,
            fetchedAt: Date(timeIntervalSince1970: 20))

        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>())
            .sorted { $0.coinGeckoId < $1.coinGeckoId }
        #expect(result.inserted == 1)
        #expect(result.updated == 1)
        #expect(rows.count == 2)
        #expect(rows[0].coinGeckoId == "bitcoin")
        #expect(rows[0].usdPrice == 41000)
        #expect(rows[0].fetchedAt == Date(timeIntervalSince1970: 20))
        #expect(rows[1].coinGeckoId == "ethereum")
    }

    @Test func `clear cache removes only historical price points`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        context.insert(HistoricalPricePoint(coinGeckoId: "bitcoin", day: Date(), usdPrice: 1))
        context.insert(Asset(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin"))
        try context.save()

        try HistoricalPriceCacheWriter.clear(in: context)

        #expect(try context.fetch(FetchDescriptor<HistoricalPricePoint>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Asset>()).count == 1)
    }

    private func token(
        assetId: UUID,
        symbol: String,
        coinGeckoId: String? = nil,
        amount: Decimal,
        usdValue: Decimal) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: symbol,
            category: .other,
            portfolioCategory: nil,
            coinGeckoId: coinGeckoId,
            role: .balance,
            amount: amount,
            usdValue: usdValue)
    }

    private func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }
}
```

- [ ] **Step 2: Run the failing app tests**

Run:

```bash
just generate
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/HistoricalPriceBackfillFeatureTests test
```

Expected: FAIL because historical backfill app types do not exist.

- [ ] **Step 3: Add settings keys**

Create `Sources/Portu/Features/Settings/HistoricalPriceBackfillSettings.swift`:

```swift
import Foundation

enum HistoricalPriceBackfillSettings {
    static let isEnabledKey = "historicalPriceBackfill.isEnabled"
    static let defaultIsEnabled = false
    static let chartHorizonDays = 365
    static let sectionTitle = "Historical Prices"
    static let useBackfillTitle = "Use historical price backfill"
    static let backfillButtonTitle = "Backfill historical prices"
    static let clearCacheButtonTitle = "Clear historical price cache"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: isEnabledKey) as? Bool ?? defaultIsEnabled
    }
}
```

- [ ] **Step 4: Add pure candidate and cache writer types**

Create `Sources/Portu/Features/Settings/HistoricalPriceBackfillFeature.swift` with these value types first:

```swift
import ComposableArchitecture
import Foundation
import PortuCore
import SwiftData

struct HistoricalBackfillCandidate: Equatable, Identifiable {
    var id: String { coinGeckoId }
    let coinGeckoId: String
    let assetIds: [UUID]
}

struct HistoricalBackfillWriteResult: Equatable {
    var inserted: Int
    var updated: Int
}

struct HistoricalBackfillResult: Equatable {
    var requestedAssets: Int
    var fetchedAssets: Int
    var skippedAssets: Int
    var insertedPoints: Int
    var updatedPoints: Int
    var failedCoinGeckoIDs: [String]
}

enum HistoricalBackfillStatus: Equatable {
    case idle
    case running
    case succeeded(HistoricalBackfillResult)
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

enum HistoricalBackfillCandidateResolver {
    static func candidates(
        tokens: [TokenEntry],
        overrides: [TokenPricingOverrideSnapshot]) -> [HistoricalBackfillCandidate] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var grouped: [String: Set<UUID>] = [:]
        for token in tokens where token.amount > 0 && (token.role.isPositive || token.role.isBorrow) {
            let override = overrideMap[token.assetId]
            if override?.manualPriceUSD != nil && normalizedID(override?.coinGeckoIdOverride) == nil {
                continue
            }
            guard let coinGeckoId = normalizedID(override?.coinGeckoIdOverride) ?? normalizedID(token.coinGeckoId) else {
                continue
            }
            grouped[coinGeckoId, default: []].insert(token.assetId)
        }
        return grouped
            .map { coinGeckoId, ids in
                HistoricalBackfillCandidate(
                    coinGeckoId: coinGeckoId,
                    assetIds: ids.sorted { $0.uuidString < $1.uuidString })
            }
            .sorted { $0.coinGeckoId < $1.coinGeckoId }
    }

    private static func normalizedID(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

enum HistoricalPriceCacheWriter {
    @MainActor
    static func upsert(
        _ dtos: [HistoricalPriceDTO],
        in context: ModelContext,
        fetchedAt: Date = .now) throws -> HistoricalBackfillWriteResult {
        let existing = try context.fetch(FetchDescriptor<HistoricalPricePoint>())
        var existingByKey = Dictionary(
            existing.map { (key(coinGeckoId: $0.coinGeckoId, day: $0.day), $0) },
            uniquingKeysWith: { lhs, rhs in lhs.fetchedAt >= rhs.fetchedAt ? lhs : rhs })
        var inserted = 0
        var updated = 0

        for dto in dtos {
            let cacheKey = key(coinGeckoId: dto.coinGeckoId, day: dto.day)
            if let row = existingByKey[cacheKey] {
                row.usdPrice = dto.usdPrice
                row.fetchedAt = fetchedAt
                updated += 1
            } else {
                let row = HistoricalPricePoint(dto: dto, fetchedAt: fetchedAt)
                context.insert(row)
                existingByKey[cacheKey] = row
                inserted += 1
            }
        }

        try context.save()
        return HistoricalBackfillWriteResult(inserted: inserted, updated: updated)
    }

    @MainActor
    static func clear(in context: ModelContext) throws {
        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>())
        for row in rows {
            context.delete(row)
        }
        try context.save()
    }

    private static func key(coinGeckoId: String, day: Date) -> String {
        "\(coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(HistoricalPriceCalendar.utcStartOfDay(for: day).timeIntervalSince1970)"
    }
}
```

The model keeps `id` as the SwiftData uniqueness constraint. Cache uniqueness for
`(coinGeckoId, day)` is enforced by `HistoricalPriceCacheWriter.upsert`, which
normalizes the composite key, fetches only rows matching the incoming keys, and
deduplicates those rows before updating or inserting prices.

- [ ] **Step 5: Add the backfill client dependency shell**

Create `Sources/Portu/Features/Settings/HistoricalPriceBackfillClient.swift`:

```swift
import ComposableArchitecture
import Foundation
import PortuCore
import SwiftData

struct HistoricalPriceBackfillClient {
    var run: @MainActor @Sendable () async throws -> HistoricalBackfillResult
    var clearCache: @MainActor @Sendable () async throws -> Void
}

extension HistoricalPriceBackfillClient: DependencyKey {
    static let liveValue = Self(
        run: { fatalError("HistoricalPriceBackfillClient.liveValue must be overridden at Store creation") },
        clearCache: { fatalError("HistoricalPriceBackfillClient.liveValue must be overridden at Store creation") })

    static let testValue = Self(
        run: { HistoricalBackfillResult(requestedAssets: 0, fetchedAssets: 0, skippedAssets: 0, insertedPoints: 0, updatedPoints: 0, failedCoinGeckoIDs: []) },
        clearCache: {})
}

extension DependencyValues {
    var historicalPriceBackfill: HistoricalPriceBackfillClient {
        get { self[HistoricalPriceBackfillClient.self] }
        set { self[HistoricalPriceBackfillClient.self] = newValue }
    }
}
```

- [ ] **Step 6: Add the reducer**

Append this reducer to `HistoricalPriceBackfillFeature.swift`:

```swift
@Reducer
struct HistoricalPriceBackfillFeature {
    @ObservableState
    struct State: Equatable {
        var status: HistoricalBackfillStatus = .idle
    }

    enum Action: Equatable {
        case backfillButtonTapped
        case backfillCompleted(Result<HistoricalBackfillResult, String>)
        case clearCacheButtonTapped
        case clearCacheCompleted(Result<Void, String>)
    }

    @Dependency(\.historicalPriceBackfill) var historicalPriceBackfill

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .backfillButtonTapped:
                guard !state.status.isRunning else { return .none }
                state.status = .running
                return .run { send in
                    do {
                        let result = try await historicalPriceBackfill.run()
                        await send(.backfillCompleted(.success(result)))
                    } catch {
                        await send(.backfillCompleted(.failure(error.localizedDescription)))
                    }
                }

            case let .backfillCompleted(.success(result)):
                state.status = .succeeded(result)
                return .none

            case let .backfillCompleted(.failure(message)):
                state.status = .failed(message)
                return .none

            case .clearCacheButtonTapped:
                return .run { send in
                    do {
                        try await historicalPriceBackfill.clearCache()
                        await send(.clearCacheCompleted(.success(())))
                    } catch {
                        await send(.clearCacheCompleted(.failure(error.localizedDescription)))
                    }
                }

            case .clearCacheCompleted(.success):
                state.status = .idle
                return .none

            case let .clearCacheCompleted(.failure(message)):
                state.status = .failed(message)
                return .none
            }
        }
    }
}
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
just generate
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/HistoricalPriceBackfillFeatureTests test
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/Portu/Features/Settings/HistoricalPriceBackfillSettings.swift \
  Sources/Portu/Features/Settings/HistoricalPriceBackfillFeature.swift \
  Sources/Portu/Features/Settings/HistoricalPriceBackfillClient.swift \
  Tests/PortuTests/HistoricalPriceBackfillFeatureTests.swift
git commit -m "feat: add historical price backfill core"
```

---

## Task 4: Live Backfill Orchestration and Settings UI

**Files:**

- Modify: `Sources/Portu/Features/Settings/HistoricalPriceBackfillClient.swift`
- Modify: `Sources/Portu/App/AppFeature.swift`
- Modify: `Sources/Portu/App/PortuApp.swift`
- Modify: `Sources/Portu/App/ContentView.swift`
- Modify: `Sources/Portu/Features/Settings/SettingsView.swift`
- Modify: `Tests/PortuTests/AppFeatureTests.swift`
- Modify: `Tests/PortuTests/SettingsTabTests.swift`

- [ ] **Step 1: Write reducer tests**

Add these to `Tests/PortuTests/AppFeatureTests.swift`:

```swift
@Test func `historical backfill success updates settings status`() async {
    let result = HistoricalBackfillResult(
        requestedAssets: 2,
        fetchedAssets: 2,
        skippedAssets: 1,
        insertedPoints: 10,
        updatedPoints: 3,
        failedCoinGeckoIDs: [])
    let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.historicalPriceBackfill.run = { result }
    }

    await store.send(.historicalPriceBackfill(.backfillButtonTapped)) {
        $0.historicalPriceBackfill.status = .running
    }
    await store.receive(\.historicalPriceBackfill.backfillCompleted) {
        $0.historicalPriceBackfill.status = .succeeded(result)
    }
}

@Test func `historical backfill clear resets status`() async {
    let initial = AppFeature.State(
        historicalPriceBackfill: HistoricalPriceBackfillFeature.State(
            status: .failed("Rate limited")))
    let store = TestStore(initialState: initial) {
        AppFeature()
    } withDependencies: {
        $0.historicalPriceBackfill.clearCache = {}
    }

    await store.send(.historicalPriceBackfill(.clearCacheButtonTapped))
    await store.receive(\.historicalPriceBackfill.clearCacheCompleted) {
        $0.historicalPriceBackfill.status = .idle
    }
}
```

Add this to `Tests/PortuTests/SettingsTabTests.swift`:

```swift
@Test func `historical price settings use shared keys and labels`() {
    let defaults = cleanDefaults()

    #expect(HistoricalPriceBackfillSettings.isEnabledKey == "historicalPriceBackfill.isEnabled")
    #expect(HistoricalPriceBackfillSettings.isEnabled(defaults: defaults) == false)

    defaults.set(true, forKey: HistoricalPriceBackfillSettings.isEnabledKey)
    #expect(HistoricalPriceBackfillSettings.isEnabled(defaults: defaults) == true)
    #expect(HistoricalPriceBackfillSettings.sectionTitle == "Historical Prices")
    #expect(HistoricalPriceBackfillSettings.chartHorizonDays == 365)
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
just generate
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/AppFeatureTests -only-testing:PortuTests/SettingsTabTests test
```

Expected: FAIL because `AppFeature.State.historicalPriceBackfill` and scoped actions do not exist.

- [ ] **Step 3: Scope the backfill reducer under `AppFeature`**

In `Sources/Portu/App/AppFeature.swift`, add to state:

```swift
var historicalPriceBackfill = HistoricalPriceBackfillFeature.State()
```

Add to action:

```swift
case historicalPriceBackfill(HistoricalPriceBackfillFeature.Action)
```

Add a scope before the main `Reduce`:

```swift
Scope(state: \.historicalPriceBackfill, action: \.historicalPriceBackfill) {
    HistoricalPriceBackfillFeature()
}
```

Extend `AppFeature.Action ==`:

```swift
case let (.historicalPriceBackfill(l), .historicalPriceBackfill(r)): l == r
```

In the switch body, add:

```swift
case .historicalPriceBackfill:
    return .none
```

- [ ] **Step 4: Implement the live backfill client**

Add this factory to `Sources/Portu/Features/Settings/HistoricalPriceBackfillClient.swift`:

```swift
extension HistoricalPriceBackfillClient {
    @MainActor
    static func live(
        modelContext: ModelContext,
        priceService: PriceServiceClient,
        now: @escaping @Sendable () -> Date = { .now }) -> Self {
        Self(
            run: {
                try await BackfillRunner(
                    modelContext: modelContext,
                    priceService: priceService,
                    now: now).run()
            },
            clearCache: {
                try HistoricalPriceCacheWriter.clear(in: modelContext)
            })
    }
}

@MainActor
private struct BackfillRunner {
    let modelContext: ModelContext
    let priceService: PriceServiceClient
    let now: @Sendable () -> Date

    func run() async throws -> HistoricalBackfillResult {
        let tokens = try modelContext.fetch(FetchDescriptor<PositionToken>())
        let overrides = try modelContext.fetch(FetchDescriptor<TokenPricingOverride>())
        let entries = TokenEntry.fromActiveTokens(tokens)
        let overrideSnapshots = overrides.map(TokenPricingOverrideSnapshot.init)
        let candidates = HistoricalBackfillCandidateResolver.candidates(
            tokens: entries,
            overrides: overrideSnapshots)

        var inserted = 0
        var updated = 0
        var fetched = 0
        var failures: [String] = []
        let skipped = max(0, Set(entries.map(\.assetId)).count - candidates.flatMap(\.assetIds).count)

        for candidate in candidates {
            do {
                let prices = try await priceService.fetchHistoricalPrices(
                    candidate.coinGeckoId,
                    HistoricalPriceBackfillSettings.chartHorizonDays)
                let write = try HistoricalPriceCacheWriter.upsert(prices, in: modelContext, fetchedAt: now())
                inserted += write.inserted
                updated += write.updated
                fetched += 1
            } catch {
                failures.append(candidate.coinGeckoId)
                if failures.count == candidates.count {
                    throw error
                }
            }
        }

        return HistoricalBackfillResult(
            requestedAssets: candidates.count,
            fetchedAssets: fetched,
            skippedAssets: skipped,
            insertedPoints: inserted,
            updatedPoints: updated,
            failedCoinGeckoIDs: failures)
    }
}
```

- [ ] **Step 5: Wire live dependency in `PortuApp`**

In `Sources/Portu/App/PortuApp.swift`, build `PriceServiceClient` once and pass it to both app dependencies:

```swift
let priceServiceClient = PriceServiceClient.live(service: priceService)

self.store = Store(initialState: AppFeature.State(storeIsEphemeral: isEphemeral)) {
    AppFeature()
} withDependencies: {
    $0.syncEngine = .live(engine: syncEngine)
    $0.priceService = priceServiceClient
    $0.historicalPriceBackfill = .live(
        modelContext: container.mainContext,
        priceService: priceServiceClient)
}
```

- [ ] **Step 6: Pass the store into Settings**

In `Sources/Portu/App/ContentView.swift`:

```swift
case .settings:
    SettingsView(store: store)
```

In `Sources/Portu/Features/Settings/SettingsView.swift`:

```swift
struct SettingsView: View {
    let store: StoreOf<AppFeature>
    @State private var selectedTab: SettingsTab = .general
    @State private var searchText = ""
```

Pass it into General:

```swift
case .general:
    GeneralSettingsTab(store: store)
```

Change `GeneralSettingsTab`:

```swift
private struct GeneralSettingsTab: View {
    let store: StoreOf<AppFeature>
    @AppStorage(PricePollingSettings.refreshIntervalKey)
    private var refreshInterval = PricePollingSettings.defaultRefreshIntervalSeconds
    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled
```

Add the historical settings card under the existing Price Updates card:

```swift
SettingsSectionCard(
    title: HistoricalPriceBackfillSettings.sectionTitle,
    subtitle: "Cache CoinGecko daily prices separately from Portu snapshots.",
    icon: .priceUpdates) {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(HistoricalPriceBackfillSettings.useBackfillTitle, isOn: $historicalBackfillEnabled)
                .toggleStyle(SettingsSwitchToggleStyle())

            HStack(spacing: 10) {
                Button(HistoricalPriceBackfillSettings.backfillButtonTitle) {
                    store.send(.historicalPriceBackfill(.backfillButtonTapped))
                }
                .buttonStyle(.plain)
                .settingsPrimaryButton(isDisabled: store.historicalPriceBackfill.status.isRunning)
                .disabled(store.historicalPriceBackfill.status.isRunning)

                Button(HistoricalPriceBackfillSettings.clearCacheButtonTitle) {
                    store.send(.historicalPriceBackfill(.clearCacheButtonTapped))
                }
                .buttonStyle(.plain)
                .settingsPrimaryButton(isDisabled: false)
            }

            HistoricalBackfillStatusText(status: store.historicalPriceBackfill.status)
        }
    }
```

Add a compact status view in the same file:

```swift
private struct HistoricalBackfillStatusText: View {
    let status: HistoricalBackfillStatus

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(SettingsDesign.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: String {
        switch status {
        case .idle:
            "No historical backfill run in this session."
        case .running:
            "Fetching historical prices from CoinGecko..."
        case let .succeeded(result):
            "Fetched \(result.fetchedAssets) assets, inserted \(result.insertedPoints), updated \(result.updatedPoints), skipped \(result.skippedAssets)."
        case let .failed(message):
            "Backfill failed: \(message)"
        }
    }
}
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
just generate
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/AppFeatureTests -only-testing:PortuTests/SettingsTabTests test
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/Portu/Features/Settings/HistoricalPriceBackfillClient.swift \
  Sources/Portu/App/AppFeature.swift \
  Sources/Portu/App/PortuApp.swift \
  Sources/Portu/App/ContentView.swift \
  Sources/Portu/Features/Settings/SettingsView.swift \
  Tests/PortuTests/AppFeatureTests.swift \
  Tests/PortuTests/SettingsTabTests.swift \
  Portu.xcodeproj
git commit -m "feat: add manual historical price backfill settings"
```

---

## Task 5: Historical Portfolio Estimator

**Files:**

- Create: `Sources/Portu/Features/Shared/HistoricalPortfolioEstimator.swift`
- Test: `Tests/PortuTests/HistoricalPortfolioEstimatorTests.swift`

- [ ] **Step 1: Write failing estimator tests**

Create `Tests/PortuTests/HistoricalPortfolioEstimatorTests.swift`:

```swift
import Foundation
@testable import Portu
import PortuCore
import Testing

struct HistoricalPortfolioEstimatorTests {
    @Test func `estimates values before first real snapshot using earliest holdings`() throws {
        let account = uuid(1)
        let btc = uuid(10)
        let eth = uuid(11)
        let day1 = date(2024, 1, 1)
        let firstReal = date(2024, 1, 3)

        let holdings = [
            HistoricalEstimateHolding(accountId: account, assetId: btc, coinGeckoId: "bitcoin", amount: 2),
            HistoricalEstimateHolding(accountId: account, assetId: eth, coinGeckoId: "ethereum", amount: 10)
        ]
        let prices = [
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day1, usdPrice: 40000),
            HistoricalPriceEntry(coinGeckoId: "ethereum", day: day1, usdPrice: 2000),
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: firstReal, usdPrice: 45000)
        ]

        let points = HistoricalPortfolioEstimator.estimatedValues(
            holdings: holdings,
            prices: prices,
            startDate: day1,
            firstRealSnapshotDate: firstReal,
            accountId: nil)

        #expect(points == [
            HistoricalPortfolioValuePoint(date: day1, value: 100000, kind: .estimated)
        ])
    }

    @Test func `account filter estimates only matching account holdings`() throws {
        let account = uuid(1)
        let other = uuid(2)
        let btc = uuid(10)
        let day = date(2024, 1, 1)
        let firstReal = date(2024, 1, 2)

        let points = HistoricalPortfolioEstimator.estimatedValues(
            holdings: [
                HistoricalEstimateHolding(accountId: account, assetId: btc, coinGeckoId: "bitcoin", amount: 2),
                HistoricalEstimateHolding(accountId: other, assetId: btc, coinGeckoId: "bitcoin", amount: 5)
            ],
            prices: [
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day, usdPrice: 40000)
            ],
            startDate: day,
            firstRealSnapshotDate: firstReal,
            accountId: account)

        #expect(points.map(\.value) == [80000])
    }

    @Test func `estimator skips days with incomplete prices`() throws {
        let account = uuid(1)
        let day = date(2024, 1, 1)
        let firstReal = date(2024, 1, 2)

        let points = HistoricalPortfolioEstimator.estimatedValues(
            holdings: [
                HistoricalEstimateHolding(accountId: account, assetId: uuid(10), coinGeckoId: "bitcoin", amount: 1),
                HistoricalEstimateHolding(accountId: account, assetId: uuid(11), coinGeckoId: "ethereum", amount: 1)
            ],
            prices: [
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day, usdPrice: 40000)
            ],
            startDate: day,
            firstRealSnapshotDate: firstReal,
            accountId: nil)

        #expect(points.isEmpty)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }
}
```

- [ ] **Step 2: Run the failing estimator tests**

Run:

```bash
just generate
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/HistoricalPortfolioEstimatorTests test
```

Expected: FAIL because estimator types do not exist.

- [ ] **Step 3: Add estimator value types and function**

Create `Sources/Portu/Features/Shared/HistoricalPortfolioEstimator.swift`:

```swift
import Foundation

enum HistoricalPortfolioPointKind: Equatable {
    case estimated
    case real
}

struct HistoricalPortfolioValuePoint: Equatable, Identifiable {
    var id: String { "\(kind)-\(date.timeIntervalSince1970)" }
    let date: Date
    let value: Decimal
    let kind: HistoricalPortfolioPointKind
}

struct HistoricalEstimateHolding: Equatable {
    let accountId: UUID
    let assetId: UUID
    let coinGeckoId: String
    let amount: Decimal
}

struct HistoricalPriceEntry: Equatable {
    let coinGeckoId: String
    let day: Date
    let usdPrice: Decimal
}

enum HistoricalPortfolioEstimator {
    static func estimatedValues(
        holdings: [HistoricalEstimateHolding],
        prices: [HistoricalPriceEntry],
        startDate: Date,
        firstRealSnapshotDate: Date,
        accountId: UUID?) -> [HistoricalPortfolioValuePoint] {
        let scopedHoldings = holdings.filter { holding in
            accountId == nil || holding.accountId == accountId
        }
        guard !scopedHoldings.isEmpty else { return [] }

        let requiredIDs = Set(scopedHoldings.map(\.coinGeckoId))
        var pricesByDay: [Date: [String: Decimal]] = [:]
        for price in prices {
            let day = utcStartOfDay(for: price.day)
            guard day >= utcStartOfDay(for: startDate), day < utcStartOfDay(for: firstRealSnapshotDate) else {
                continue
            }
            pricesByDay[day, default: [:]][price.coinGeckoId] = price.usdPrice
        }

        return pricesByDay.keys.sorted().compactMap { day in
            let dayPrices = pricesByDay[day, default: [:]]
            guard requiredIDs.allSatisfy({ dayPrices[$0] != nil }) else { return nil }
            let value = scopedHoldings.reduce(Decimal.zero) { partial, holding in
                partial + holding.amount * (dayPrices[holding.coinGeckoId] ?? 0)
            }
            return HistoricalPortfolioValuePoint(date: day, value: value, kind: .estimated)
        }
    }

    static func realValues(_ values: [(Date, Decimal)]) -> [HistoricalPortfolioValuePoint] {
        values
            .sorted { $0.0 < $1.0 }
            .map { HistoricalPortfolioValuePoint(date: utcStartOfDay(for: $0.0), value: $0.1, kind: .real) }
    }

    private static func utcStartOfDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.startOfDay(for: date)
    }
}
```

- [ ] **Step 4: Run focused estimator tests**

Run:

```bash
just generate
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/HistoricalPortfolioEstimatorTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Shared/HistoricalPortfolioEstimator.swift \
  Tests/PortuTests/HistoricalPortfolioEstimatorTests.swift \
  Portu.xcodeproj
git commit -m "feat: derive estimated portfolio history"
```

---

## Task 6: Chart Integration

**Files:**

- Modify: `Sources/Portu/Features/Overview/PortfolioValueChart.swift`
- Modify: `Sources/Portu/Features/Performance/ValueChartMode.swift`
- Modify: `Sources/Portu/Features/Performance/PerformanceFeature.swift`
- Modify: `Sources/Portu/Features/Performance/PerformanceBottomPanel.swift`
- Modify: `Sources/Portu/Features/AssetDetail/AssetPriceChart.swift`
- Modify: `Tests/PortuTests/PerformanceFeatureTests.swift`
- Modify: `Tests/PortuTests/AssetPriceChartTests.swift`

- [ ] **Step 1: Write failing pure tests for period price changes**

Add to `Tests/PortuTests/PerformanceFeatureTests.swift`:

```swift
struct PerformanceHistoricalPriceChangeTests {
    @Test func `computes period price changes from first and last cached prices`() throws {
        let day1 = date(2024, 1, 1)
        let day2 = date(2024, 1, 2)

        let changes = PerformanceFeature.computeHistoricalPriceChanges(
            rows: [
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day1, usdPrice: 40000),
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day2, usdPrice: 44000),
                HistoricalPriceEntry(coinGeckoId: "ethereum", day: day1, usdPrice: 2000),
                HistoricalPriceEntry(coinGeckoId: "ethereum", day: day2, usdPrice: 1800)
            ])

        #expect(changes.map(\.coinGeckoId) == ["bitcoin", "ethereum"])
        #expect(changes[0].percentChange == Decimal(string: "0.1")!)
        #expect(changes[1].percentChange == Decimal(string: "-0.1")!)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
```

- [ ] **Step 2: Run the failing performance tests**

Run:

```bash
just generate
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/PerformanceFeatureTests test
```

Expected: FAIL because `computeHistoricalPriceChanges` does not exist.

- [ ] **Step 3: Add period price change helper**

In `Sources/Portu/Features/Performance/PerformanceFeature.swift`, add:

```swift
struct AssetPricePeriodChange: Identifiable, Equatable {
    var id: String { coinGeckoId }
    let coinGeckoId: String
    let startPrice: Decimal
    let endPrice: Decimal
    let percentChange: Decimal
}

extension PerformanceFeature {
    static func computeHistoricalPriceChanges(
        rows: [HistoricalPriceEntry]) -> [AssetPricePeriodChange] {
        let grouped = Dictionary(grouping: rows) { $0.coinGeckoId }
        return grouped.keys.sorted().compactMap { coinGeckoId in
            let sorted = grouped[coinGeckoId, default: []].sorted {
                if $0.day != $1.day { return $0.day < $1.day }
                return $0.usdPrice < $1.usdPrice
            }
            guard
                let first = sorted.first,
                let last = sorted.last,
                first.usdPrice > 0
            else { return nil }
            return AssetPricePeriodChange(
                coinGeckoId: coinGeckoId,
                startPrice: first.usdPrice,
                endPrice: last.usdPrice,
                percentChange: (last.usdPrice - first.usdPrice) / first.usdPrice)
        }
    }
}
```

- [ ] **Step 4: Wire Overview estimated value chart**

In `Sources/Portu/Features/Overview/PortfolioValueChart.swift`:

- Query `AssetSnapshot`, `Asset`, `TokenPricingOverride`, and `HistoricalPricePoint`.
- Read `HistoricalPriceBackfillSettings.isEnabledKey` through `@AppStorage`.
- Build earliest holdings by taking the first real day of `AssetSnapshot` rows, mapping `assetId` to resolved CoinGecko ID with override preference, and using `amount - borrowAmount`.
- Convert `HistoricalPricePoint` rows to `HistoricalPriceEntry`.
- Draw estimated points before real points.

Core body shape:

```swift
Chart {
    ForEach(estimatedPoints) { point in
        LineMark(
            x: .value("Date", point.date),
            y: .value("Value", point.value))
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
    }

    ForEach(filteredSnapshots, id: \.id) { snapshot in
        AreaMark(
            x: .value("Date", snapshot.timestamp),
            y: .value("Value", snapshot.totalValue))
            .foregroundStyle(
                .linearGradient(
                    colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom))

        LineMark(
            x: .value("Date", snapshot.timestamp),
            y: .value("Value", snapshot.totalValue))
            .foregroundStyle(PortuTheme.dashboardGold)
    }
}
```

Add a caption below the chart only when estimated points are visible:

```swift
Text("Dashed segment is estimated from earliest Portu holdings and CoinGecko historical prices.")
    .font(.caption)
    .foregroundStyle(PortuTheme.dashboardSecondaryText)
```

- [ ] **Step 5: Wire Performance value chart**

In `Sources/Portu/Features/Performance/ValueChartMode.swift`:

- Add `@Query` values for `AssetSnapshot`, `Asset`, `TokenPricingOverride`, and `HistoricalPricePoint`.
- Add `@AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)`.
- Use `accountId` when calling `HistoricalPortfolioEstimator.estimatedValues`.
- Keep `PnLChartMode` unchanged so PnL uses real snapshots only.

The chart should use the same dashed estimated `LineMark` style as Overview and real value styling for snapshot data.

- [ ] **Step 6: Wire Asset Detail price chart**

In `Sources/Portu/Features/AssetDetail/AssetPriceChart.swift`, replace the current `priceChart` empty state branch with a query-backed chart:

```swift
@Query
private var historicalPrices: [HistoricalPricePoint]
```

In `init`, set the query:

```swift
if let targetCoinGeckoId = coinGeckoId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !targetCoinGeckoId.isEmpty {
    _historicalPrices = Query(
        filter: #Predicate<HistoricalPricePoint> { $0.coinGeckoId == targetCoinGeckoId },
        sort: \.day)
} else {
    _historicalPrices = Query(
        filter: #Predicate<HistoricalPricePoint> { $0.coinGeckoId == "__missing__" },
        sort: \.day)
}
```

The chart branch should render:

```swift
let points = historicalPrices.filter { $0.day >= store.assetDetail.selectedRange.startDate }
if points.isEmpty {
    ContentUnavailableView(
        "No Price History",
        systemImage: "chart.line.uptrend.xyaxis",
        description: Text("Run historical price cache from Settings"))
        .foregroundStyle(PortuTheme.dashboardSecondaryText)
        .frame(height: 250)
} else {
    Chart(points, id: \.id) { point in
        LineMark(
            x: .value("Date", point.day),
            y: .value("Price", point.usdPrice))
            .foregroundStyle(PortuTheme.dashboardGold)
    }
    .chartYAxis {
        AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0 ... 4)))
    }
    .frame(height: 250)
}
```

- [ ] **Step 7: Wire Performance bottom asset prices**

In `Sources/Portu/Features/Performance/PerformanceBottomPanel.swift`:

- Query `HistoricalPricePoint`.
- Convert rows within `startDate...Date.now` to `HistoricalPriceEntry`.
- Call `PerformanceFeature.computeHistoricalPriceChanges(rows:)`.
- Render the first five rows sorted by absolute percentage change descending.

Row text shape:

```swift
ForEach(priceChanges.prefix(5)) { change in
    HStack {
        Text(change.coinGeckoId)
            .frame(width: 120, alignment: .leading)
        Text(change.endPrice, format: .currency(code: "USD"))
            .frame(width: 90, alignment: .trailing)
        Text(change.percentChange, format: .percent.precision(.fractionLength(1)))
            .foregroundStyle(change.percentChange >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)
            .frame(width: 64, alignment: .trailing)
    }
    .font(.caption)
    .foregroundStyle(PortuTheme.dashboardSecondaryText)
}
```

- [ ] **Step 8: Run focused chart tests**

Run:

```bash
just generate
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/PerformanceFeatureTests -only-testing:PortuTests/AssetPriceChartTests -only-testing:PortuTests/HistoricalPortfolioEstimatorTests test
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/Portu/Features/Overview/PortfolioValueChart.swift \
  Sources/Portu/Features/Performance/ValueChartMode.swift \
  Sources/Portu/Features/Performance/PerformanceFeature.swift \
  Sources/Portu/Features/Performance/PerformanceBottomPanel.swift \
  Sources/Portu/Features/AssetDetail/AssetPriceChart.swift \
  Tests/PortuTests/PerformanceFeatureTests.swift \
  Tests/PortuTests/AssetPriceChartTests.swift \
  Portu.xcodeproj
git commit -m "feat: show historical price charts"
```

---

## Task 7: Verification

**Files:**

- No new files.

- [ ] **Step 1: Regenerate the Xcode project**

Run:

```bash
just generate
```

Expected: `Portu.xcodeproj` regenerates successfully.

- [ ] **Step 2: Run package tests**

Run:

```bash
swift test --package-path Packages/PortuCore
swift test --package-path Packages/PortuNetwork
```

Expected: PASS.

- [ ] **Step 3: Run focused app tests**

Run:

```bash
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation \
  -only-testing:PortuTests/HistoricalPriceBackfillFeatureTests \
  -only-testing:PortuTests/HistoricalPortfolioEstimatorTests \
  -only-testing:PortuTests/PerformanceFeatureTests \
  -only-testing:PortuTests/AssetPriceChartTests \
  -only-testing:PortuTests/AppFeatureTests \
  -only-testing:PortuTests/SettingsTabTests \
  test
```

Expected: PASS.

- [ ] **Step 4: Run the full scheme**

Run:

```bash
xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation test
```

Expected: PASS.

- [ ] **Step 5: Build and launch verification**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: build succeeds, app launches, and the script confirms the `Portu` process is running.

- [ ] **Step 6: Manual smoke check**

Open Portu and verify:

- Settings -> General shows `Historical Prices`.
- `Use historical price backfill` persists when toggled.
- `Backfill historical prices` changes status to running and then success or a clear CoinGecko error.
- Asset Detail -> Price shows cached price history after a successful backfill.
- Overview and Performance value charts show real snapshot data as before.
- When backfill is enabled and cache exists before the earliest snapshot day, estimated data is dashed and labeled.
- Performance PnL still uses real snapshot points only.

- [ ] **Step 7: Final commit if verification changed generated files**

```bash
git status --short
git add Portu.xcodeproj
git commit -m "chore: regenerate project for historical price backfill"
```

Only run the commit command if `git status --short` shows `Portu.xcodeproj` changes after verification.

---

## Self-Review Notes

- Spec coverage: separate cache model is Task 1; CoinGecko fetch is Task 2; manual Settings backfill is Task 4; estimated portfolio history is Task 5 and Task 6; Asset Detail price history and Performance asset price changes are Task 6; snapshot immutability is preserved by never writing snapshot rows.
- No generated estimated snapshots are planned.
- PnL remains real-only.
- Historical prices are deduped by normalized CoinGecko ID and UTC day.
- SwiftData access stays on the main actor in the live backfill path.

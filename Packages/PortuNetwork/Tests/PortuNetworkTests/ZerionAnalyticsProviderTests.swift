import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

private final class AnalyticsRetryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero
    private var recordedSleeps: [Duration] = []

    var now: Duration {
        lock.withLock { current }
    }

    var sleeps: [Duration] {
        lock.withLock { recordedSleeps }
    }

    func sleep(for duration: Duration) async throws {
        lock.withLock {
            recordedSleeps.append(duration)
            current += duration
        }
    }
}

@Suite(.serialized)
// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
struct ZerionAnalyticsProviderTests {
    private let evmAddress = "0x1111111111111111111111111111111111111111"
    private let solanaAddress = "8BH9pjtgyZDC4iAQH5ZiYDZ1MDWC98xki2V8NzqqKW3K"

    init() {
        ZerionAnalyticsMockURLProtocol.reset()
    }

    @Test func `wallet chart request uses normalized address USD full positions and chain filters`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let fixture = try fixtureData("wallet-chart")
        ZerionAnalyticsMockURLProtocol.respond { request in
            #expect(request.url?.path == "/v1/wallets/\(evmAddress)/charts/month")
            let url = try #require(request.url)
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let items = Dictionary(uniqueKeysWithValues: (query.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            #expect(items["currency"] == "usd")
            #expect(items["filter[positions]"] == "no_filter")
            #expect(items["filter[chain_ids]"] == "base,ethereum")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic dGVzdC1rZXk6")
            return .init(data: fixture, statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: " \(evmAddress.uppercased()) ")],
            chainIDs: ["ethereum", "base"])

        let points = try await provider.fetchPortfolioValueHistory(scope: scope, period: .month)

        #expect(points.map(\.usdValue) == [110, 120, 0])
        #expect(points.map(\.timestamp) == [
            Date(timeIntervalSince1970: 1_704_100_000),
            Date(timeIntervalSince1970: 1_704_153_600),
            Date(timeIntervalSince1970: 1_704_240_000)
        ])
        #expect(points.allSatisfy { $0.provider == .zerion && $0.coverage == .noFilter })
    }

    @Test func `unrestricted wallet chart omits chain filter`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let fixture = try fixtureData("wallet-chart")
        ZerionAnalyticsMockURLProtocol.respond { request in
            let items = try queryItems(in: request)
            #expect(items["filter[chain_ids]"] == nil)
            return .init(data: fixture, statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        let points = try await provider.fetchPortfolioValueHistory(scope: scope, period: .month)

        #expect(points.isEmpty == false)
    }

    @Test func `wallet chart drops points outside response interval`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let response = Data(#"""
        {
          "data": {
            "attributes": {
              "begin_at": "2024-01-01T00:00:00Z",
              "end_at": "2024-01-02T00:00:00Z",
              "points": [[1704067200, 100], [1704240000, 200]]
            }
          }
        }
        """#.utf8)
        ZerionAnalyticsMockURLProtocol.respond { _ in
            .init(data: response, statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        let points = try await provider.fetchPortfolioValueHistory(scope: scope, period: .month)

        #expect(points.map(\.usdValue) == [100])
    }

    @Test func `wallet chart drops far future points without response end`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let response = Data(#"""
        {
          "data": {
            "attributes": {
              "begin_at": "2024-01-01T00:00:00Z",
              "end_at": null,
              "points": [[1704067200, 100], [4000000000, 200]]
            }
          }
        }
        """#.utf8)
        ZerionAnalyticsMockURLProtocol.respond { _ in
            .init(data: response, statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        let points = try await provider.fetchPortfolioValueHistory(scope: scope, period: .month)

        #expect(points.map(\.usdValue) == [100])
    }

    @Test func `wallet chart tuple decodes value independently from malformed timestamp`() throws {
        let data = Data(#"""
        {"attributes":{"points":[["malformed",130]],"begin_at":null,"end_at":null}}
        """#.utf8)

        let resource = try JSONDecoder().decode(ZerionWalletChartResource.self, from: data)

        #expect(resource.attributes.points.first?.timestamp == nil)
        #expect(resource.attributes.points.first?.value == 130)
    }

    @Test func `one EVM and one Solana address use wallet set chart`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let fixture = try fixtureData("wallet-set-chart")
        ZerionAnalyticsMockURLProtocol.respond { request in
            #expect(request.url?.path == "/v1/wallet-sets/charts/week")
            let url = try #require(request.url)
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let items = Dictionary(uniqueKeysWithValues: (query.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            #expect(items["addresses"] == "\(evmAddress),\(solanaAddress)")
            #expect(items["currency"] == "usd")
            #expect(items["filter[positions]"] == nil)
            #expect(items["filter[chain_ids]"]?.split(separator: ",").count ?? 0 <= 25)
            return .init(data: fixture, statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [
                .init(family: .solana, value: solanaAddress),
                .init(family: .evm, value: evmAddress)
            ])

        let points = try await provider.fetchPortfolioValueHistory(scope: scope, period: .week)

        #expect(points.map(\.usdValue) == [250, 275])
        #expect(points.allSatisfy { $0.coverage == .providerReported })
    }

    @Test(arguments: [
        (ZerionChartPeriod.week, "week"),
        (.month, "month"),
        (.threeMonths, "3months"),
        (.year, "year")
    ])
    func `chart period maps to documented path`(period: ZerionChartPeriod, expected: String) {
        #expect(period.rawValue == expected)
    }

    @Test(arguments: [
        (Date(timeIntervalSince1970: 1_767_312_000), ZerionChartPeriod.month),
        (Date(timeIntervalSince1970: 1_771_027_200), ZerionChartPeriod.threeMonths),
        (Date(timeIntervalSince1970: 1_775_952_000), ZerionChartPeriod.year)
    ])
    func `YTD period selects enough chart resolution`(now: Date, expected: ZerionChartPeriod) {
        #expect(ZerionChartPeriod.yearToDate(at: now) == expected)
    }

    @Test func `YTD period uses the user calendar across the UTC new year`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let utcNewYear = Date(timeIntervalSince1970: 1_767_225_600)

        #expect(ZerionChartPeriod.yearToDate(at: utcNewYear, calendar: calendar) == .year)
    }

    @Test func `unsupported and invalid scopes fail before a request`() async {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let provider = makeProvider()
        let duplicateFamily = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [
                .init(family: .evm, value: evmAddress),
                .init(family: .evm, value: "0x2222222222222222222222222222222222222222")
            ])
        let invalid = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: "not-an-address")])
        let invalidSolana = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .solana, value: String(repeating: "z", count: 44))])
        let wrongSource = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zapper,
            addresses: [.init(family: .evm, value: evmAddress)])

        await #expect(throws: ZerionError.unsupportedAnalyticsScope) {
            _ = try await provider.fetchPortfolioValueHistory(scope: duplicateFamily, period: .week)
        }
        await #expect(throws: ZerionError.invalidAddress("not-an-address")) {
            _ = try await provider.fetchPortfolioValueHistory(scope: invalid, period: .week)
        }
        await #expect(throws: ZerionError.invalidAddress(String(repeating: "z", count: 44))) {
            _ = try await provider.fetchPortfolioValueHistory(scope: invalidSolana, period: .week)
        }
        await #expect(throws: ZerionError.unsupportedAnalyticsScope) {
            _ = try await provider.fetchPortfolioValueHistory(scope: wrongSource, period: .week)
        }
        #expect(ZerionAnalyticsMockURLProtocol.requests.isEmpty)
    }

    @Test func `generic wallet chart chain filter stays within endpoint limit`() {
        #expect(ZerionChainMapping.analyticsChainIDs.count <= 25)
        #expect(ZerionChainMapping.analyticsChainIDs.contains("solana"))
    }

    @Test func `wallet PnL requests selected currency and normalizes every summary field`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let fixture = try fixtureData("pnl-overall")
        ZerionAnalyticsMockURLProtocol.respond { request in
            #expect(request.url?.path == "/v1/wallets/\(evmAddress)/pnl")
            let items = try queryItems(in: request)
            #expect(items["currency"] == "chf")
            #expect(items["since"] == "1701475200000")
            #expect(items["filter[chain_ids]"] == "ethereum")
            return .init(data: fixture, statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)],
            chainIDs: ["ethereum"])
        let asOf = Date(timeIntervalSince1970: 1_704_153_600)

        let result = try await provider.fetchPnL(
            scope: scope,
            range: .oneMonth,
            currency: .chf,
            implementations: [],
            asOf: asOf)

        #expect(result.range == .oneMonth)
        #expect(result.currency == .chf)
        #expect(result.totalGain == Decimal(string: "-637.8173517"))
        #expect(result.realizedGain == Decimal(string: "-655.3618983"))
        #expect(result.unrealizedGain == Decimal(string: "17.5445466"))
        #expect(result.relativeTotalGain == Decimal(string: "-0.1138"))
        #expect(result.relativeRealizedGain == Decimal(string: "-0.1515"))
        #expect(result.relativeUnrealizedGain == Decimal(string: "-0.0019"))
        #expect(result.totalFee == Decimal(string: "281.9088917"))
        #expect(result.totalInvested == Decimal(string: "701.2"))
        #expect(result.realizedCostBasis == Decimal(string: "655.36"))
        #expect(result.netInvested == Decimal(string: "45.84218703"))
        #expect(result.receivedExternal == Decimal(string: "133971.2931"))
        #expect(result.sentExternal == Decimal(string: "133270.089"))
        #expect(result.sentForNFTs == 120)
        #expect(result.receivedForNFTs == 80)
        #expect(result.fetchedAt == asOf)
    }

    @Test func `unrestricted wallet PnL omits chain filter`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let fixture = try fixtureData("pnl-overall")
        ZerionAnalyticsMockURLProtocol.respond { request in
            let items = try queryItems(in: request)
            #expect(items["filter[chain_ids]"] == nil)
            return .init(data: fixture, statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        let result = try await provider.fetchPnL(
            scope: scope,
            range: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: Date(timeIntervalSince1970: 1_704_153_600))

        #expect(result.totalGain == Decimal(string: "-637.8173517"))
    }

    @Test func `wallet PnL polls preparing responses within the two minute deadline`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let fixture = try fixtureData("pnl-overall")
        ZerionAnalyticsMockURLProtocol.respond { _ in
            let isReady = ZerionAnalyticsMockURLProtocol.requests.count == 3
            return .init(
                data: isReady ? fixture : Data(#"{"errors":[]}"#.utf8),
                statusCode: isReady ? 200 : 503,
                headers: isReady ? [:] : ["Retry-After": "30"])
        }
        let clock = AnalyticsRetryClock()
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAnalyticsMockSession(),
            minimumRequestInterval: .zero,
            maximumRetryAttempts: 0,
            pacingNow: { clock.now },
            pacingSleep: { try await clock.sleep(for: $0) }))
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        let result = try await provider.fetchPnL(
            scope: scope,
            range: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: Date(timeIntervalSince1970: 1_704_153_600))

        #expect(result.totalGain == Decimal(string: "-637.8173517"))
        #expect(ZerionAnalyticsMockURLProtocol.requests.count == 3)
        #expect(clock.sleeps == [.seconds(30), .seconds(30)])
    }

    @Test func `wallet PnL stops preparing polls at the two minute deadline`() async {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        ZerionAnalyticsMockURLProtocol.respond { _ in
            .init(
                data: Data(#"{"errors":[]}"#.utf8),
                statusCode: 503,
                headers: ["Retry-After": "30"])
        }
        let clock = AnalyticsRetryClock()
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAnalyticsMockSession(),
            minimumRequestInterval: .zero,
            maximumRetryAttempts: 0,
            pacingNow: { clock.now },
            pacingSleep: { try await clock.sleep(for: $0) }))
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        await #expect(throws: ZerionError.temporarilyUnavailable(retryAfter: 30)) {
            _ = try await provider.fetchPnL(
                scope: scope,
                range: .oneMonth,
                currency: .usd,
                implementations: [],
                asOf: Date(timeIntervalSince1970: 1_704_153_600))
        }

        #expect(ZerionAnalyticsMockURLProtocol.requests.count == 4)
        #expect(clock.sleeps == Array(repeating: .seconds(30), count: 4))
    }

    @Test func `wallet PnL shares one preparation deadline across filtered batches`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let overall = try fixtureData("pnl-overall")
        let filtered = try fixtureData("pnl-filtered")
        ZerionAnalyticsMockURLProtocol.respond { request in
            let hasFilter = try queryItems(in: request)["filter[fungible_implementations]"] != nil
            let requestCount = ZerionAnalyticsMockURLProtocol.requests.count
            if hasFilter, requestCount == 2 || requestCount == 4 {
                return .init(
                    data: Data(#"{"errors":[]}"#.utf8),
                    statusCode: 503,
                    headers: ["Retry-After": "60"])
            }
            return .init(
                data: hasFilter ? filtered : overall,
                statusCode: 200,
                headers: [:])
        }
        let clock = AnalyticsRetryClock()
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAnalyticsMockSession(),
            minimumRequestInterval: .zero,
            maximumRetryAttempts: 0,
            pacingNow: { clock.now },
            pacingSleep: { try await clock.sleep(for: $0) }))
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])
        let identities = (0 ..< 101).map {
            OnchainTokenIdentity(
                chain: .ethereum,
                contractAddress: String(format: "0x%040x", $0 + 1))
        }

        let result = try await provider.fetchPnL(
            scope: scope,
            range: .oneMonth,
            currency: .usd,
            implementations: identities,
            asOf: Date(timeIntervalSince1970: 1_704_153_600))

        #expect(result.totalGain == Decimal(string: "-637.8173517"))
        #expect(result.assets.count == 1)
        #expect(ZerionAnalyticsMockURLProtocol.requests.count == 5)
        #expect(clock.sleeps == [.seconds(60), .seconds(60)])
    }

    @Test func `wallet set PnL uses addresses and keeps direct EUR denomination`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let fixture = try fixtureData("pnl-overall")
        ZerionAnalyticsMockURLProtocol.respond { request in
            #expect(request.url?.path == "/v1/wallet-sets/pnl")
            let items = try queryItems(in: request)
            #expect(items["addresses"] == "\(evmAddress),\(solanaAddress)")
            #expect(items["currency"] == "eur")
            return .init(data: fixture, statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [
                .init(family: .solana, value: solanaAddress),
                .init(family: .evm, value: evmAddress)
            ])

        let result = try await provider.fetchPnL(
            scope: scope,
            range: .allTime,
            currency: .eur,
            implementations: [],
            asOf: Date(timeIntervalSince1970: 1_704_153_600))

        #expect(result.currency == .eur)
    }

    @Test(arguments: [
        (ProviderPnLRange.allTime, nil),
        (.oneDay, "1704067200000"),
        (.oneWeek, "1703548800000"),
        (.oneMonth, "1701475200000"),
        (.oneYear, "1672617600000"),
        (.yearToDate, "1704067200000")
    ])
    func `pnl ranges use only Zerion standard marks`(range: ProviderPnLRange, expected: String?) throws {
        let asOf = Date(timeIntervalSince1970: 1_704_153_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        #expect(range.zerionSinceMilliseconds(asOf: asOf, calendar: calendar) == expected)
    }

    @Test func `YTD pnl since uses the user calendar across the UTC new year`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let utcNewYear = Date(timeIntervalSince1970: 1_767_225_600)

        #expect(
            ProviderPnLRange.yearToDate.zerionSinceMilliseconds(
                asOf: utcNewYear,
                calendar: calendar) == "1735718400000")
    }

    @Test func `filtered PnL batches never replace or sum the overall result`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let overall = try fixtureData("pnl-overall")
        let filtered = try fixtureData("pnl-filtered")
        ZerionAnalyticsMockURLProtocol.respond { request in
            let items = try queryItems(in: request)
            return .init(
                data: items["filter[fungible_implementations]"] == nil ? overall : filtered,
                statusCode: 200,
                headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])
        let identities = (0 ..< 101).map {
            OnchainTokenIdentity(
                chain: .ethereum,
                contractAddress: String(format: "0x%040x", $0 + 1))
        }

        let result = try await provider.fetchPnL(
            scope: scope,
            range: .allTime,
            currency: .usd,
            implementations: identities,
            asOf: Date(timeIntervalSince1970: 1_704_153_600))

        #expect(ZerionAnalyticsMockURLProtocol.requests.count == 4)
        for request in ZerionAnalyticsMockURLProtocol.requests.dropFirst() {
            let filter = try #require(queryItems(in: request)["filter[fungible_implementations]"])
            #expect(filter.split(separator: ",").count <= 100)
            #expect(request.url?.absoluteString.count ?? .max <= 2000)
        }
        #expect(result.totalGain == Decimal(string: "-637.8173517"))
        #expect(result.assets.count == 1)
        #expect(result.assets.first?.totalGain == 10)
        #expect(result.assets.first?.relativeTotalGain == Decimal(string: "0.025"))
        #expect(result.excludedIdentifiers == [
            "ethereum:",
            "ethereum:0x000000000000000000000000000000000000dead",
            "ethereum:0x6b175474e89094c44da98b954eedeac495271d0f"
        ])
    }

    @Test func `overall PnL survives a failed filtered breakdown batch`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let overall = try fixtureData("pnl-overall")
        let implementation = "ethereum:\(evmAddress)"
        ZerionAnalyticsMockURLProtocol.respond { request in
            let items = try queryItems(in: request)
            if items["filter[fungible_implementations]"] == nil {
                return .init(data: overall, statusCode: 200, headers: [:])
            }
            #expect(items["filter[fungible_implementations]"] == implementation)
            return .init(
                data: Data(#"{"errors":[]}"#.utf8),
                statusCode: 429,
                headers: [:])
        }
        let provider = makeProvider(maximumRetryAttempts: 0)
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        let result = try await provider.fetchPnL(
            scope: scope,
            range: .allTime,
            currency: .usd,
            implementations: [OnchainTokenIdentity(
                chain: .ethereum,
                contractAddress: evmAddress)],
            asOf: Date(timeIntervalSince1970: 1_704_153_600))

        #expect(result.totalGain == Decimal(string: "-637.8173517"))
        #expect(result.assets.isEmpty)
        #expect(result.excludedIdentifiers == [
            "ethereum:0x000000000000000000000000000000000000dead",
            implementation
        ])
    }

    @Test func `malformed PnL implementations remain provider only`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let response = Data(#"""
        {
          "data": {
            "attributes": {
              "total_gain": 0,
              "breakdown": {
                "by_implementation": {
                  "ethereum:not-an-address": {"total_gain": 1},
                  "solana:not-a-mint": {"total_gain": 2},
                  "ethereum:0x1111111111111111111111111111111111111111": {"total_gain": 3}
                }
              }
            }
          }
        }
        """#.utf8)
        ZerionAnalyticsMockURLProtocol.respond { _ in
            .init(data: response, statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        let result = try await provider.fetchPnL(
            scope: scope,
            range: .oneMonth,
            currency: .usd,
            implementations: [OnchainTokenIdentity(
                chain: .ethereum,
                contractAddress: "0x1111111111111111111111111111111111111111")],
            asOf: Date(timeIntervalSince1970: 1_704_153_600))

        let assets = Dictionary(uniqueKeysWithValues: result.assets.map { ($0.implementationID, $0) })
        #expect(assets["ethereum:not-an-address"]?.identity == nil)
        #expect(assets["solana:not-a-mint"]?.identity == nil)
        #expect(assets["ethereum:0x1111111111111111111111111111111111111111"]?.identity?.chain == .ethereum)
    }

    @Test func `portfolio reconciliation parses normalized no filter summary`() async throws {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        let fixture = try fixtureData("portfolio")
        ZerionAnalyticsMockURLProtocol.respond { request in
            #expect(request.url?.path == "/v1/wallets/\(evmAddress)/portfolio")
            let items = try queryItems(in: request)
            #expect(items["currency"] == "usd")
            #expect(items["filter[positions]"] == "no_filter")
            #expect(items["sync"] == "false")
            return .init(data: fixture, statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        let summary = try await provider.fetchPortfolioSummary(scope: scope)

        #expect(summary.totalPositions == 1000)
        #expect(summary.positionsByChain == ["base": 400, "ethereum": 600])
        #expect(summary.positionsByType["borrowed"] == 50)
        #expect(summary.absoluteChange1D == 25)
        #expect(summary.relativeChange1D == Decimal(string: "0.025"))
    }

    @Test func `portfolio reconciliation uses absolute or relative tolerance`() {
        let withinAbsolute = ZerionPortfolioReconciliation.compare(
            providerTotal: 1000,
            localTotal: 999.6,
            absoluteTolerance: 0.5,
            relativeTolerance: 0.0001)
        let withinRelative = ZerionPortfolioReconciliation.compare(
            providerTotal: 1000,
            localTotal: 995,
            absoluteTolerance: 1,
            relativeTolerance: 0.01)
        let outside = ZerionPortfolioReconciliation.compare(
            providerTotal: 1000,
            localTotal: 980,
            absoluteTolerance: 1,
            relativeTolerance: 0.01)

        #expect(withinAbsolute.isWithinTolerance)
        #expect(withinRelative.isWithinTolerance)
        #expect(outside.isWithinTolerance == false)
        #expect(outside.absoluteDifference == 20)
        #expect(outside.relativeDifference == Decimal(string: "0.02"))
    }

    @Test func `malformed chart and PnL payloads fail without fabricated values`() async {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        ZerionAnalyticsMockURLProtocol.respond { _ in
            .init(data: Data(#"{"data":{"attributes":{}}}"#.utf8), statusCode: 200, headers: [:])
        }
        let provider = makeProvider()
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        await #expect(throws: ZerionError.decodingFailed) {
            _ = try await provider.fetchPortfolioValueHistory(scope: scope, period: .week)
        }
        await #expect(throws: ZerionError.decodingFailed) {
            _ = try await provider.fetchPnL(
                scope: scope,
                range: .oneMonth,
                currency: .usd,
                implementations: [],
                asOf: Date(timeIntervalSince1970: 1_704_153_600))
        }
    }

    @Test(
        arguments: [
            (400, ZerionError.badRequest),
            (401, ZerionError.unauthorized),
            (402, ZerionError.paymentRequired),
            (403, ZerionError.unauthorized),
            (404, ZerionError.notFound),
            (429, ZerionError.rateLimited(
                remainingSecond: nil,
                remainingDay: 0,
                remainingMonth: nil,
                reset: nil)),
            (503, ZerionError.temporarilyUnavailable(retryAfter: nil))
        ])
    func `typed chart failures propagate`(status: Int, expected: ZerionError) async {
        defer { ZerionAnalyticsMockURLProtocol.reset() }
        ZerionAnalyticsMockURLProtocol.respond { _ in
            var headers = ["RateLimit-Org-Day-Remaining": "0"]
            if status != 503 {
                headers["Retry-After"] = "7"
            }
            return .init(
                data: Data(#"{"errors":[]}"#.utf8),
                statusCode: status,
                headers: headers)
        }
        let provider = makeProvider(maximumRetryAttempts: 0)
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)])

        await #expect(throws: expected) {
            _ = try await provider.fetchPortfolioValueHistory(scope: scope, period: .week)
        }
    }

    private func makeProvider(maximumRetryAttempts: Int = 2) -> ZerionProvider {
        ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAnalyticsMockSession(),
            minimumRequestInterval: .zero,
            maximumRetryAttempts: maximumRetryAttempts))
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func queryItems(in request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}

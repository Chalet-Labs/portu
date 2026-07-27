import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

@Suite(.serialized)
struct ZerionProviderTests {
    init() {
        ZerionMockURLProtocol.reset()
    }

    @Test func `combined fetch requests no filter once and maps simple native balance`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        ZerionMockURLProtocol.respond { request in
            let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(request.url?.absoluteString.hasPrefix(
                "https://api.zerion.io/v1/wallets/0xabc/positions/?") == true)
            #expect(query["currency"] == "usd")
            #expect(query["filter[positions]"] == "no_filter")
            #expect(query["filter[trash]"] == "only_non_trash")
            #expect(query["filter[chain_ids]"] == "ethereum")
            return .init(data: Data(Self.positionsFixture.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))

        let positions = try await provider.fetchPositions(context: makeSyncContext(chain: .ethereum))

        #expect(ZerionMockURLProtocol.requests.count == 1)
        let idle = try #require(positions.first { $0.positionType == .idle })
        let token = try #require(idle.tokens.first)
        #expect(token.role == .balance)
        #expect(token.symbol == "ETH")
        #expect(token.amount == Decimal(string: "1.123456789012345678"))
        #expect(token.usdValue == 0)
        #expect(token.contractAddress == OnchainTokenIdentity.nativeAssetSentinel)
        #expect(token.sourceKey == "asset:ethereum:0x0000000000000000000000000000000000000000")
    }

    @Test func `combined fetch follows pagination before returning positions`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        let fixture = try #require(
            JSONSerialization.jsonObject(with: Data(Self.positionsFixture.utf8)) as? [String: Any])
        let rows = try #require(fixture["data"] as? [[String: Any]])

        var firstPage = fixture
        firstPage["data"] = Array(rows.prefix(1))
        firstPage["links"] = [
            "next": "https://api.zerion.io/v1/wallets/0xabc/positions/?page=2"
        ]
        let firstPageData = try JSONSerialization.data(withJSONObject: firstPage)

        var secondPage = fixture
        secondPage["data"] = Array(rows.dropFirst())
        secondPage["links"] = [:]
        let secondPageData = try JSONSerialization.data(withJSONObject: secondPage)

        ZerionMockURLProtocol.respond { request in
            let page = try URLComponents(
                url: #require(request.url),
                resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "page" }?
                .value
            return .init(
                data: page == "2" ? secondPageData : firstPageData,
                statusCode: 200,
                headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))

        let positions = try await provider.fetchPositions(context: makeSyncContext(chain: .ethereum))

        #expect(ZerionMockURLProtocol.requests.count == 2)
        #expect(Set(positions.flatMap(\.tokens).map(\.symbol)) == ["ETH", "USDT", "WETH"])
    }

    @Test func `complex rows group by chain dapp and group id without counting receipts`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        ZerionMockURLProtocol.respond { _ in
            .init(data: Data(Self.positionsFixture.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))

        let positions = try await provider.fetchPositions(context: makeSyncContext(chain: .ethereum))
        let lp = try #require(positions.first { $0.positionType == .liquidityPool })

        #expect(lp.protocolId == "uniswap-v2")
        #expect(lp.protocolName == "Uniswap V2")
        #expect(lp.tokens.count == 2)
        #expect(lp.tokens.map(\.role) == [.supply, .supply])
        #expect(lp.tokens.map(\.symbol) == ["USDT", "WETH"])
        #expect(lp.tokens.reduce(Decimal.zero) { $0 + $1.usdValue } == 410)
        #expect(!lp.tokens.contains { $0.symbol == "UNI-V2" })
    }

    @Test func `unknown response chain skips only the malformed resource`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        let fixture = Self.positionsFixture.replacingFirstOccurrence(
            of: #""id":"ethereum""#,
            with: #""id":"future-chain""#)
        ZerionMockURLProtocol.respond { _ in
            .init(data: Data(fixture.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))

        let positions = try await provider.fetchPositions(context: makeSyncContext(chain: .ethereum))

        #expect(Set(positions.flatMap(\.tokens).map(\.symbol)) == ["USDT", "WETH"])
    }

    @Test func `combined Solana fetch requests simple positions only`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        var fixtureObject = try #require(
            JSONSerialization.jsonObject(with: Data(Self.positionsFixture.utf8)) as? [String: Any])
        let rows = try #require(fixtureObject["data"] as? [[String: Any]])
        fixtureObject["data"] = Array(rows.prefix(1))
        let simpleFixture = try #require(String(
            data: JSONSerialization.data(withJSONObject: fixtureObject),
            encoding: .utf8))
            .replacingOccurrences(of: "ethereum", with: "solana")
        ZerionMockURLProtocol.respond { request in
            let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(query["filter[positions]"] == "only_simple")
            return .init(data: Data(simpleFixture.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))

        _ = try await provider.fetchPositions(context: makeSyncContext(chain: .solana))
    }

    @Test(arguments: [Chain.mode, .opBNB, .ronin, .taiko])
    func `chains rejected by positions fail before making a request`(chain: Chain) async {
        defer { ZerionMockURLProtocol.reset() }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))

        await #expect(throws: ZerionError.unsupportedChain(chain.rawValue)) {
            _ = try await provider.fetchPositions(context: makeSyncContext(chain: chain))
        }
        #expect(ZerionMockURLProtocol.requests.isEmpty)
    }

    @Test func `multiple addresses are deduplicated and requested deterministically`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        ZerionMockURLProtocol.respond { _ in
            .init(data: Data(#"{"data":[],"links":{}}"#.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))
        let context = makeSyncContext(addresses: [
            ("0xb", .ethereum),
            ("0xa", .ethereum),
            ("0xa", .ethereum)
        ])

        let positions = try await provider.fetchPositions(context: context)

        #expect(positions.isEmpty)
        #expect(ZerionMockURLProtocol.requests.compactMap(\.url?.path) == [
            "/v1/wallets/0xa/positions",
            "/v1/wallets/0xb/positions"
        ])
    }

    @Test func `invalid exact quantity skips only the malformed resource`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        let invalid = Self.positionsFixture.replacingOccurrences(
            of: #""numeric":"1.123456789012345678""#,
            with: #""numeric":"not-a-decimal""#)
        ZerionMockURLProtocol.respond { _ in
            .init(data: Data(invalid.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))

        let positions = try await provider.fetchPositions(context: makeSyncContext(chain: .ethereum))

        #expect(Set(positions.flatMap(\.tokens).map(\.symbol)) == ["USDT", "WETH"])
    }

    @Test func `mismatched implementation chain skips only the malformed resource`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        let invalid = Self.positionsFixture.replacingOccurrences(
            of: #""implementations": [{"chain_id":"ethereum","address":null,"decimals":18}]"#,
            with: #""implementations": [{"chain_id":"base","address":null,"decimals":18}]"#)
        ZerionMockURLProtocol.respond { _ in
            .init(data: Data(invalid.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))

        let positions = try await provider.fetchPositions(context: makeSyncContext(chain: .ethereum))

        #expect(Set(positions.flatMap(\.tokens).map(\.symbol)) == ["USDT", "WETH"])
    }

    @Test func `current prices match reordered implementations and normalize percent`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        ZerionMockURLProtocol.respond { request in
            let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(request.url?.absoluteString.hasPrefix("https://api.zerion.io/v1/fungibles/?") == true)
            #expect(query["filter[fungible_implementations]"] == "base:0xabc,ethereum")
            return .init(data: Data(#"""
            {"data":[
              {"type":"fungibles","id":"opaque-contract","attributes":{
                "market_data":{"price":2.5,"changes":{"percent_1d":-4.25}},
                "implementations":[{"chain_id":"base","address":"0xAbC","decimals":18}]
              }},
              {"type":"fungibles","id":"opaque-native","attributes":{
                "market_data":{"price":2000,"changes":{"percent_1d":5}},
                "implementations":[{"chain_id":"ethereum","address":null,"decimals":18}]
              }}
            ],"links":{}}
            """#.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))
        let native = OnchainTokenIdentity.native(on: .ethereum)
        let contract = OnchainTokenIdentity(chain: .base, contractAddress: "0xABC")

        let update = try await provider.fetchPriceUpdate(for: [native, contract, native])

        #expect(update.prices[native.historicalPriceID] == 2000)
        #expect(update.changes24h[native.historicalPriceID] == Decimal(string: "0.05"))
        #expect(update.prices[contract.historicalPriceID] == Decimal(string: "2.5"))
        #expect(update.changes24h[contract.historicalPriceID] == Decimal(string: "-0.0425"))
    }

    @Test func `current prices skip unsupported identities without dropping supported prices`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        ZerionMockURLProtocol.respond { request in
            let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(query["filter[fungible_implementations]"] == "base:0xabc")
            return .init(data: Data(#"""
            {"data":[
              {"type":"fungibles","id":"supported","attributes":{
                "market_data":{"price":2.5,"changes":{"percent_1d":1}},
                "implementations":[{"chain_id":"base","address":"0xAbC","decimals":18}]
              }}
            ],"links":{}}
            """#.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))
        let supported = OnchainTokenIdentity(chain: .base, contractAddress: "0xABC")
        let unsupported = OnchainTokenIdentity(chain: .bitcoin, contractAddress: "native")

        let update = try await provider.fetchPriceUpdate(for: [unsupported, supported])

        #expect(update.prices.count == 1)
        #expect(update.prices[supported.historicalPriceID] == Decimal(string: "2.5"))
        #expect(update.changes24h.count == 1)
        #expect(update.changes24h[supported.historicalPriceID] == Decimal(string: "0.01"))
    }

    @Test func `historical chart uses seconds and keeps latest point per UTC day`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        ZerionMockURLProtocol.respond { request in
            let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(request.url?.path == "/v1/fungibles/by-implementation/charts/month")
            #expect(query["implementation"] == "ethereum")
            #expect(query["currency"] == "usd")
            return .init(data: Data(#"""
            {"data":{"type":"fungible_charts","id":"eth","attributes":{
              "begin_at":"2026-07-25T00:00:00Z","end_at":"2026-07-26T00:00:00Z",
              "points":[[1784937600,1900],[1784941200,1910],[1785024000,1920]]
            }}}
            """#.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))
        let identity = OnchainTokenIdentity.native(on: .ethereum)

        let history = try await provider.fetchHistoricalPrices(identity: identity, days: 30)

        #expect(history.count == 2)
        #expect(history[0].timestamp == Date(timeIntervalSince1970: 1_784_941_200))
        #expect(history[0].price == 1910)
        #expect(history[0].source == .zerion)
        #expect(history[1].timestamp == Date(timeIntervalSince1970: 1_785_024_000))
    }

    @Test func `historical chart excludes points older than the requested horizon`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        let now = Date.now
        let oldTimestamp = Int(now.addingTimeInterval(-120 * 86400).timeIntervalSince1970)
        let recentTimestamp = Int(now.addingTimeInterval(-30 * 86400).timeIntervalSince1970)
        let response = """
        {"data":{"type":"fungible_charts","id":"eth","attributes":{
          "begin_at":"2026-01-01T00:00:00Z","end_at":"2026-07-26T00:00:00Z",
          "points":[[\(oldTimestamp),1800],[\(recentTimestamp),2000]]
        }}}
        """
        ZerionMockURLProtocol.respond { request in
            #expect(request.url?.path == "/v1/fungibles/by-implementation/charts/year")
            return .init(data: Data(response.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))

        let history = try await provider.fetchHistoricalPrices(
            identity: .native(on: .ethereum),
            days: 90)

        #expect(history.map(\.timestamp) == [Date(timeIntervalSince1970: TimeInterval(recentTimestamp))])
    }

    // swiftlint:disable line_length
    private static let positionsFixture = #"""
    {
      "data": [
        {
          "type": "positions",
          "id": "native",
          "attributes": {
            "name": "Asset",
            "position_type": "wallet",
            "quantity": {"int":"1123456789012345678","decimals":18,"float":1.123,"numeric":"1.123456789012345678"},
            "value": null,
            "price": null,
            "fungible_info": {
              "name": "Ethereum",
              "symbol": "ETH",
              "icon": {"url":"https://img.example/eth.png"},
              "flags": {"verified":true},
              "implementations": [{"chain_id":"ethereum","address":null,"decimals":18}]
            },
            "flags": {"displayable":true,"is_trash":false}
          },
          "relationships": {
            "chain": {"data":{"type":"chains","id":"ethereum"}},
            "fungible": {"data":{"type":"fungibles","id":"eth"}}
          }
        },
        {
          "type": "positions",
          "id": "weth-lp",
          "attributes": {
            "name": "Uniswap V2 WETH/USDT Pool",
            "parent": null,
            "protocol": "Uniswap V2",
            "protocol_module": "liquidity_pool",
            "group_id": "lp-group",
            "position_type": "deposit",
            "quantity": {"int":"1","decimals":18,"float":0.1,"numeric":"0.1"},
            "value": 210,
            "price": 2100,
            "fungible_info": {
              "name":"Wrapped Ether","symbol":"WETH","icon":{"url":"https://img.example/weth.png"},
              "flags":{"verified":true},
              "implementations":[{"chain_id":"ethereum","address":"0xC02","decimals":18}]
            },
            "flags":{"displayable":true,"is_trash":false},
            "application_metadata":{"name":"Uniswap V2","icon":{"url":"https://img.example/uniswap.png"}},
            "receipt":{"fungible_info":{"name":"Uniswap LP","symbol":"UNI-V2","implementations":[{"chain_id":"ethereum","address":"0xLP","decimals":18}]}}
          },
          "relationships":{
            "chain":{"data":{"type":"chains","id":"ethereum"}},
            "dapp":{"data":{"type":"dapps","id":"uniswap-v2"}},
            "fungible":{"data":{"type":"fungibles","id":"weth"}}
          }
        },
        {
          "type": "positions",
          "id": "usdt-lp",
          "attributes": {
            "name": "Uniswap V2 WETH/USDT Pool",
            "parent": null,
            "protocol": "Uniswap V2",
            "protocol_module": "liquidity_pool",
            "group_id": "lp-group",
            "position_type": "deposit",
            "quantity": {"int":"200000000","decimals":6,"float":200,"numeric":"200.000000"},
            "value": 200,
            "price": 1,
            "fungible_info": {
              "name":"Tether USD","symbol":"USDT","icon":{"url":"https://img.example/usdt.png"},
              "flags":{"verified":true},
              "implementations":[{"chain_id":"ethereum","address":"0xUSDT","decimals":6}]
            },
            "flags":{"displayable":true,"is_trash":false},
            "application_metadata":{"name":"Uniswap V2","icon":{"url":"https://img.example/uniswap.png"}},
            "receipt":{"fungible_info":{"name":"Uniswap LP","symbol":"UNI-V2","implementations":[{"chain_id":"ethereum","address":"0xLP","decimals":18}]}}
          },
          "relationships":{
            "chain":{"data":{"type":"chains","id":"ethereum"}},
            "dapp":{"data":{"type":"dapps","id":"uniswap-v2"}},
            "fungible":{"data":{"type":"fungibles","id":"usdt"}}
          }
        }
      ],
      "links": {"self":"https://api.zerion.io/v1/wallets/fixture/positions/"}
    }
    """#
    // swiftlint:enable line_length
}

private extension String {
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}

@Suite(.serialized)
struct ZerionProviderLiveTests {
    @Test func `live smoke uses one combined position request when explicitly enabled`() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["PORTU_ZERION_LIVE_TESTS"] == "1",
            let apiKey = environment["ZERION_API_KEY"],
            !apiKey.isEmpty
        else { return }

        let address = environment["ZERION_SMOKE_ADDRESS"]
            ?? "0x00000000219ab540356cBB839CBe05303d7705Fa"
        let context = SyncContext(
            accountId: UUID(),
            kind: .wallet,
            addresses: [(address, .ethereum)],
            exchangeType: nil)
        let provider = ZerionProvider(client: ZerionAPIClient(apiKey: { apiKey }))

        let positions = try await provider.fetchPositions(context: context)

        #expect(!positions.isEmpty)
    }
}

#if DEBUG

    import Foundation
    @testable import Portu
    import PortuCore
    import SwiftData
    import Testing

    /// `GET /state/portfolio/timings`: the read model's most recent build and valuation (#123, T1).
    @MainActor
    struct DebugPortfolioTimingsTests {
        @Test func `the route serves the most recent durations in milliseconds`() throws {
            let response = DebugEndpoints.portfolioTimings(PortfolioTimings.Snapshot(
                projectionBuild: .milliseconds(42) + .microseconds(500),
                valuation: .microseconds(3250)))
            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])

            #expect(response.statusCode == 200)
            #expect(json["projectionBuildMs"] as? Double == 42.5)
            #expect(json["valuationMs"] as? Double == 3.25)
        }

        @Test func `a duration not yet measured is null`() throws {
            let response = DebugEndpoints.portfolioTimings(PortfolioTimings.Snapshot())
            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])

            #expect(json["projectionBuildMs"] is NSNull)
            #expect(json["valuationMs"] is NSNull)
        }

        /// A build and a live valuation each record their duration, and the debug server serves them
        /// on the route. The snapshot is process-wide, so this checks only that both are measured.
        @Test func `a build and a valuation are measured and served`() async throws {
            let container = try ModelContainerFactory().makeInMemory()
            let projector = await PortfolioProjectorClient.makeProjector(modelContainer: container)
            let projection = try await projector.build(PortfolioProjectionRequest(isHistoricalBackfillEnabled: false, now: .now))
            _ = await PortfolioValuator.liveValue.value(PortfolioValuationRequest(
                projection: projection,
                prices: PortfolioPriceInputs(livePricesUSD: [:], liveChanges24h: [:], usdToDisplayRate: 1, currency: .usd),
                settings: .defaults))

            let server = DebugServer(port: 0, modelContainer: container)
            try await server.start()
            defer { server.stop() }
            let port = try #require(server.listeningPort)
            let (data, response) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:\(port)/state/portfolio/timings")))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(json["projectionBuildMs"] is Double)
            #expect(json["valuationMs"] is Double)
        }
    }

#endif

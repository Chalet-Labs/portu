#if DEBUG

    import Foundation
    @testable import Portu
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
    }

#endif

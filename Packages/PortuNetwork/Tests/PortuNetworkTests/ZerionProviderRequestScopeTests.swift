import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

@Suite(.serialized)
struct ZerionProviderRequestScopeTests {
    @Test func `generic EVM scope absorbs overlapping explicit chain for same address`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        ZerionMockURLProtocol.respond { _ in
            .init(data: Data(#"{"data":[],"links":{}}"#.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))
        let context = makeSyncContext(addresses: [
            ("0xAbC", nil),
            ("0xabc", .ethereum)
        ])

        _ = try await provider.fetchPositions(context: context)

        let requests = ZerionMockURLProtocol.requests
        #expect(requests.count == 1)
        let requestURL = try #require(requests.first?.url)
        let components = try #require(URLComponents(
            url: requestURL,
            resolvingAgainstBaseURL: false))
        let chainIDs = try #require(components
            .queryItems?
            .first { $0.name == "filter[chain_ids]" }?
            .value)
        #expect(chainIDs.split(separator: ",").contains("ethereum"))
    }
}

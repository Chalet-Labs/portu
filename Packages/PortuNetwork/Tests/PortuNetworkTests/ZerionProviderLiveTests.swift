import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

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

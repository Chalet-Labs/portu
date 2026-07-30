import Foundation
@testable import Portu
import PortuCore
import Testing

struct PortfolioAnalyticsScopeFactoryTests {
    @Test func `one EVM plus one Solana address offers wallet set and individual fallbacks`() throws {
        let input = makeInput(addresses: [
            .init(chain: .solana, address: "8BH9pjtgyZDC4iAQH5ZiYDZ1MDWC98xki2V8NzqqKW3K"),
            .init(chain: nil, address: "0x1111111111111111111111111111111111111111")
        ])

        let options = PortfolioAnalyticsScopeFactory.scopeOptions(account: input)
        let option = try #require(options.first)

        #expect(options.count == 3)
        #expect(option.label == "EVM + Solana")
        #expect(option.scope.addresses.count == 2)
        #expect(options.dropFirst().allSatisfy { $0.scope.addresses.count == 1 })
    }

    @Test func `multiple EVM addresses produce separate scopes without combined total`() {
        let input = makeInput(addresses: [
            .init(chain: nil, address: "0x2222222222222222222222222222222222222222"),
            .init(chain: nil, address: "0x1111111111111111111111111111111111111111")
        ])

        let options = PortfolioAnalyticsScopeFactory.scopeOptions(account: input)

        #expect(options.count == 2)
        #expect(options.allSatisfy { $0.scope.addresses.count == 1 })
        #expect(options.map(\.scope.addresses.first?.value) == [
            "0x1111111111111111111111111111111111111111",
            "0x2222222222222222222222222222222222222222"
        ])
    }

    @Test func `invalid and unsupported addresses do not create analytics scopes`() {
        let input = makeInput(addresses: [
            .init(chain: nil, address: "not-an-evm-address"),
            .init(chain: .solana, address: "0OIl"),
            .init(chain: .bitcoin, address: "bc1qexample")
        ])

        #expect(PortfolioAnalyticsScopeFactory.scopeOptions(account: input).isEmpty)
    }

    @Test func `validated addresses trim normalize and deduplicate after family detection`() {
        let input = makeInput(addresses: [
            .init(chain: .ethereum, address: " 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "),
            .init(chain: nil, address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            .init(chain: .solana, address: "8BH9pjtgyZDC4iAQH5ZiYDZ1MDWC98xki2V8NzqqKW3K")
        ])

        let options = PortfolioAnalyticsScopeFactory.scopeOptions(account: input)

        #expect(options.count == 3)
        #expect(options.first?.scope.addresses.map(\.value) == [
            "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "8BH9pjtgyZDC4iAQH5ZiYDZ1MDWC98xki2V8NzqqKW3K"
        ])
    }

    private func makeInput(
        addresses: [PortfolioAnalyticsAddressInput]) -> PortfolioAnalyticsAccountInput {
        PortfolioAnalyticsAccountInput(
            id: UUID(),
            dataSource: .zerion,
            isActive: true,
            addresses: addresses,
            implementations: [])
    }
}

import Foundation
@testable import Portu
import PortuCore
import Testing

struct PortfolioAnalyticsScopeFactoryTests {
    @Test func `one EVM plus one Solana address offers wallet set and individual fallbacks`() throws {
        let implementation = OnchainTokenIdentity(
            chain: .ethereum,
            contractAddress: "0x3333333333333333333333333333333333333333")
        let input = makeInput(addresses: [
            .init(chain: .solana, address: "8BH9pjtgyZDC4iAQH5ZiYDZ1MDWC98xki2V8NzqqKW3K"),
            .init(chain: .base, address: "0x1111111111111111111111111111111111111111")
        ], implementations: [implementation])

        let options = PortfolioAnalyticsScopeFactory.scopeOptions(account: input)
        let option = try #require(options.first)

        #expect(options.count == 3)
        #expect(option.label == "EVM + Solana")
        #expect(option.scope.addresses.count == 2)
        #expect(option.scope.chainIDs == ["base", "solana"])
        #expect(options.dropFirst().allSatisfy { $0.scope.addresses.count == 1 })
        #expect(PortfolioAnalyticsScopeFactory.scopeCoversEntireAccount(
            option.scope,
            account: input))
        #expect(PortfolioAnalyticsScopeFactory.scopeCoversEntireAccount(
            options[1].scope,
            account: input) == false)

        let context = try #require(PortfolioAnalyticsScopeFactory.requestContext(
            account: input,
            chartRange: .oneMonth,
            currency: .usd,
            asOf: Date(timeIntervalSince1970: 1_704_153_600)))
        #expect(context.fallbackScopeFingerprint == options[1].id)
        #expect(context.isFullAccountScope)
        #expect(context.implementations == [implementation])
    }

    @Test func `explicit chains use Zerion analytics identifiers`() throws {
        let input = makeInput(addresses: [
            .init(chain: .bsc, address: "0x1111111111111111111111111111111111111111")
        ])

        let option = try #require(PortfolioAnalyticsScopeFactory.scopeOptions(account: input).first)

        #expect(option.scope.chainIDs == ["binance-smart-chain"])
    }

    @Test func `multiple EVM addresses produce separate scopes without combined total`() {
        let implementation = OnchainTokenIdentity(
            chain: .ethereum,
            contractAddress: "0x3333333333333333333333333333333333333333")
        let input = makeInput(addresses: [
            .init(chain: nil, address: "0x2222222222222222222222222222222222222222"),
            .init(chain: nil, address: "0x1111111111111111111111111111111111111111")
        ], implementations: [implementation])

        let options = PortfolioAnalyticsScopeFactory.scopeOptions(account: input)
        let context = PortfolioAnalyticsScopeFactory.requestContext(
            account: input,
            chartRange: .oneMonth,
            currency: .usd,
            asOf: .now)

        #expect(options.count == 2)
        #expect(options.allSatisfy { $0.scope.addresses.count == 1 })
        #expect(options.allSatisfy {
            PortfolioAnalyticsScopeFactory.scopeCoversEntireAccount(
                $0.scope,
                account: input) == false
        })
        #expect(options.map(\.scope.addresses.first?.value) == [
            "0x1111111111111111111111111111111111111111",
            "0x2222222222222222222222222222222222222222"
        ])
        #expect(context?.isFullAccountScope == false)
        #expect(context?.implementations.isEmpty == true)
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
        #expect(options.first?.scope.chainIDs == [])
        #expect(options.first {
            $0.scope.addresses.first?.family == .evm
        }?.scope.chainIDs == [])
    }

    private func makeInput(
        addresses: [PortfolioAnalyticsAddressInput],
        implementations: [OnchainTokenIdentity] = []) -> PortfolioAnalyticsAccountInput {
        PortfolioAnalyticsAccountInput(
            id: UUID(),
            dataSource: .zerion,
            isActive: true,
            addresses: addresses,
            implementations: implementations)
    }
}

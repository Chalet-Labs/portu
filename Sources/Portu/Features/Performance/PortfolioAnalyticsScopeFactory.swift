import Foundation
import PortuCore
import PortuNetwork

struct PortfolioAnalyticsAddressInput: Equatable {
    let chain: Chain?
    let address: String
}

struct PortfolioAnalyticsAccountInput: Equatable {
    let id: UUID
    let dataSource: DataSource
    let isActive: Bool
    let addresses: [PortfolioAnalyticsAddressInput]
    let implementations: [OnchainTokenIdentity]
}

struct PortfolioAnalyticsScopeOption: Equatable, Identifiable {
    let label: String
    let scope: PortfolioAnalyticsScope

    var id: String {
        scope.fingerprint
    }
}

enum PortfolioAnalyticsScopeFactory {
    static func scopeOptions(
        account: PortfolioAnalyticsAccountInput) -> [PortfolioAnalyticsScopeOption] {
        let addresses = Array(Set(account.addresses.compactMap(validatedAddress))).sorted()
        guard addresses.isEmpty == false else { return [] }

        var options: [PortfolioAnalyticsScopeOption] = []
        if
            addresses.count == 2,
            Set(addresses.map(\.family)) == Set(PortfolioAnalyticsAddressFamily.allCases) {
            options.append(PortfolioAnalyticsScopeOption(
                label: "EVM + Solana",
                scope: PortfolioAnalyticsScope(
                    accountID: account.id,
                    dataSource: account.dataSource,
                    addresses: addresses)))
        }

        options.append(contentsOf: addresses.map { address in
            let matchingInput = account.addresses.first {
                PortfolioAnalyticsAddress(
                    family: $0.chain == .solana ? .solana : .evm,
                    value: $0.address) == address
            }
            let chainIDs = matchingInput?.chain.map { [$0.rawValue] } ?? []
            return PortfolioAnalyticsScopeOption(
                label: abbreviated(address.value),
                scope: PortfolioAnalyticsScope(
                    accountID: account.id,
                    dataSource: account.dataSource,
                    addresses: [address],
                    chainIDs: chainIDs))
        })
        return options
    }

    static func requestContext(
        account: PortfolioAnalyticsAccountInput,
        selectedScopeFingerprint: String? = nil,
        chartRange: ChartTimeRange,
        currency: FiatCurrency,
        asOf: Date) -> PortfolioAnalyticsRequestContext? {
        let options = scopeOptions(account: account)
        guard
            let scope = options.first(where: {
                $0.scope.fingerprint == selectedScopeFingerprint
            })?.scope ?? options.first?.scope else { return nil }
        return PortfolioAnalyticsRequestContext(
            scope: scope,
            chartRange: chartRange,
            currency: currency,
            implementations: Array(Set(account.implementations)).sorted {
                $0.canonicalPriceID < $1.canonicalPriceID
            },
            asOf: asOf,
            isAccountActive: account.isActive)
    }

    private static func abbreviated(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(7))…\(address.suffix(5))"
    }

    private static func validatedAddress(
        _ input: PortfolioAnalyticsAddressInput) -> PortfolioAnalyticsAddress? {
        if let chain = input.chain, ZerionChainMapping.supportsPositions(on: chain) == false {
            return nil
        }
        let address = PortfolioAnalyticsAddress(
            family: input.chain == .solana ? .solana : .evm,
            value: input.address)
        return address.isValid ? address : nil
    }
}

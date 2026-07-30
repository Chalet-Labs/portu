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
            let chainIDsByAddress = addresses.map { address in
                Self.chainIDs(for: address, in: account.addresses)
            }
            let chainIDs = chainIDsByAddress.allSatisfy { $0.isEmpty == false }
                ? chainIDsByAddress.flatMap(\.self)
                : []
            options.append(PortfolioAnalyticsScopeOption(
                label: "EVM + Solana",
                scope: PortfolioAnalyticsScope(
                    accountID: account.id,
                    dataSource: account.dataSource,
                    addresses: addresses,
                    chainIDs: chainIDs)))
        }

        options.append(contentsOf: addresses.map { address in
            PortfolioAnalyticsScopeOption(
                label: abbreviated(address.value),
                scope: PortfolioAnalyticsScope(
                    accountID: account.id,
                    dataSource: account.dataSource,
                    addresses: [address],
                    chainIDs: Self.chainIDs(for: address, in: account.addresses)))
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

    private static func chainIDs(
        for address: PortfolioAnalyticsAddress,
        in inputs: [PortfolioAnalyticsAddressInput]) -> [String] {
        let matchingInputs = inputs.filter { validatedAddress($0) == address }
        guard matchingInputs.allSatisfy({ $0.chain != nil }) else { return [] }
        return Array(Set(matchingInputs.compactMap(\.chain?.rawValue))).sorted()
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

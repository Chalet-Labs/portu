import Foundation
import PortuCore

extension ZerionProvider: ZerionAnalyticsService {
    public func fetchPortfolioValueHistory(
        scope: PortfolioAnalyticsScope,
        period: ZerionChartPeriod) async throws -> [ProviderPortfolioValueDTO] {
        let request = try analyticsRequest(for: scope, period: period)
        let coverage: PortfolioAnalyticsCoverage = scope.addresses.allSatisfy { $0.family == .evm }
            ? .noFilter
            : .providerReported
        let envelope: ZerionSingleEnvelope<ZerionWalletChartResource> = try await client.get(
            path: request.path,
            queryItems: request.queryItems)

        var latestByDay: [Date: ProviderPortfolioValueDTO] = [:]
        for point in envelope.data.attributes.points {
            guard
                let timestamp = point.timestamp,
                timestamp.isFinite,
                let value = point.value,
                value > 0
            else {
                continue
            }
            let date = Date(timeIntervalSince1970: timestamp)
            let normalized = ProviderPortfolioValueDTO(
                timestamp: date,
                usdValue: value,
                provider: .zerion,
                coverage: coverage)
            let day = normalized.day
            if latestByDay[day].map({ $0.timestamp < date }) ?? true {
                latestByDay[day] = normalized
            }
        }
        return latestByDay.values.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.usdValue < $1.usdValue
        }
    }

    public func fetchPnL(
        scope: PortfolioAnalyticsScope,
        range: ProviderPnLRange,
        currency: FiatCurrency,
        implementations: [OnchainTokenIdentity],
        asOf: Date) async throws -> ProviderPnLDTO {
        let baseRequest = try pnlRequest(
            for: scope,
            range: range,
            currency: currency,
            asOf: asOf)
        let overall: ZerionPnLEnvelope = try await client.get(
            path: baseRequest.path,
            queryItems: baseRequest.queryItems)

        let normalizedImplementations = try Array(Set(implementations.map {
            try pnlImplementation(for: $0)
        })).sorted()
        var assetsByImplementation: [String: ProviderPnLAssetDTO] = [:]
        var excluded = Set(overall.meta?.excludedFungibleIDs ?? [])
        excluded.formUnion(overall.meta?.excludedFungibleImplementations ?? [])
        for batch in try pnlImplementationBatches(
            normalizedImplementations,
            baseRequest: baseRequest) {
            try Task.checkCancellation()
            let filtered: ZerionPnLEnvelope = try await client.get(
                path: baseRequest.path,
                queryItems: baseRequest.queryItems + [
                    URLQueryItem(
                        name: "filter[fungible_implementations]",
                        value: batch.joined(separator: ","))
                ])
            for (implementationID, metrics) in filtered.data.attributes.breakdown?.byImplementation ?? [:] {
                assetsByImplementation[implementationID] = assetDTO(
                    implementationID: implementationID,
                    metrics: metrics)
            }
            excluded.formUnion(filtered.meta?.excludedFungibleIDs ?? [])
            excluded.formUnion(filtered.meta?.excludedFungibleImplementations ?? [])
        }

        let metrics = overall.data.attributes
        return ProviderPnLDTO(
            range: range,
            currency: currency,
            totalGain: metrics.totalGain,
            realizedGain: metrics.realizedGain,
            unrealizedGain: metrics.unrealizedGain,
            relativeTotalGain: normalizedPercentage(metrics.relativeTotalGainPercentage),
            relativeRealizedGain: normalizedPercentage(metrics.relativeRealizedGainPercentage),
            relativeUnrealizedGain: normalizedPercentage(metrics.relativeUnrealizedGainPercentage),
            totalFee: metrics.totalFee,
            totalInvested: metrics.totalInvested,
            realizedCostBasis: metrics.realizedCostBasis,
            netInvested: metrics.netInvested,
            receivedExternal: metrics.receivedExternal,
            sentExternal: metrics.sentExternal,
            sentForNFTs: metrics.sentForNFTs,
            receivedForNFTs: metrics.receivedForNFTs,
            excludedIdentifiers: Array(excluded),
            assets: Array(assetsByImplementation.values),
            fetchedAt: asOf)
    }

    public func fetchPortfolioSummary(
        scope: PortfolioAnalyticsScope) async throws -> ZerionPortfolioSummary {
        let request = try portfolioRequest(for: scope)
        let envelope: ZerionPortfolioEnvelope = try await client.get(
            path: request.path,
            queryItems: request.queryItems)
        let attributes = envelope.data.attributes
        return ZerionPortfolioSummary(
            totalPositions: attributes.total.positions,
            positionsByChain: attributes.positionsDistributionByChain,
            positionsByType: attributes.positionsDistributionByType,
            absoluteChange1D: attributes.changes?.absolute1D,
            relativeChange1D: normalizedPercentage(attributes.changes?.percent1D))
    }
}

private extension ZerionProvider {
    struct AnalyticsRequest {
        let path: String
        let queryItems: [URLQueryItem]
    }

    func pnlRequest(
        for scope: PortfolioAnalyticsScope,
        range: ProviderPnLRange,
        currency: FiatCurrency,
        asOf: Date) throws -> AnalyticsRequest {
        guard scope.dataSource == .zerion else {
            throw ZerionError.unsupportedAnalyticsScope
        }
        try validate(addresses: scope.addresses)

        let path: String
        var queryItems: [URLQueryItem] = []
        if scope.addresses.count == 1, let address = scope.addresses.first {
            path = "wallets/\(address.value)/pnl"
        } else if
            scope.addresses.count == 2,
            Set(scope.addresses.map(\.family)) == Set(PortfolioAnalyticsAddressFamily.allCases) {
            path = "wallet-sets/pnl"
            queryItems.append(URLQueryItem(
                name: "addresses",
                value: scope.addresses.map(\.value).joined(separator: ",")))
        } else {
            throw ZerionError.unsupportedAnalyticsScope
        }

        let chainIDs = try analyticsChainIDs(for: scope)
        guard chainIDs.count <= 25 else {
            throw ZerionError.invalidData("wallet PnL supports at most 25 chains")
        }
        queryItems.append(URLQueryItem(name: "currency", value: currency.rawValue))
        queryItems.append(URLQueryItem(
            name: "filter[chain_ids]",
            value: chainIDs.joined(separator: ",")))
        if let since = range.zerionSinceMilliseconds(asOf: asOf) {
            queryItems.append(URLQueryItem(name: "since", value: since))
        }
        return AnalyticsRequest(path: path, queryItems: queryItems)
    }

    func analyticsRequest(
        for scope: PortfolioAnalyticsScope,
        period: ZerionChartPeriod) throws -> AnalyticsRequest {
        guard scope.dataSource == .zerion else {
            throw ZerionError.unsupportedAnalyticsScope
        }
        try validate(addresses: scope.addresses)

        let path: String
        var queryItems: [URLQueryItem] = []
        if scope.addresses.count == 1, let address = scope.addresses.first {
            path = "wallets/\(address.value)/charts/\(period.rawValue)"
        } else if
            scope.addresses.count == 2,
            Set(scope.addresses.map(\.family)) == Set(PortfolioAnalyticsAddressFamily.allCases) {
            path = "wallet-sets/charts/\(period.rawValue)"
            queryItems.append(URLQueryItem(
                name: "addresses",
                value: scope.addresses.map(\.value).joined(separator: ",")))
        } else {
            throw ZerionError.unsupportedAnalyticsScope
        }

        let chainIDs = try analyticsChainIDs(for: scope)
        guard chainIDs.count <= 25 else {
            throw ZerionError.invalidData("wallet chart supports at most 25 chains")
        }
        queryItems.append(contentsOf: [
            URLQueryItem(name: "currency", value: "usd"),
            URLQueryItem(name: "filter[chain_ids]", value: chainIDs.joined(separator: ","))
        ])
        if scope.addresses.allSatisfy({ $0.family == .evm }) {
            queryItems.append(URLQueryItem(name: "filter[positions]", value: "no_filter"))
        }
        return AnalyticsRequest(path: path, queryItems: queryItems)
    }

    func portfolioRequest(
        for scope: PortfolioAnalyticsScope) throws -> AnalyticsRequest {
        guard scope.dataSource == .zerion else {
            throw ZerionError.unsupportedAnalyticsScope
        }
        try validate(addresses: scope.addresses)

        let path: String
        var queryItems: [URLQueryItem] = []
        if scope.addresses.count == 1, let address = scope.addresses.first {
            path = "wallets/\(address.value)/portfolio"
        } else if
            scope.addresses.count == 2,
            Set(scope.addresses.map(\.family)) == Set(PortfolioAnalyticsAddressFamily.allCases) {
            path = "wallet-sets/portfolio"
            queryItems.append(URLQueryItem(
                name: "addresses",
                value: scope.addresses.map(\.value).joined(separator: ",")))
        } else {
            throw ZerionError.unsupportedAnalyticsScope
        }
        queryItems.append(contentsOf: [
            URLQueryItem(name: "currency", value: "usd"),
            URLQueryItem(name: "filter[positions]", value: "no_filter"),
            URLQueryItem(name: "sync", value: "false")
        ])
        return AnalyticsRequest(path: path, queryItems: queryItems)
    }

    func analyticsChainIDs(for scope: PortfolioAnalyticsScope) throws -> [String] {
        let families = Set(scope.addresses.map(\.family))
        if scope.chainIDs.isEmpty {
            return ZerionChainMapping.analyticsChainIDs.filter { chainID in
                chainID == "solana" ? families.contains(.solana) : families.contains(.evm)
            }
        }

        let supported = Set(ZerionChainMapping.analyticsChainIDs)
        let mapped = try scope.chainIDs.map { rawValue -> String in
            if let chain = Chain.normalized(rawValue: rawValue) {
                return try ZerionChainMapping.positionID(for: chain)
            }
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard supported.contains(normalized) else {
                throw ZerionError.unsupportedChain(rawValue)
            }
            return normalized
        }
        return Array(Set(mapped)).sorted()
    }

    func validate(addresses: [PortfolioAnalyticsAddress]) throws {
        guard addresses.isEmpty == false else {
            throw ZerionError.unsupportedAnalyticsScope
        }
        for address in addresses {
            guard address.isValid else {
                throw ZerionError.invalidAddress(address.value)
            }
        }
    }

    func pnlImplementation(for identity: OnchainTokenIdentity) throws -> String {
        let implementation = try ZerionChainMapping.implementation(for: identity)
        return identity.contractAddress == OnchainTokenIdentity.nativeAssetSentinel
            ? "\(implementation):"
            : implementation
    }

    func pnlImplementationBatches(
        _ implementations: [String],
        baseRequest: AnalyticsRequest) throws -> [[String]] {
        let maximumImplementationCount = 100
        let maximumURLLength = 2000
        var batches: [[String]] = []
        var current: [String] = []

        for implementation in implementations {
            let candidate = current + [implementation]
            if
                candidate.count > maximumImplementationCount
                || pnlURLLength(for: candidate, baseRequest: baseRequest) > maximumURLLength {
                guard current.isEmpty == false else {
                    throw ZerionError.invalidData("PnL implementation filter exceeds safe URL length")
                }
                batches.append(current)
                current = [implementation]
                guard pnlURLLength(for: current, baseRequest: baseRequest) <= maximumURLLength else {
                    throw ZerionError.invalidData("PnL implementation filter exceeds safe URL length")
                }
            } else {
                current = candidate
            }
        }

        if current.isEmpty == false {
            batches.append(current)
        }
        return batches
    }

    func pnlURLLength(
        for implementations: [String],
        baseRequest: AnalyticsRequest) -> Int {
        var components = URLComponents(
            string: "https://api.zerion.io/v1/\(baseRequest.path)")!
        components.queryItems = baseRequest.queryItems + [
            URLQueryItem(
                name: "filter[fungible_implementations]",
                value: implementations.joined(separator: ","))
        ]
        return components.url?.absoluteString.count ?? .max
    }

    func assetDTO(
        implementationID: String,
        metrics: ZerionPnLMetrics) -> ProviderPnLAssetDTO {
        ProviderPnLAssetDTO(
            implementationID: implementationID,
            identity: try? ZerionChainMapping.identity(for: implementationID),
            averageBuyPrice: metrics.averageBuyPrice,
            averageSellPrice: metrics.averageSellPrice,
            totalGain: metrics.totalGain,
            realizedGain: metrics.realizedGain,
            unrealizedGain: metrics.unrealizedGain,
            relativeTotalGain: normalizedPercentage(metrics.relativeTotalGainPercentage),
            relativeRealizedGain: normalizedPercentage(metrics.relativeRealizedGainPercentage),
            relativeUnrealizedGain: normalizedPercentage(metrics.relativeUnrealizedGainPercentage),
            totalFee: metrics.totalFee,
            totalInvested: metrics.totalInvested,
            realizedCostBasis: metrics.realizedCostBasis,
            netInvested: metrics.netInvested,
            receivedExternal: metrics.receivedExternal,
            sentExternal: metrics.sentExternal,
            sentForNFTs: metrics.sentForNFTs,
            receivedForNFTs: metrics.receivedForNFTs)
    }

    func normalizedPercentage(_ percentagePoints: Decimal?) -> Decimal? {
        percentagePoints.map { $0 / 100 }
    }
}

import Foundation
import os
import PortuCore

public actor ZerionProvider: PortfolioDataProvider {
    private static let logger = Logger(subsystem: "com.portu.app", category: "ZerionProvider")

    private struct RequestKey: Hashable {
        let address: String
        let chainIDs: [String]
    }

    private struct GroupKey: Hashable {
        let chain: Chain
        let dappID: String
        let groupID: String
        let module: String
    }

    let client: ZerionAPIClient

    nonisolated public var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsTokenBalances: true,
            supportsDeFiPositions: true,
            supportsHealthFactors: false)
    }

    public init(client: ZerionAPIClient) {
        self.client = client
    }

    public func fetchPositions(context: SyncContext) async throws -> [PositionDTO] {
        try await fetch(context: context, positionFilter: "no_filter")
    }

    public func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        try await fetch(context: context, positionFilter: "only_simple")
            .filter { $0.positionType == .idle }
    }

    public func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        try await fetch(context: context, positionFilter: "only_complex")
            .filter { $0.positionType != .idle }
    }

    private func fetch(context: SyncContext, positionFilter: String) async throws -> [PositionDTO] {
        var resources: [ZerionPositionResource] = []
        for request in try requestKeys(for: context) {
            let effectivePositionFilter = request.chainIDs == ["solana"]
                ? "only_simple"
                : positionFilter
            var nextURL: URL?
            repeat {
                let envelope: ZerionCollectionEnvelope<ZerionPositionResource> = if let nextURL {
                    try await client.get(next: nextURL)
                } else {
                    try await client.get(
                        path: "wallets/\(request.address)/positions/",
                        queryItems: [
                            URLQueryItem(name: "currency", value: "usd"),
                            URLQueryItem(name: "filter[positions]", value: effectivePositionFilter),
                            URLQueryItem(name: "filter[trash]", value: "only_non_trash"),
                            URLQueryItem(name: "filter[chain_ids]", value: request.chainIDs.joined(separator: ","))
                        ])
                }
                resources.append(contentsOf: envelope.data)
                nextURL = envelope.links?.next
            } while nextURL != nil
        }
        return try positions(from: resources)
    }

    private func requestKeys(for context: SyncContext) throws -> [RequestKey] {
        var keys = Set<RequestKey>()
        for addressEntry in context.addresses {
            let address = addressEntry.address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { continue }
            let chunks: [[String]] = if let chain = addressEntry.chain {
                try [[ZerionChainMapping.positionID(for: chain)]]
            } else {
                ZerionChainMapping.genericEVMChainIDChunks
            }
            for chainIDs in chunks {
                keys.insert(RequestKey(address: address, chainIDs: chainIDs))
            }
        }
        return keys.sorted {
            if $0.address != $1.address { return $0.address < $1.address }
            return $0.chainIDs.lexicographicallyPrecedes($1.chainIDs)
        }
    }

    private func positions(from resources: [ZerionPositionResource]) throws -> [PositionDTO] {
        var simple: [PositionDTO] = []
        var grouped: [GroupKey: (metadata: ZerionPositionResource, tokens: [TokenDTO])] = [:]

        for resource in resources {
            do {
                let chainID = try required(resource.relationships.chain.data?.id, context: "missing chain")
                let chain = try ZerionChainMapping.chain(for: chainID)
                let token = try token(from: resource, chain: chain, chainID: chainID)
                let dappID = resource.relationships.dapp?.data?.id

                if resource.attributes.positionType == "wallet", dappID == nil {
                    simple.append(PositionDTO(
                        positionType: .idle,
                        chain: chain,
                        protocolId: nil,
                        protocolName: nil,
                        protocolLogoURL: nil,
                        healthFactor: nil,
                        tokens: [token]))
                    continue
                }

                guard chain != .solana else {
                    throw ZerionError.unsupportedChain(Chain.solana.rawValue)
                }
                let resolvedDappID = dappID ?? resource.attributes.protocol ?? "unknown"
                let groupID = resource.attributes.groupID ?? resource.attributes.parent ?? resource.id
                let module = resource.attributes.protocolModule ?? "other"
                let key = GroupKey(chain: chain, dappID: resolvedDappID, groupID: groupID, module: module)
                if grouped[key] == nil {
                    grouped[key] = (resource, [])
                }
                grouped[key]?.tokens.append(token)
            } catch {
                Self.logger.error(
                    "Skipping malformed Zerion position \(resource.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        let complex = grouped.map { key, group -> PositionDTO in
            let attributes = group.metadata.attributes
            return PositionDTO(
                positionType: positionType(for: key.module),
                chain: key.chain,
                protocolId: key.dappID,
                protocolName: attributes.applicationMetadata?.name ?? attributes.protocol,
                protocolLogoURL: attributes.applicationMetadata?.icon?.url,
                healthFactor: nil,
                tokens: group.tokens.sorted {
                    if $0.symbol != $1.symbol { return $0.symbol < $1.symbol }
                    return ($0.contractAddress ?? "") < ($1.contractAddress ?? "")
                })
        }

        return (simple + complex).sorted {
            if ($0.chain?.rawValue ?? "") != ($1.chain?.rawValue ?? "") {
                return ($0.chain?.rawValue ?? "") < ($1.chain?.rawValue ?? "")
            }
            if $0.positionType.rawValue != $1.positionType.rawValue {
                return $0.positionType.rawValue < $1.positionType.rawValue
            }
            return ($0.protocolId ?? "") < ($1.protocolId ?? "")
        }
    }

    private func token(
        from resource: ZerionPositionResource,
        chain: Chain,
        chainID: String) throws -> TokenDTO {
        let attributes = resource.attributes
        let fungible = try required(attributes.fungibleInfo, context: "missing fungible info")
        let implementation = try required(
            fungible.implementations.first { $0.chainID == chainID },
            context: "missing \(chainID) implementation")
        guard let parsedAmount = Decimal(string: attributes.quantity.numeric, locale: Locale(identifier: "en_US_POSIX")) else {
            throw ZerionError.invalidData("invalid quantity")
        }
        let amount = parsedAmount < 0 ? -parsedAmount : parsedAmount
        let value = attributes.value ?? 0
        let address = implementation.address?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let identity = if let address, !address.isEmpty {
            OnchainTokenIdentity(chain: chain, contractAddress: address)
        } else {
            OnchainTokenIdentity.native(on: chain)
        }

        return TokenDTO(
            role: tokenRole(for: attributes.positionType),
            symbol: fungible.symbol ?? attributes.name ?? "Unknown",
            name: fungible.name ?? attributes.name ?? "Unknown",
            amount: amount,
            usdValue: value < 0 ? -value : value,
            chain: chain,
            contractAddress: identity.contractAddress,
            debankId: nil,
            coinGeckoId: nil,
            sourceKey: identity.canonicalPriceID,
            logoURL: fungible.icon?.url,
            category: attributes.positionType == "wallet" ? .other : .defi,
            isVerified: fungible.flags?.verified ?? false)
    }

    private func tokenRole(for positionType: String) -> TokenRole {
        switch positionType {
        case "loan": .borrow
        case "reward": .reward
        case "locked", "staked": .stake
        case "wallet": .balance
        case "deposit", "investment": .supply
        default: .supply
        }
    }

    private func positionType(for module: String) -> PositionType {
        switch module {
        case "lending": .lending
        case "liquidity_pool": .liquidityPool
        case "staked", "nft_staked": .staking
        case "farming", "leveraged_farming", "yield": .farming
        case "vesting", "locked": .vesting
        default: .other
        }
    }

    private func required<T>(_ value: T?, context: String) throws -> T {
        guard let value else {
            throw ZerionError.invalidData(context)
        }
        return value
    }
}

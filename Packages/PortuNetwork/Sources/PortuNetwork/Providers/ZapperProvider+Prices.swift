import Foundation
import PortuCore

public extension ZapperProvider {
    func fetchPriceUpdate(for identities: [OnchainTokenIdentity]) async throws -> PriceUpdate {
        let uniqueIdentities = Array(Set(identities))
        guard !uniqueIdentities.isEmpty else {
            return PriceUpdate(prices: [:], changes24h: [:])
        }

        var prices: [String: Decimal] = [:]
        var changes24h: [String: Decimal] = [:]

        // Issue one request per chain so each response can be matched by address alone —
        // Zapper's `fungibleTokenBatchV2` does not guarantee response order matches input
        // order, and the response rows only carry `address` (not chainId), so a single
        // address could otherwise collide across chains.
        let byChain = Dictionary(grouping: uniqueIdentities, by: \.chain)
        for chain in byChain.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let chainId = Self.chainIds[chain] else {
                throw ZapperError.unsupportedChain(chain)
            }
            let chainIdentities = byChain[chain, default: []]
                .sorted { $0.contractAddress < $1.contractAddress }
            for chunk in chainIdentities.chunked(size: 100) {
                let inputs = chunk.map { identity -> FungibleTokenInputV2 in
                    FungibleTokenInputV2(address: identity.contractAddress, chainId: chainId)
                }
                let response: GraphQLResponse<TokenPriceBatchData> = try await performGraphQL(
                    query: Self.tokenPriceBatchQuery,
                    variables: TokenPriceBatchVariables(tokens: inputs))
                let rows = try response.payload().fungibleTokenBatchV2

                var rowsByAddress: [String: ZapperFungibleTokenV2] = [:]
                for row in rows {
                    guard let row, let address = row.address?.lowercased(), !address.isEmpty else { continue }
                    rowsByAddress[address] = row
                }

                for identity in chunk {
                    guard
                        let row = rowsByAddress[identity.contractAddress],
                        let priceData = row.priceData
                    else { continue }
                    let key = identity.historicalPriceID
                    if let price = priceData.price, price.isFinite, price > 0 {
                        prices[key] = NSNumber(value: price).decimalValue
                    }
                    if let change = priceData.priceChange24h, change.isFinite {
                        changes24h[key] = NSNumber(value: change).decimalValue / 100
                    }
                }
            }
        }

        return PriceUpdate(prices: prices, changes24h: changes24h)
    }

    func fetchHistoricalPrices(
        identity: OnchainTokenIdentity,
        days: Int) async throws -> [HistoricalPriceDTO] {
        guard let chainId = Self.chainIds[identity.chain] else {
            throw ZapperError.unsupportedChain(identity.chain)
        }
        let variables = TokenPriceTicksVariables(
            address: identity.contractAddress,
            chainId: chainId,
            currency: "USD",
            timeFrame: Self.timeFrame(for: days))
        let response: GraphQLResponse<TokenPriceTicksData> = try await performGraphQL(
            query: Self.tokenPriceTicksQuery,
            variables: variables)
        let ticks = try response.payload().fungibleTokenV2?.priceData?.priceTicks ?? []
        let dtos = ticks.compactMap { tick -> HistoricalPriceDTO? in
            guard tick.close.isFinite, tick.close > 0, tick.timestamp.isFinite else { return nil }
            let timestamp = Date(timeIntervalSince1970: tick.timestamp / 1000)
            return HistoricalPriceDTO(
                coinGeckoId: identity.historicalPriceID,
                timestamp: timestamp,
                usdPrice: NSNumber(value: tick.close).decimalValue,
                source: .zapper)
        }
        logFilteredTicks(ticks, dtos: dtos, identity: identity)

        var latestByDay: [Date: HistoricalPriceDTO] = [:]
        for dto in dtos {
            if let existing = latestByDay[dto.day], existing.timestamp >= dto.timestamp {
                continue
            }
            latestByDay[dto.day] = dto
        }
        return latestByDay.values.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            return $0.timestamp < $1.timestamp
        }
    }
}

private extension ZapperProvider {
    static func timeFrame(for days: Int) -> String {
        switch max(days, 1) {
        case 1:
            "DAY"
        case 2 ... 7:
            "WEEK"
        case 8 ... 31:
            "MONTH"
        default:
            "YEAR"
        }
    }

    func logFilteredTicks(
        _ ticks: [ZapperPriceTick],
        dtos: [HistoricalPriceDTO],
        identity: OnchainTokenIdentity) {
        if !ticks.isEmpty, dtos.isEmpty {
            Self.logger.warning(
                "Zapper filtered all \(ticks.count, privacy: .public) price ticks for \(identity.historicalPriceID, privacy: .public).")
        } else if ticks.isEmpty {
            Self.logger.notice(
                "Zapper returned no price history for \(identity.historicalPriceID, privacy: .public) over the requested window.")
        }
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let nextIndex = Swift.min(index + size, endIndex)
            chunks.append(Array(self[index ..< nextIndex]))
            index = nextIndex
        }
        return chunks
    }
}

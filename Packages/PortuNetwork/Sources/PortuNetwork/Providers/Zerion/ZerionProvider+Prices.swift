import Foundation
import PortuCore

public extension ZerionProvider {
    func fetchPriceUpdate(for identities: [OnchainTokenIdentity]) async throws -> PriceUpdate {
        let unique = Array(Set(identities)).sorted {
            if $0.chain.rawValue != $1.chain.rawValue { return $0.chain.rawValue < $1.chain.rawValue }
            return $0.contractAddress < $1.contractAddress
        }
        guard !unique.isEmpty else {
            return PriceUpdate(prices: [:], changes24h: [:])
        }

        let requested = unique.reduce(into: [String: OnchainTokenIdentity]()) { result, identity in
            guard let implementation = try? ZerionChainMapping.implementation(for: identity) else {
                return
            }
            result[implementation] = identity
        }
        var prices: [String: Decimal] = [:]
        var changes: [String: Decimal] = [:]

        for chunk in implementationChunks(Array(requested.keys).sorted()) {
            var nextURL: URL?
            repeat {
                let envelope: ZerionCollectionEnvelope<ZerionFungibleResource> = if let nextURL {
                    try await client.get(next: nextURL)
                } else {
                    try await client.get(
                        path: "fungibles/",
                        queryItems: [
                            URLQueryItem(name: "filter[fungible_implementations]", value: chunk.joined(separator: ",")),
                            URLQueryItem(name: "currency", value: "usd"),
                            URLQueryItem(name: "page[size]", value: "100")
                        ])
                }

                for resource in envelope.data {
                    for implementation in resource.attributes.implementations {
                        let key = implementation.address.map {
                            "\(implementation.chainID):\($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                        } ?? implementation.chainID
                        guard let identity = requested[key], let marketData = resource.attributes.marketData else {
                            continue
                        }
                        if let price = marketData.price, price > 0 {
                            prices[identity.historicalPriceID] = price
                        }
                        if let percent = marketData.changes?.percent1D {
                            changes[identity.historicalPriceID] = percent / 100
                        }
                    }
                }
                nextURL = envelope.links?.next
            } while nextURL != nil
        }

        return PriceUpdate(prices: prices, changes24h: changes)
    }

    func fetchHistoricalPrices(
        identity: OnchainTokenIdentity,
        days: Int) async throws -> [HistoricalPriceDTO] {
        let implementation = try ZerionChainMapping.implementation(for: identity)
        let envelope: ZerionSingleEnvelope<ZerionChartResource>
        do {
            envelope = try await client.get(
                path: "fungibles/by-implementation/charts/\(Self.chartPeriod(for: days))",
                queryItems: [
                    URLQueryItem(name: "implementation", value: implementation),
                    URLQueryItem(name: "currency", value: "usd")
                ])
        } catch ZerionError.notFound {
            return []
        }

        var latestByDay: [Date: HistoricalPriceDTO] = [:]
        let cutoff = Date.now.addingTimeInterval(-TimeInterval(max(days, 1)) * 86400)
        for point in envelope.data.attributes.points where point.timestamp.isFinite && point.price > 0 {
            let date = Date(timeIntervalSince1970: point.timestamp)
            guard date >= cutoff else { continue }
            let dto = HistoricalPriceDTO(
                coinGeckoId: identity.historicalPriceID,
                timestamp: date,
                usdPrice: point.price,
                source: .zerion)
            if let existing = latestByDay[dto.day], existing.timestamp >= dto.timestamp {
                continue
            }
            latestByDay[dto.day] = dto
        }
        return latestByDay.values.sorted { $0.timestamp < $1.timestamp }
    }
}

private extension ZerionProvider {
    func implementationChunks(_ implementations: [String]) -> [[String]] {
        let maximumEncodedLength = 1800
        var chunks: [[String]] = []
        var current: [String] = []
        var currentLength = 0

        for implementation in implementations {
            let addedLength = implementation.utf8.count + (current.isEmpty ? 0 : 1)
            if current.count == 25 || (!current.isEmpty && currentLength + addedLength > maximumEncodedLength) {
                chunks.append(current)
                current = []
                currentLength = 0
            }
            current.append(implementation)
            currentLength += addedLength
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    static func chartPeriod(for days: Int) -> String {
        switch max(days, 1) {
        case 1: "day"
        case 2 ... 7: "week"
        case 8 ... 31: "month"
        default: "year"
        }
    }
}

import Foundation
import PortuCore
import SwiftData

struct PortfolioAnalyticsHistoryWriteResult: Equatable {
    let inserted: Int
    let updated: Int
    let pruned: Int
}

enum PortfolioAnalyticsCacheWriter {
    static let retainedDayCount = 400

    static func retentionCutoff(asOf date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = HistoricalPriceCalendar.utcStartOfDay(for: date)
        return calendar.date(byAdding: .day, value: -(retainedDayCount - 1), to: day)!
    }

    @MainActor
    static func upsertHistory(
        _ points: [ProviderPortfolioValueDTO],
        scope: PortfolioAnalyticsScope,
        in context: ModelContext,
        fetchedAt: Date = .now,
        coverageStartDate: Date? = nil) throws -> PortfolioAnalyticsHistoryWriteResult {
        let accountID = scope.accountID
        let descriptor = FetchDescriptor<ProviderPortfolioValuePoint>(
            predicate: #Predicate { $0.accountID == accountID })
        let accountRows = try context.fetch(descriptor)
        let scopedRows = accountRows.filter {
            $0.scopeFingerprint == scope.fingerprint
                && $0.provider == .zerion
        }
        var existingByDay: [HistoryDayIdentity: ProviderPortfolioValuePoint] = [:]
        var duplicateRows: [ProviderPortfolioValuePoint] = []
        for row in scopedRows.sorted(by: { $0.cacheKey < $1.cacheKey }) {
            let identity = HistoryDayIdentity(provider: row.provider, day: row.day)
            if existingByDay[identity] == nil {
                existingByDay[identity] = row
            } else {
                duplicateRows.append(row)
            }
        }
        let latestIncoming = latestHistoryPointsByDay(points)
        let requestedCoverageStartDate = HistoricalPriceCalendar.utcStartOfDay(
            for: coverageStartDate ?? points.map(\.timestamp).min() ?? fetchedAt)

        do {
            try upsertHistoryRefresh(
                scope: scope,
                coverageStartDate: requestedCoverageStartDate,
                fetchedAt: fetchedAt,
                in: context)
            duplicateRows.forEach(context.delete)
            let reconciledCount = reconcileHistoryRows(
                &existingByDay,
                retaining: Set(latestIncoming.keys),
                from: requestedCoverageStartDate,
                through: fetchedAt,
                in: context)
            let writeCounts = upsertHistoryPoints(
                latestIncoming.values,
                scope: scope,
                existingByDay: &existingByDay,
                timing: (requestedCoverageStartDate, fetchedAt),
                in: context)

            let cutoff = retentionCutoff(asOf: fetchedAt)
            var pruned = duplicateRows.count + reconciledCount
            for row in existingByDay.values where row.day < cutoff {
                context.delete(row)
                pruned += 1
            }
            try context.save()
            return PortfolioAnalyticsHistoryWriteResult(
                inserted: writeCounts.inserted,
                updated: writeCounts.updated,
                pruned: pruned)
        } catch {
            context.rollback()
            throw error
        }
    }

    private struct HistoryDayIdentity: Hashable {
        let provider: PortfolioAnalyticsProvider
        let day: Date
    }

    private static func latestHistoryPointsByDay(
        _ points: [ProviderPortfolioValueDTO]) -> [Date: ProviderPortfolioValueDTO] {
        Dictionary(
            points.sorted { $0.timestamp < $1.timestamp }.map { ($0.day, $0) },
            uniquingKeysWith: { _, latest in latest })
    }

    @MainActor
    private static func upsertHistoryPoints(
        _ points: Dictionary<Date, ProviderPortfolioValueDTO>.Values,
        scope: PortfolioAnalyticsScope,
        existingByDay: inout [HistoryDayIdentity: ProviderPortfolioValuePoint],
        timing: (coverageStartDate: Date, fetchedAt: Date),
        in context: ModelContext) -> (inserted: Int, updated: Int) {
        var inserted = 0
        var updated = 0
        for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
            let identity = HistoryDayIdentity(provider: point.provider, day: point.day)
            let key = ProviderPortfolioValuePoint.cacheKey(
                accountID: scope.accountID,
                scopeFingerprint: scope.fingerprint,
                provider: point.provider,
                coverage: point.coverage,
                day: point.day)
            if let row = existingByDay[identity] {
                row.cacheKey = key
                row.coverage = point.coverage
                row.timestamp = point.timestamp
                row.day = point.day
                row.usdValue = point.usdValue
                row.fetchedAt = timing.fetchedAt
                row.coverageStartDate = min(row.coverageStartDate, timing.coverageStartDate)
                updated += 1
            } else {
                let row = ProviderPortfolioValuePoint(
                    accountID: scope.accountID,
                    scopeFingerprint: scope.fingerprint,
                    provider: point.provider,
                    coverage: point.coverage,
                    timestamp: point.timestamp,
                    usdValue: point.usdValue,
                    fetchedAt: timing.fetchedAt,
                    coverageStartDate: timing.coverageStartDate)
                context.insert(row)
                existingByDay[identity] = row
                inserted += 1
            }
        }
        return (inserted, updated)
    }

    @MainActor
    private static func reconcileHistoryRows(
        _ existingByDay: inout [HistoryDayIdentity: ProviderPortfolioValuePoint],
        retaining incomingDays: Set<Date>,
        from coverageStartDate: Date,
        through fetchedAt: Date,
        in context: ModelContext) -> Int {
        let coverageEndDate = HistoricalPriceCalendar.utcStartOfDay(for: fetchedAt)
        let staleIdentities = existingByDay.keys.filter { identity in
            identity.day >= coverageStartDate
                && identity.day <= coverageEndDate
                && incomingDays.contains(identity.day) == false
        }
        for identity in staleIdentities {
            if let row = existingByDay.removeValue(forKey: identity) {
                context.delete(row)
            }
        }
        return staleIdentities.count
    }

    @MainActor
    private static func upsertHistoryRefresh(
        scope: PortfolioAnalyticsScope,
        coverageStartDate: Date,
        fetchedAt: Date,
        in context: ModelContext) throws {
        let refreshKey = ProviderPortfolioHistoryRefresh.cacheKey(
            accountID: scope.accountID,
            scopeFingerprint: scope.fingerprint,
            provider: .zerion,
            coverageStartDate: coverageStartDate)
        let descriptor = FetchDescriptor<ProviderPortfolioHistoryRefresh>(
            predicate: #Predicate { $0.cacheKey == refreshKey })
        if let refresh = try context.fetch(descriptor).first {
            refresh.fetchedAt = fetchedAt
        } else {
            context.insert(ProviderPortfolioHistoryRefresh(
                accountID: scope.accountID,
                scopeFingerprint: scope.fingerprint,
                provider: .zerion,
                coverageStartDate: coverageStartDate,
                fetchedAt: fetchedAt))
        }
    }

    @MainActor
    static func upsertPnL(
        _ value: ProviderPnLDTO,
        scope: PortfolioAnalyticsScope,
        in context: ModelContext) throws {
        let cacheKey = ProviderPnLSnapshot.cacheKey(
            accountID: scope.accountID,
            scopeFingerprint: scope.fingerprint,
            provider: .zerion,
            range: value.range,
            currency: value.currency)
        let descriptor = FetchDescriptor<ProviderPnLSnapshot>(
            predicate: #Predicate { $0.cacheKey == cacheKey })

        do {
            let breakdowns = value.assets.map(makeBreakdown)
            if let snapshot = try context.fetch(descriptor).first {
                for child in snapshot.assetBreakdowns {
                    context.delete(child)
                }
                apply(value, to: snapshot)
                snapshot.assetBreakdowns = breakdowns
            } else {
                context.insert(makeSnapshot(value, scope: scope, breakdowns: breakdowns))
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    static func invalidateObsoleteScopes(
        accountID: UUID,
        keeping scopeFingerprint: String,
        in context: ModelContext) throws -> Int {
        let historyDescriptor = FetchDescriptor<ProviderPortfolioValuePoint>(
            predicate: #Predicate { $0.accountID == accountID })
        let pnlDescriptor = FetchDescriptor<ProviderPnLSnapshot>(
            predicate: #Predicate { $0.accountID == accountID })
        let refreshDescriptor = FetchDescriptor<ProviderPortfolioHistoryRefresh>(
            predicate: #Predicate { $0.accountID == accountID })

        do {
            let history = try context.fetch(historyDescriptor)
                .filter { $0.scopeFingerprint != scopeFingerprint }
            let pnl = try context.fetch(pnlDescriptor)
                .filter { $0.scopeFingerprint != scopeFingerprint }
            let refreshes = try context.fetch(refreshDescriptor)
                .filter { $0.scopeFingerprint != scopeFingerprint }
            history.forEach(context.delete)
            pnl.forEach(context.delete)
            refreshes.forEach(context.delete)
            try context.save()
            return history.count + pnl.count + refreshes.count
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    static func clear(
        accountID: UUID,
        in context: ModelContext) throws -> Int {
        do {
            let removed = try deleteRows(accountID: accountID, in: context)
            try context.save()
            return removed
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    static func deleteRows(
        accountID: UUID,
        in context: ModelContext) throws -> Int {
        let history = try context.fetch(FetchDescriptor<ProviderPortfolioValuePoint>(
            predicate: #Predicate { $0.accountID == accountID }))
        let pnl = try context.fetch(FetchDescriptor<ProviderPnLSnapshot>(
            predicate: #Predicate { $0.accountID == accountID }))
        let refreshes = try context.fetch(FetchDescriptor<ProviderPortfolioHistoryRefresh>(
            predicate: #Predicate { $0.accountID == accountID }))
        history.forEach { context.delete($0) }
        pnl.forEach { context.delete($0) }
        refreshes.forEach { context.delete($0) }
        return history.count + pnl.count + refreshes.count
    }

    private static func makeSnapshot(
        _ value: ProviderPnLDTO,
        scope: PortfolioAnalyticsScope,
        breakdowns: [ProviderPnLAssetBreakdown]) -> ProviderPnLSnapshot {
        ProviderPnLSnapshot(
            accountID: scope.accountID,
            scopeFingerprint: scope.fingerprint,
            provider: .zerion,
            range: value.range,
            currency: value.currency,
            totalGain: value.totalGain,
            realizedGain: value.realizedGain,
            unrealizedGain: value.unrealizedGain,
            relativeTotalGain: value.relativeTotalGain,
            relativeRealizedGain: value.relativeRealizedGain,
            relativeUnrealizedGain: value.relativeUnrealizedGain,
            totalFee: value.totalFee,
            totalInvested: value.totalInvested,
            realizedCostBasis: value.realizedCostBasis,
            netInvested: value.netInvested,
            receivedExternal: value.receivedExternal,
            sentExternal: value.sentExternal,
            sentForNFTs: value.sentForNFTs,
            receivedForNFTs: value.receivedForNFTs,
            excludedIdentifiers: value.excludedIdentifiers,
            fetchedAt: value.fetchedAt,
            assetBreakdowns: breakdowns)
    }

    private static func apply(_ value: ProviderPnLDTO, to snapshot: ProviderPnLSnapshot) {
        snapshot.totalGain = value.totalGain
        snapshot.realizedGain = value.realizedGain
        snapshot.unrealizedGain = value.unrealizedGain
        snapshot.relativeTotalGain = value.relativeTotalGain
        snapshot.relativeRealizedGain = value.relativeRealizedGain
        snapshot.relativeUnrealizedGain = value.relativeUnrealizedGain
        snapshot.totalFee = value.totalFee
        snapshot.totalInvested = value.totalInvested
        snapshot.realizedCostBasis = value.realizedCostBasis
        snapshot.netInvested = value.netInvested
        snapshot.receivedExternal = value.receivedExternal
        snapshot.sentExternal = value.sentExternal
        snapshot.sentForNFTs = value.sentForNFTs
        snapshot.receivedForNFTs = value.receivedForNFTs
        snapshot.excludedIdentifiers = value.excludedIdentifiers.sorted()
        snapshot.fetchedAt = value.fetchedAt
    }

    private static func makeBreakdown(_ value: ProviderPnLAssetDTO) -> ProviderPnLAssetBreakdown {
        ProviderPnLAssetBreakdown(
            implementationID: value.implementationID,
            identity: value.identity,
            averageBuyPrice: value.averageBuyPrice,
            averageSellPrice: value.averageSellPrice,
            totalGain: value.totalGain,
            realizedGain: value.realizedGain,
            unrealizedGain: value.unrealizedGain,
            relativeTotalGain: value.relativeTotalGain,
            relativeRealizedGain: value.relativeRealizedGain,
            relativeUnrealizedGain: value.relativeUnrealizedGain,
            totalFee: value.totalFee,
            totalInvested: value.totalInvested,
            realizedCostBasis: value.realizedCostBasis,
            netInvested: value.netInvested,
            receivedExternal: value.receivedExternal,
            sentExternal: value.sentExternal,
            sentForNFTs: value.sentForNFTs,
            receivedForNFTs: value.receivedForNFTs)
    }
}

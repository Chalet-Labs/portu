import Foundation
import PortuCore
import SwiftData

/// Everything one load fetched, gathered once so the three shaping paths share it instead of
/// re-querying. Deliberately actor-local and not `Sendable`: `priceRows` holds live rows that
/// must not leave the fetcher.
private struct PerformanceLoadInputs {
    let request: PerformanceDataRequest
    let startDay: Date
    let conversion: CurrencyConversionContext
    let resolver: PortfolioCategoryResolver
    let overrides: [TokenPricingOverrideSnapshot]
    let mappings: [TokenIdentityMappingSnapshot]
    let visibleAssetIDs: Set<UUID>
    let snapshotRows: [PerformanceSnapshotRow]
    let assets: [PerformanceAssetRow]
    let priceRows: [HistoricalPricePoint]
}

/// Materialises and shapes every Performance screen input on a background `ModelContext`.
///
/// The screen used to run this work inside view bodies via `@Query`, which forced the main
/// thread to fault the whole `AssetSnapshot` table (~12k rows/day) on each render. Every
/// query here is date-predicated — and account-predicated when an account is selected — at
/// SQL level; the one deliberate exception is the limit-1 earliest-row probe.
///
/// Rows are projected into value types before leaving their fetch, so nothing persistent
/// escapes the actor and no relationship is faulted off it.
@ModelActor
actor PerformanceDataFetcher {
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60

    func load(_ request: PerformanceDataRequest) throws -> PerformanceDataSnapshot {
        try Task.checkCancellation()
        let inputs = try loadInputs(request)
        try Task.checkCancellation()
        let categoryChart = categoryChartData(inputs)
        try Task.checkCancellation()
        let valueChart = try valueChartData(inputs)
        try Task.checkCancellation()
        let bottomPanel = bottomPanelData(inputs)
        try Task.checkCancellation()
        return PerformanceDataSnapshot(
            categories: inputs.resolver.categories,
            categoryChart: categoryChart,
            valueChart: valueChart,
            bottomPanel: bottomPanel)
    }

    #if DEBUG
        /// Regression probe for the initialization-queue invariant in
        /// `PerformanceDataClient.live`.
        func isExecutingOnMainThread() -> Bool {
            Thread.isMainThread
        }
    #endif

    // MARK: - Fetching

    private func loadInputs(_ request: PerformanceDataRequest) throws -> PerformanceLoadInputs {
        let startDay = HistoricalPriceCalendar.utcStartOfDay(for: request.startDate)
        let resolver = try categoryResolver()
        let overrides = try overrideRows()
        let mappings = try mappingRows()
        let conversion = try conversionContext(request, startDay: startDay)
        let visibleAssetIDs = try dashboardVisibleAssetIDs(
            request,
            resolver: resolver,
            overrides: overrides,
            mappings: mappings)
        try Task.checkCancellation()

        // The bottom panel needs snapshot rows only when something is dashboard-visible;
        // the category chart needs them whenever it is the active mode.
        let needsSnapshots = !visibleAssetIDs.isEmpty || request.chartMode == .assets
        let snapshotRows = needsSnapshots
            ? try assetSnapshotRows(accountId: request.accountId, from: startDay)
            : []
        try Task.checkCancellation()
        // The asset table and historical prices only feed backfill-derived output.
        let needsPrices = request.historicalBackfillEnabled
            && (request.chartMode == .value || !visibleAssetIDs.isEmpty)
        let assets = needsPrices ? try assetRows() : []
        let priceRows = needsPrices ? try historicalPriceRows(from: startDay) : []

        return PerformanceLoadInputs(
            request: request,
            startDay: startDay,
            conversion: conversion,
            resolver: resolver,
            overrides: overrides,
            mappings: mappings,
            visibleAssetIDs: visibleAssetIDs,
            snapshotRows: snapshotRows,
            assets: assets,
            priceRows: priceRows)
    }

    /// Mirrors `PortfolioCategoryResolver.live`: an empty category table falls back to
    /// `.defaults`, which keeps the default category buttons rendering on a cold store.
    private func categoryResolver() throws -> PortfolioCategoryResolver {
        let categories = try modelContext.fetch(
            FetchDescriptor<PortfolioCategory>(
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]))
        guard !categories.isEmpty else { return .defaults }

        let rules = try modelContext.fetch(
            FetchDescriptor<CategorySymbolRule>(sortBy: [SortDescriptor(\.normalizedSymbol)]))
        return PortfolioCategoryResolver(
            categories: categories.map(PortfolioCategorySnapshot.init),
            rules: rules.compactMap(CategorySymbolRuleSnapshot.init))
    }

    private func overrideRows() throws -> [TokenPricingOverrideSnapshot] {
        try modelContext.fetch(FetchDescriptor<TokenPricingOverride>()).map {
            TokenPricingOverrideSnapshot(
                id: $0.id,
                assetId: $0.assetId,
                manualPriceUSD: $0.manualPriceUSD,
                coinGeckoIdOverride: $0.coinGeckoIdOverride,
                isIgnored: $0.isIgnored,
                alwaysShow: $0.alwaysShow,
                notes: $0.notes)
        }
    }

    private func mappingRows() throws -> [TokenIdentityMappingSnapshot] {
        try modelContext.fetch(FetchDescriptor<TokenIdentityMapping>()).map {
            TokenIdentityMappingSnapshot(
                id: $0.id,
                identity: $0.onchainIdentity,
                coinGeckoId: $0.coinGeckoId,
                zapperId: $0.zapperId)
        }
    }

    private func assetRows() throws -> [PerformanceAssetRow] {
        try modelContext.fetch(FetchDescriptor<Asset>()).map {
            PerformanceAssetRow(
                id: $0.id,
                name: $0.name,
                symbol: $0.symbol,
                coinGeckoId: $0.coinGeckoId,
                identity: OnchainTokenIdentity(chain: $0.upsertChain, contractAddress: $0.upsertContract))
        }
    }

    private func conversionContext(
        _ request: PerformanceDataRequest,
        startDay: Date) throws -> CurrencyConversionContext {
        let rates = try modelContext.fetch(
            FetchDescriptor<CurrencyConversionRatePoint>(
                predicate: #Predicate<CurrencyConversionRatePoint> { $0.day >= startDay },
                sortBy: [SortDescriptor(\.day)]))
        return CurrencyConversionContext(
            displayCurrency: request.displayCurrency,
            currentUSDToDisplayRate: request.currentUSDToDisplayRate,
            historicalRatePoints: rates)
    }

    private func historicalPriceRows(from startDay: Date) throws -> [HistoricalPricePoint] {
        try modelContext.fetch(
            FetchDescriptor<HistoricalPricePoint>(
                predicate: #Predicate<HistoricalPricePoint> { $0.day >= startDay },
                sortBy: [SortDescriptor(\.day)]))
    }

    /// `AssetSnapshot` rows for the selected scope. `upper` defaults to `.distantFuture` so the
    /// windowed (estimate) and open-ended (chart/panel) fetches share one predicate shape.
    private func assetSnapshotRows(
        accountId: UUID?,
        from lower: Date,
        before upper: Date = .distantFuture) throws -> [PerformanceSnapshotRow] {
        let sortBy = [SortDescriptor(\AssetSnapshot.timestamp)]
        guard let accountId else {
            return try modelContext.fetch(
                FetchDescriptor<AssetSnapshot>(
                    predicate: #Predicate<AssetSnapshot> { $0.timestamp >= lower && $0.timestamp < upper },
                    sortBy: sortBy))
                .map(\.performanceRow)
        }
        return try modelContext.fetch(
            FetchDescriptor<AssetSnapshot>(
                predicate: #Predicate<AssetSnapshot> {
                    $0.accountId == accountId && $0.timestamp >= lower && $0.timestamp < upper
                },
                sortBy: sortBy))
            .map(\.performanceRow)
    }

    private func earliestAssetSnapshotDate(accountId: UUID?) throws -> Date? {
        var descriptor = FetchDescriptor<AssetSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        if let accountId {
            descriptor.predicate = #Predicate<AssetSnapshot> { $0.accountId == accountId }
        }
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.timestamp
    }

    /// Asset ids that survive dashboard eligibility — the visibility scope shared by the
    /// bottom panel's category changes and price changes.
    private func dashboardVisibleAssetIDs(
        _ request: PerformanceDataRequest,
        resolver: PortfolioCategoryResolver,
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot]) throws -> Set<UUID> {
        let tokens = try modelContext.fetch(FetchDescriptor<PositionToken>())
        // Account scoping traverses PositionToken -> Position -> Account, and `#Predicate`
        // through chained optional relationships is not supported, so it stays in memory.
        let scoped = request.accountId.map { id in
            tokens.filter { $0.position?.account?.id == id }
        } ?? tokens
        let entries = TokenSettingsFeature.applyIdentityMappings(
            to: TokenEntry.fromActiveTokens(scoped, categoryResolver: resolver),
            mappings: mappings,
            overrides: overrides)
        let prices = OverviewHistoricalPriceChangeFeature.mergedPrices(
            live: request.liveDisplayPrices,
            historical: request.historicalDisplayPrices)
        let eligible = TokenSettingsFeature.dashboardEligibleTokens(
            tokens: entries,
            prices: prices,
            overrides: overrides,
            settings: request.dashboardSettings,
            usdToDisplayRate: request.currentUSDToDisplayRate)
        return Set(eligible.map(\.assetId))
    }

    // MARK: - Category chart

    private func categoryChartData(
        _ inputs: PerformanceLoadInputs) -> PerformanceCategoryChartCache {
        guard inputs.request.chartMode == .assets else { return .empty }
        return PerformanceCategoryChartCache(
            entries: PerformanceDataShaping.categoryEntries(
                rows: inputs.snapshotRows,
                from: inputs.request.startDate,
                resolver: inputs.resolver),
            conversionContext: inputs.conversion)
    }

    // MARK: - Bottom panel

    private func bottomPanelData(_ inputs: PerformanceLoadInputs) -> PerformanceBottomPanelData {
        guard !inputs.visibleAssetIDs.isEmpty else { return .empty }

        let changeEntries = PerformanceDataShaping.categoryEntries(
            rows: inputs.snapshotRows,
            from: inputs.request.startDate,
            visibleAssetIDs: inputs.visibleAssetIDs,
            resolver: inputs.resolver)
        return PerformanceBottomPanelData(
            categoryChanges: PerformanceFeature.computeCategoryChanges(
                entries: changeEntries,
                visibleAssetIDs: inputs.visibleAssetIDs,
                conversionContext: inputs.conversion),
            priceChanges: priceChanges(inputs))
    }

    private func priceChanges(_ inputs: PerformanceLoadInputs) -> [AssetPricePeriodChange] {
        guard inputs.request.historicalBackfillEnabled else { return [] }

        let holdings = PerformanceDataShaping
            .estimateEntries(
                rows: inputs.snapshotRows,
                overrides: inputs.overrides,
                assets: inputs.assets)
            .filter { inputs.visibleAssetIDs.contains($0.assetId) }
        guard !holdings.isEmpty else { return [] }

        let heldRows = PerformanceFeature.historicalPriceEntriesForHeldAssets(
            rows: OverviewHistoricalPriceChangeFeature.mergedHistoricalPriceEntries(
                from: inputs.priceRows,
                displayCurrency: inputs.request.displayCurrency,
                context: inputs.conversion),
            holdings: holdings,
            startDate: inputs.request.startDate,
            accountId: inputs.request.accountId,
            isHistoricalBackfillEnabled: true)
        let changes = PerformanceFeature.applyAssetDisplayNames(
            changes: PerformanceFeature.computeHistoricalPriceChanges(rows: heldRows),
            namesByHistoricalPriceID: PerformanceDataShaping.assetNames(
                assets: inputs.assets,
                overrides: inputs.overrides,
                mappings: inputs.mappings))
        return PerformanceDataShaping.orderedPriceChanges(changes)
    }

    // MARK: - Value chart

    private func valueChartData(_ inputs: PerformanceLoadInputs) throws -> PerformanceValueChartData {
        guard inputs.request.chartMode == .value else { return .empty }

        let request = inputs.request
        let local = try localObservations(request)
        let provider = try providerValuePoints(request)
        let merged = ProviderPortfolioHistory.merge(
            provider: provider,
            local: local,
            selectedAccountID: request.accountId,
            startDate: request.startDate)
        let retained = ProviderPortfolioHistory.retainedProviderPoints(
            provider,
            local: local,
            selectedAccountID: request.accountId,
            startDate: request.startDate)
        let converted = ProviderPortfolioHistory.convertProviderHistory(
            retained,
            mergeContext: ProviderHistoryMergeContext(
                local: local,
                selectedAccountID: request.accountId,
                startDate: request.startDate),
            currency: request.displayCurrency,
            historicalRatesByDay: inputs.conversion.historicalUSDToDisplayRatesByDay)
        let points = PerformanceDataShaping.valueChartPoints(
            merged: merged,
            converted: converted.points,
            conversion: inputs.conversion)
        let rendered = ProviderPortfolioHistory.renderedProviderPoints(
            for: retained,
            renderedTimestamps: Set(converted.points.map(\.timestamp)))

        return try PerformanceValueChartData(
            points: points,
            estimatedPoints: ProviderPortfolioHistory.estimatesOutsideProviderCoverage(
                estimatedPoints(inputs),
                providerDates: points.compactMap { $0.source == .zerion ? $0.date : nil }),
            providerDisclosure: ProviderPortfolioHistory.disclosure(for: rendered),
            historicalFXUnavailableBefore: converted.historicalFXUnavailableBefore,
            hasRetainedProviderPoints: !retained.isEmpty,
            hasConvertedProviderPoints: !converted.points.isEmpty)
    }

    /// Local snapshots for the selected scope, windowed to the chart range.
    ///
    /// `ProviderPortfolioHistory` derives the local-authority day from the *globally* earliest
    /// fresh row, not from the visible window, so a separate limit-1 probe re-introduces that
    /// row when it predates the window. Without it the authority day would move forward and
    /// provider points that local data already supersedes would be retained. The probe row is
    /// always outside the range, so `merge`'s trailing `startDate` filter drops it again.
    private func localObservations(
        _ request: PerformanceDataRequest) throws -> [LocalPortfolioValueObservation] {
        let startDate = request.startDate
        guard let accountId = request.accountId else {
            return try modelContext.fetch(
                FetchDescriptor<PortfolioSnapshot>(
                    predicate: #Predicate<PortfolioSnapshot> { $0.timestamp >= startDate },
                    sortBy: [SortDescriptor(\.timestamp)]))
                .map {
                    LocalPortfolioValueObservation(
                        timestamp: $0.timestamp,
                        usdValue: $0.totalValue,
                        isFresh: !$0.isPartial)
                }
        }

        var observations = try modelContext.fetch(
            FetchDescriptor<AccountSnapshot>(
                predicate: #Predicate<AccountSnapshot> {
                    $0.accountId == accountId && $0.timestamp >= startDate
                },
                sortBy: [SortDescriptor(\.timestamp)]))
            .map {
                LocalPortfolioValueObservation(
                    timestamp: $0.timestamp,
                    usdValue: $0.totalValue,
                    isFresh: $0.isFresh)
            }

        var probe = FetchDescriptor<AccountSnapshot>(
            predicate: #Predicate<AccountSnapshot> { $0.accountId == accountId && $0.isFresh },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        probe.fetchLimit = 1
        if let earliest = try modelContext.fetch(probe).first, earliest.timestamp < startDate {
            observations.insert(
                LocalPortfolioValueObservation(
                    timestamp: earliest.timestamp,
                    usdValue: earliest.totalValue,
                    isFresh: true),
                at: 0)
        }
        return observations
    }

    /// Persisted provider history stays the value-chart source, so cold entry still renders
    /// and an unresolved analytics scope still gates provider data out entirely.
    private func providerValuePoints(
        _ request: PerformanceDataRequest) throws -> [ProviderPortfolioValueDTO] {
        guard
            let accountId = request.accountId,
            let fingerprint = request.analyticsScopeFingerprint
        else { return [] }

        let startDate = request.startDate
        return try modelContext.fetch(
            FetchDescriptor<ProviderPortfolioValuePoint>(
                predicate: #Predicate<ProviderPortfolioValuePoint> {
                    $0.accountID == accountId
                        && $0.scopeFingerprint == fingerprint
                        && $0.timestamp >= startDate
                },
                sortBy: [SortDescriptor(\.timestamp)]))
            .map {
                ProviderPortfolioValueDTO(
                    timestamp: $0.timestamp,
                    usdValue: $0.usdValue,
                    provider: $0.provider,
                    coverage: $0.coverage)
            }
    }

    private func estimatedPoints(
        _ inputs: PerformanceLoadInputs) throws -> [HistoricalPortfolioValuePoint] {
        let request = inputs.request
        guard
            request.historicalBackfillEnabled,
            let firstRealSnapshotDate = try earliestAssetSnapshotDate(accountId: request.accountId),
            // When the earliest row predates the range, the estimator's price window
            // [startDay, utcStartOfDay(firstReal)) is empty and the estimate is empty too.
            firstRealSnapshotDate >= request.startDate
        else { return [] }

        let firstDay = HistoricalPriceCalendar.utcStartOfDay(for: firstRealSnapshotDate)
        let dayRows = try assetSnapshotRows(
            accountId: request.accountId,
            from: firstDay,
            before: firstDay.addingTimeInterval(Self.secondsPerDay))
        let holdings = PerformanceFeature.earliestEstimateHoldings(
            snapshots: PerformanceDataShaping.estimateEntries(
                rows: dayRows,
                overrides: inputs.overrides,
                assets: inputs.assets),
            firstRealSnapshotDate: firstRealSnapshotDate,
            accountId: request.accountId)
        guard !holdings.isEmpty else { return [] }

        let prices = inputs.priceRows.compactMap { row -> HistoricalPriceEntry? in
            guard
                row.fiatCurrency == .usd,
                row.day >= inputs.startDay,
                row.day < firstRealSnapshotDate
            else {
                return nil
            }
            return HistoricalPriceEntry(coinGeckoId: row.coinGeckoId, day: row.day, usdPrice: row.usdPrice)
        }
        return HistoricalPortfolioEstimator.estimatedValues(
            holdings: holdings,
            prices: prices,
            startDate: request.startDate,
            firstRealSnapshotDate: firstRealSnapshotDate,
            accountId: request.accountId)
            .map { inputs.conversion.convertUSDPoint($0) }
    }
}

private extension AssetSnapshot {
    /// Value projection taken inside the fetching actor, before the row can be handed off.
    var performanceRow: PerformanceSnapshotRow {
        PerformanceSnapshotRow(
            accountId: accountId,
            assetId: assetId,
            timestamp: timestamp,
            symbol: symbol,
            category: category,
            amount: amount,
            usdValue: usdValue,
            borrowAmount: borrowAmount,
            borrowUsdValue: borrowUsdValue)
    }
}

import Charts
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct ValueChartMode: View {
    let accountId: UUID?
    let startDate: Date
    let analyticsScopeFingerprint: String?

    @Environment(AppState.self) private var appState

    @Query(sort: \PortfolioSnapshot.timestamp)
    private var portfolioSnapshots: [PortfolioSnapshot]

    @Query(sort: \AccountSnapshot.timestamp)
    private var accountSnapshots: [AccountSnapshot]

    @Query(sort: \AssetSnapshot.timestamp)
    private var assetSnapshots: [AssetSnapshot]

    @Query private var assets: [Asset]

    @Query private var tokenPricingOverrides: [TokenPricingOverride]

    @Query
    private var historicalPrices: [HistoricalPricePoint]

    @Query
    private var currencyRates: [CurrencyConversionRatePoint]

    @Query
    private var providerValuePoints: [ProviderPortfolioValuePoint]

    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    init(
        accountId: UUID?,
        startDate: Date,
        analyticsScopeFingerprint: String? = nil) {
        self.accountId = accountId
        self.startDate = startDate
        self.analyticsScopeFingerprint = analyticsScopeFingerprint
        let historicalStartDate = HistoricalPriceCalendar.utcStartOfDay(for: startDate)
        _historicalPrices = Query(
            filter: #Predicate<HistoricalPricePoint> { $0.day >= historicalStartDate },
            sort: \.day)
        _currencyRates = Query(
            filter: #Predicate<CurrencyConversionRatePoint> { $0.day >= historicalStartDate },
            sort: \.day)
    }

    private var localObservations: [LocalPortfolioValueObservation] {
        if let accountId {
            accountSnapshots
                .filter { $0.accountId == accountId && $0.timestamp >= startDate }
                .map {
                    LocalPortfolioValueObservation(
                        timestamp: $0.timestamp,
                        usdValue: $0.totalValue,
                        isFresh: $0.isFresh)
                }
        } else {
            portfolioSnapshots
                .filter { $0.timestamp >= startDate }
                .map {
                    LocalPortfolioValueObservation(
                        timestamp: $0.timestamp,
                        usdValue: $0.totalValue,
                        isFresh: !$0.isPartial)
                }
        }
    }

    private var providerDTOs: [ProviderPortfolioValueDTO] {
        guard let accountId, let analyticsScopeFingerprint else { return [] }
        return providerValuePoints.compactMap { point in
            guard
                point.accountID == accountId,
                point.scopeFingerprint == analyticsScopeFingerprint,
                point.timestamp >= startDate
            else { return nil }
            return ProviderPortfolioValueDTO(
                timestamp: point.timestamp,
                usdValue: point.usdValue,
                provider: point.provider,
                coverage: point.coverage)
        }
    }

    private var mergedDataPoints: [PortfolioHistoryPoint] {
        ProviderPortfolioHistory.merge(
            provider: providerDTOs,
            local: localObservations,
            selectedAccountID: accountId)
    }

    private var convertedDataPoints: [(Date, Decimal, Bool, PortfolioHistorySource)] {
        let context = currencyConversionContext
        let convertedProviderByTimestamp = Dictionary(
            uniqueKeysWithValues: convertedProviderHistory.points.map { ($0.timestamp, $0.value) })
        return mergedDataPoints.compactMap { point in
            switch point.source {
            case .local:
                (
                    point.timestamp,
                    context.convertUSDValue(point.usdValue, on: point.timestamp),
                    !point.isReliable,
                    point.source)
            case .zerion:
                convertedProviderByTimestamp[point.timestamp].map {
                    (point.timestamp, $0, false, point.source)
                }
            }
        }
    }

    private var convertedProviderHistory: ProviderHistoryConversionResult {
        ProviderPortfolioHistory.convertProviderHistory(
            providerDTOs,
            currency: appState.selectedCurrency,
            historicalRatesByDay: currencyConversionContext.historicalUSDToDisplayRatesByDay)
    }

    private var scopedAssetSnapshots: [AssetSnapshot] {
        assetSnapshots.filter { accountId == nil || $0.accountId == accountId }
    }

    private var estimatedPoints: [HistoricalPortfolioValuePoint] {
        guard
            historicalBackfillEnabled,
            let firstRealSnapshotDate = scopedAssetSnapshots.map(\.timestamp).min()
        else { return [] }

        let holdings = PerformanceFeature.earliestEstimateHoldings(
            snapshots: historicalEstimateSnapshotEntries,
            firstRealSnapshotDate: firstRealSnapshotDate,
            accountId: accountId)
        guard !holdings.isEmpty else { return [] }

        let startDay = HistoricalPriceCalendar.utcStartOfDay(for: startDate)
        return HistoricalPortfolioEstimator.estimatedValues(
            holdings: holdings,
            prices: historicalPrices.compactMap {
                guard $0.fiatCurrency == .usd, $0.day >= startDay, $0.day < firstRealSnapshotDate else { return nil }
                return HistoricalPriceEntry(
                    coinGeckoId: $0.coinGeckoId,
                    day: $0.day,
                    usdPrice: $0.usdPrice)
            },
            startDate: startDate,
            firstRealSnapshotDate: firstRealSnapshotDate,
            accountId: accountId)
    }

    private var convertedEstimatedPoints: [HistoricalPortfolioValuePoint] {
        let context = currencyConversionContext
        return estimatedPoints.map { context.convertUSDPoint($0) }
    }

    private var currencyConversionContext: CurrencyConversionContext {
        CurrencyConversionContext(
            displayCurrency: appState.selectedCurrency,
            currentUSDToDisplayRate: appState.currentUSDToDisplayRate,
            historicalRatePoints: currencyRates)
    }

    private var currencyCode: String {
        appState.selectedCurrency.displayCode
    }

    private var historicalEstimateSnapshotEntries: [HistoricalEstimateSnapshotEntry] {
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(
            tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init))
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        return scopedAssetSnapshots.map { snapshot in
            let asset = assetsById[snapshot.assetId]
            return HistoricalEstimateSnapshotEntry(
                accountId: snapshot.accountId,
                assetId: snapshot.assetId,
                timestamp: snapshot.timestamp,
                coinGeckoId: asset?.coinGeckoId,
                coinGeckoIdOverride: overridesByAssetId[snapshot.assetId]?.coinGeckoIdOverride,
                onchainIdentity: OnchainTokenIdentity(chain: asset?.upsertChain, contractAddress: asset?.upsertContract),
                amount: snapshot.amount,
                borrowAmount: snapshot.borrowAmount,
                netUSDValue: snapshot.usdValue - snapshot.borrowUsdValue)
        }
    }

    var body: some View {
        let dataPoints = convertedDataPoints
        let estimatedPoints = providerDTOs.isEmpty ? convertedEstimatedPoints : []
        if dataPoints.isEmpty, estimatedPoints.isEmpty {
            Group {
                if
                    appState.selectedCurrency != .usd,
                    providerDTOs.isEmpty == false,
                    convertedProviderHistory.points.isEmpty {
                    ContentUnavailableView(
                        "Historical FX unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("No matching daily FX rates are available for Zerion history."))
                } else {
                    ContentUnavailableView(
                        "No Performance Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Sync your accounts to track portfolio performance"))
                }
            }
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
            .frame(height: 320)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(estimatedPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value))
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }

                    ForEach(dataPoints, id: \.0) { date, value, isPartial, source in
                        if source == .local {
                            AreaMark(x: .value("Date", date), y: .value("Value", value))
                                .foregroundStyle(
                                    .linearGradient(
                                        colors: [PortuTheme.dashboardGold.opacity(0.35), .clear],
                                        startPoint: .top, endPoint: .bottom))
                        }
                        LineMark(x: .value("Date", date), y: .value("Value", value))
                            .foregroundStyle(
                                source == .zerion
                                    ? PortuTheme.dashboardSecondaryText
                                    : PortuTheme.dashboardGold)
                            .lineStyle(
                                source == .zerion || isPartial
                                    ? StrokeStyle(lineWidth: 2, dash: [5, 3])
                                    : StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: currencyCode).precision(.fractionLength(0)))
                }
                .frame(height: 300)

                if providerDTOs.isEmpty == false {
                    Label(
                        "Zerion history · historical complex DeFi coverage may be incomplete",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
                if let conversionStart = convertedProviderHistory.historicalFXUnavailableBefore {
                    Label(
                        "Historical FX unavailable before \(conversionStart.formatted(date: .abbreviated, time: .omitted))",
                        systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                } else if
                    appState.selectedCurrency != .usd,
                    providerDTOs.isEmpty == false,
                    convertedProviderHistory.points.isEmpty {
                    Label(
                        "Historical FX unavailable for Zerion history",
                        systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
            }
        }
    }
}

import Combine
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PerformanceView: View {
    let store: StoreOf<AppFeature>

    @Environment(\.modelContext) private var modelContext
    @Environment(\.historicalDisplayPrices) private var historicalDisplayPrices

    @Query private var accounts: [Account]
    @StateObject private var containerSaveObserver = PerformanceContainerSaveObserver()

    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true
    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    var body: some View {
        // Bound once per body pass: `analyticsAccountInput` walks account positions and
        // tokens, and previously ran once per derived property (context, fingerprint,
        // scope options, task ID). Everything below reuses these three values.
        let accountInput = analyticsAccountInput
        let analyticsContext = makeAnalyticsContext(account: accountInput, asOf: .now)
        let scopeFingerprint = analyticsHistoryScopeFingerprint(
            account: accountInput,
            context: analyticsContext)
        let dataTaskID = makeDataTaskID(analyticsScopeFingerprint: scopeFingerprint)

        return ScrollView {
            VStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
                DashboardPageHeader("Performance")

                controlStrip

                dataLoadStatus

                DashboardCard(horizontalPadding: 18, verticalPadding: 16) {
                    switch store.performance.chartMode {
                    case .value:
                        ValueChartMode(
                            data: store.performance.valueChartData,
                            historyStatus: store.performance.analytics.historyStatus,
                            currencyCode: currencyCode)
                    case .assets:
                        AssetsChartMode(
                            categories: store.performance.categories,
                            chartData: store.performance.assetChartPoints,
                            store: store)
                    case .valueChange:
                        ValueChangeChartMode(
                            accountId: store.performance.selectedAccountId,
                            startDate: store.performance.selectedRange.startDate,
                            store: store)
                    case .pnl:
                        WalletPnLChartMode(
                            store: store,
                            context: analyticsContext,
                            scopeOptions: analyticsScopeOptions(account: accountInput))
                    }
                }

                PerformanceBottomPanel(
                    data: store.performance.bottomPanelData,
                    currencyCode: currencyCode,
                    historicalBackfillEnabled: historicalBackfillEnabled)
                    .dashboardCard(horizontalPadding: 18, verticalPadding: 16)
            }
            .padding(DashboardStyle.pagePadding)
        }
        .dashboardPage()
        .task(id: dataTaskID) {
            store.send(.performance(.dataRequested(dataTaskID.request(asOf: .now))))
        }
        .task(id: analyticsTaskID(account: accountInput)) {
            if let context = makeAnalyticsContext(account: accountInput, asOf: .now) {
                store.send(.performance(.analytics(.load(context))))
            } else {
                store.send(.performance(.analytics(.selectionUnavailable)))
            }
        }
        // One model-boundary hook covers every writer: sync snapshots, retention prunes,
        // analytics/price/FX caches, category-rule and override edits from the separate
        // Settings scene, and manual position saves. The observer owns the debounced
        // subscription so body recomputation cannot reset an in-flight debounce.
        .onAppear {
            containerSaveObserver.observe(container: modelContext.container)
        }
        .onChange(of: ObjectIdentifier(modelContext.container)) { _, _ in
            containerSaveObserver.observe(container: modelContext.container)
        }
        .onReceive(containerSaveObserver.didSave) {
            store.send(.performance(.dataInvalidated))
        }
        .onDisappear {
            store.send(.performance(.screenExited))
            store.send(.performance(.analytics(.featureExited)))
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 10) {
            Picker("Account", selection: Binding(
                get: { store.performance.selectedAccountId },
                set: { store.send(.performance(.accountSelected($0))) })) {
                    Text("All Accounts").tag(nil as UUID?)
                    ForEach(accounts.filter(\.isActive), id: \.id) { account in
                        Text(account.name).tag(account.id as UUID?)
                    }
                }
                .frame(width: 220)

            if store.performance.chartMode != .pnl {
                Picker("Range", selection: Binding(
                    get: { store.performance.selectedRange },
                    set: { store.send(.performance(.timeRangeChanged($0))) })) {
                        ForEach(ChartTimeRange.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
            }

            Picker("Mode", selection: Binding(
                get: { store.performance.chartMode },
                set: { store.send(.performance(.chartModeChanged($0))) })) {
                    ForEach(availableModes, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: store.performance.analytics.isAvailable ? 300 : 220)

            Spacer(minLength: 0)
        }
        .dashboardControl()
        .dashboardCard(horizontalPadding: 10, verticalPadding: 10)
    }

    @ViewBuilder
    private var dataLoadStatus: some View {
        if store.performance.isDataLoading {
            ProgressView("Loading performance data\u{2026}")
                .controlSize(.small)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
        } else if let error = store.performance.dataLoadError {
            Label(
                "Performance data unavailable: \(error)",
                systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardWarning)
        }
    }

    private var availableModes: [PerformanceChartMode] {
        PerformanceChartMode.allCases.filter {
            $0 != .pnl || store.performance.analytics.isAvailable
        }
    }

    private var currencyCode: String {
        store.selectedCurrency.displayCode
    }

    private var selectedAccount: Account? {
        guard let id = store.performance.selectedAccountId else { return nil }
        return accounts.first { $0.id == id }
    }

    private var analyticsAccountInput: PortfolioAnalyticsAccountInput? {
        guard let account = selectedAccount else { return nil }
        let implementations = account.positions.flatMap(\.tokens).compactMap { token in
            OnchainTokenIdentity(
                chain: token.asset?.upsertChain,
                contractAddress: token.asset?.upsertContract)
        }
        return PortfolioAnalyticsAccountInput(
            id: account.id,
            dataSource: account.dataSource,
            isActive: account.isActive,
            addresses: account.addresses.map {
                PortfolioAnalyticsAddressInput(chain: $0.chain, address: $0.address)
            },
            implementations: implementations)
    }

    /// Identity for the off-main-actor load. Deliberately excludes the concrete window
    /// start: `ChartTimeRange.startDate` is relative to `.now`, so including it would
    /// make every body pass a fresh identity and relaunch the load forever. The range
    /// enum plus `dataRevision` capture every real reason to refetch.
    private struct PerformanceDataTaskID: Equatable {
        var accountId: UUID?
        var range: ChartTimeRange
        var chartMode: PerformanceChartMode
        var analyticsScopeFingerprint: String?
        var displayCurrency: FiatCurrency
        var currentUSDToDisplayRate: Decimal
        var liveDisplayPrices: [String: Decimal]
        var historicalDisplayPrices: [String: Decimal]
        var minimumDashboardValue: Decimal
        var hideUnpriced: Bool
        var hideDust: Bool
        var historicalBackfillEnabled: Bool
        var dataRevision: Int

        func request(asOf date: Date) -> PerformanceDataRequest {
            PerformanceDataRequest(
                accountId: accountId,
                startDate: range.startDate(at: date),
                chartMode: chartMode,
                analyticsScopeFingerprint: analyticsScopeFingerprint,
                displayCurrency: displayCurrency,
                currentUSDToDisplayRate: currentUSDToDisplayRate,
                liveDisplayPrices: liveDisplayPrices,
                historicalDisplayPrices: historicalDisplayPrices,
                minimumDashboardValue: minimumDashboardValue,
                hideUnpriced: hideUnpriced,
                hideDust: hideDust,
                historicalBackfillEnabled: historicalBackfillEnabled)
        }
    }

    private func makeDataTaskID(analyticsScopeFingerprint: String?) -> PerformanceDataTaskID {
        PerformanceDataTaskID(
            accountId: store.performance.selectedAccountId,
            range: store.performance.selectedRange,
            chartMode: store.performance.chartMode,
            analyticsScopeFingerprint: analyticsScopeFingerprint,
            displayCurrency: store.selectedCurrency,
            currentUSDToDisplayRate: store.currentUSDToDisplayRate,
            liveDisplayPrices: store.prices,
            historicalDisplayPrices: historicalDisplayPrices,
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust,
            historicalBackfillEnabled: historicalBackfillEnabled,
            dataRevision: store.performance.dataRevision)
    }

    private func analyticsScopeOptions(
        account: PortfolioAnalyticsAccountInput?) -> [PortfolioAnalyticsScopeOption] {
        account.map(PortfolioAnalyticsScopeFactory.scopeOptions) ?? []
    }

    private func analyticsHistoryScopeFingerprint(
        account: PortfolioAnalyticsAccountInput?,
        context: PortfolioAnalyticsRequestContext?) -> String? {
        guard
            store.performance.analytics.isAvailable,
            store.performance.selectedRange != .custom,
            let account,
            let context,
            PortfolioAnalyticsScopeFactory.scopeCoversEntireAccount(
                context.scope,
                account: account) else { return nil }
        return context.scope.fingerprint
    }

    private func analyticsTaskID(account: PortfolioAnalyticsAccountInput?) -> String {
        let availability = store.performance.analytics.isAvailable
        guard let context = makeAnalyticsContext(account: account, asOf: .distantPast) else {
            return [
                "none",
                store.performance.selectedRange.rawValue,
                store.selectedCurrency.rawValue,
                "available:\(availability)"
            ].joined(separator: "|")
        }
        return [
            context.historyRequestID,
            "active:\(context.isAccountActive)",
            "available:\(availability)"
        ].joined(separator: "|")
    }

    private func makeAnalyticsContext(
        account: PortfolioAnalyticsAccountInput?,
        asOf: Date) -> PortfolioAnalyticsRequestContext? {
        guard let account else { return nil }
        return PortfolioAnalyticsScopeFactory.requestContext(
            account: account,
            selectedScopeFingerprint: store.performance.analytics.selectedWalletScopeFingerprint,
            chartRange: store.performance.selectedRange,
            currency: store.selectedCurrency,
            asOf: asOf)
    }
}

final class PerformanceContainerSaveObserver: ObservableObject {
    let didSave = PassthroughSubject<Void, Never>()

    private var observedContainer: ModelContainer?
    private var subscription: AnyCancellable?

    func observe(container: ModelContainer) {
        guard observedContainer !== container else { return }
        observedContainer = container
        subscription = NotificationCenter.default.publisher(for: ModelContext.didSave)
            .compactMap { ($0.object as? ModelContext)?.container }
            .filter { $0 === container }
            .map { _ in () }
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [didSave] in didSave.send() }
    }
}

import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PerformanceView: View {
    let store: StoreOf<AppFeature>

    @Query private var accounts: [Account]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
                DashboardPageHeader("Performance")

                controlStrip

                DashboardCard(horizontalPadding: 18, verticalPadding: 16) {
                    switch store.performance.chartMode {
                    case .value:
                        ValueChartMode(
                            accountId: store.performance.selectedAccountId,
                            startDate: store.performance.selectedRange.startDate,
                            analyticsScopeFingerprint: analyticsHistoryScopeFingerprint,
                            historyStatus: store.performance.analytics.historyStatus)
                    case .assets:
                        AssetsChartMode(
                            accountId: store.performance.selectedAccountId,
                            startDate: store.performance.selectedRange.startDate,
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
                            scopeOptions: analyticsScopeOptions)
                    }
                }

                PerformanceBottomPanel(
                    accountId: store.performance.selectedAccountId,
                    startDate: store.performance.selectedRange.startDate)
                    .dashboardCard(horizontalPadding: 18, verticalPadding: 16)
            }
            .padding(DashboardStyle.pagePadding)
        }
        .dashboardPage()
        .task(id: analyticsTaskID) {
            if let context = makeAnalyticsContext(asOf: .now) {
                store.send(.performance(.analytics(.load(context))))
            } else {
                store.send(.performance(.analytics(.selectionUnavailable)))
            }
        }
        .onDisappear {
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

    private var availableModes: [PerformanceChartMode] {
        PerformanceChartMode.allCases.filter {
            $0 != .pnl || store.performance.analytics.isAvailable
        }
    }

    private var selectedAccount: Account? {
        guard let id = store.performance.selectedAccountId else { return nil }
        return accounts.first { $0.id == id }
    }

    private var analyticsContext: PortfolioAnalyticsRequestContext? {
        makeAnalyticsContext(asOf: .now)
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

    private var analyticsScopeOptions: [PortfolioAnalyticsScopeOption] {
        analyticsAccountInput.map(PortfolioAnalyticsScopeFactory.scopeOptions) ?? []
    }

    private var analyticsHistoryScopeFingerprint: String? {
        guard
            store.performance.analytics.isAvailable,
            store.performance.selectedRange != .custom,
            let input = analyticsAccountInput,
            let context = analyticsContext,
            PortfolioAnalyticsScopeFactory.scopeCoversEntireAccount(
                context.scope,
                account: input) else { return nil }
        return context.scope.fingerprint
    }

    private var analyticsTaskID: String {
        let availability = store.performance.analytics.isAvailable
        guard let context = makeAnalyticsContext(asOf: .distantPast) else {
            return [
                "none",
                store.performance.selectedRange.rawValue,
                store.selectedCurrency.rawValue,
                "available:\(availability)"
            ].joined(separator: "|")
        }
        return [
            context.requestID(pnlRange: store.performance.analytics.pnlRange),
            "active:\(context.isAccountActive)",
            "available:\(availability)"
        ].joined(separator: "|")
    }

    private func makeAnalyticsContext(asOf: Date) -> PortfolioAnalyticsRequestContext? {
        guard let input = analyticsAccountInput else { return nil }
        return PortfolioAnalyticsScopeFactory.requestContext(
            account: input,
            selectedScopeFingerprint: store.performance.analytics.selectedWalletScopeFingerprint,
            chartRange: store.performance.selectedRange,
            currency: store.selectedCurrency,
            asOf: asOf)
    }
}

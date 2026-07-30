import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

struct WalletPnLChartMode: View {
    let store: StoreOf<AppFeature>
    let context: PortfolioAnalyticsRequestContext?
    let scopeOptions: [PortfolioAnalyticsScopeOption]

    private var state: PortfolioAnalyticsFeature.State {
        store.performance.analytics
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if scopeOptions.count > 1 {
                    Picker("Wallet", selection: Binding(
                        get: { context?.scope.fingerprint ?? scopeOptions[0].id },
                        set: {
                            store.send(.performance(.analytics(.walletScopeSelected($0))))
                        })) {
                            ForEach(scopeOptions) { option in
                                Text(option.label).tag(option.id)
                            }
                        }
                        .frame(width: 180)
                }

                Picker("PnL range", selection: Binding(
                    get: { state.pnlRange },
                    set: { range in
                        guard let context else { return }
                        store.send(.performance(.analytics(.pnlRangeChanged(range, context))))
                    })) {
                        ForEach(ProviderPnLRange.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                Button("Refresh", systemImage: "arrow.clockwise") {
                    guard let context else { return }
                    store.send(.performance(.analytics(.refresh(context))))
                }
                .disabled(context?.isAccountActive != true)

                Button("Clear cache", systemImage: "trash") {
                    guard let context else { return }
                    store.send(.performance(.analytics(.clearCache(context))))
                }
                .disabled(context == nil)
            }

            if context?.isAccountActive == false {
                Label("Inactive account — cached analytics remain read-only", systemImage: "pause.circle")
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
            }

            content

            Text("Zerion FIFO estimate. Transfers, airdrops, excluded unpriced assets, and tax rules can change the result.")
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
        }
        .frame(minHeight: 320, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if context == nil {
            ContentUnavailableView(
                "Select a Zerion account",
                systemImage: "wallet.bifold",
                description: Text("PnL is available for one eligible wallet scope at a time."))
        } else if let pnl = state.pnl {
            VStack(alignment: .leading, spacing: 12) {
                if case let .failed(failure) = state.pnlStatus {
                    Label(failure.message, systemImage: failure.systemImage)
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                } else if state.pnlStatus == .refreshing {
                    ProgressView("Refreshing Zerion PnL…")
                        .controlSize(.small)
                }

                HStack(spacing: 28) {
                    metric("Total gain", value: pnl.totalGain, currency: pnl.currency, showsDirection: true)
                    metric("Realized", value: pnl.realizedGain, currency: pnl.currency, showsDirection: true)
                    metric("Unrealized", value: pnl.unrealizedGain, currency: pnl.currency, showsDirection: true)
                    metric("Fees", value: pnl.totalFee, currency: pnl.currency)
                    metric("Net invested", value: pnl.netInvested, currency: pnl.currency)
                }

                let flows = WalletPnLPresentation.flowRows(for: pnl)
                if flows.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("External and NFT flows")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 28) {
                            ForEach(flows) { flow in
                                metric(flow.title, value: flow.value, currency: pnl.currency)
                            }
                        }
                    }
                }

                if pnl.excludedIdentifiers.isEmpty == false {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            "\(pnl.excludedIdentifiers.count) unpriced assets excluded",
                            systemImage: "exclamationmark.triangle")
                        Text(pnl.excludedIdentifiers.prefix(5).joined(separator: ", "))
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }

                let assetRows = WalletPnLPresentation.assetRows(for: pnl)
                if assetRows.isEmpty == false {
                    assetBreakdown(assetRows, currency: pnl.currency)
                }

                Text(metadata(for: pnl))
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)

                Text("Unrealized gain uses current prices, including for historical ranges. Coverage may be incomplete.")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
            }
        } else {
            switch state.pnlStatus {
            case .loading, .refreshing:
                ProgressView("Loading Zerion PnL…")
            case let .failed(failure):
                ContentUnavailableView(
                    failure.title,
                    systemImage: failure.systemImage,
                    description: Text(failure.message))
            case .idle, .loaded:
                ContentUnavailableView(
                    "PnL unavailable",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Select an active Zerion account"))
            }
        }
    }

    private func metadata(for pnl: ProviderPnLDTO) -> String {
        let freshness = ProviderPnLFreshness.evaluate(fetchedAt: pnl.fetchedAt, now: .now)
        let prefix = freshness == .fresh ? "Zerion" : "Stale Zerion cache"
        return [
            prefix,
            "FIFO",
            pnl.range.displayName,
            pnl.currency.displayCode,
            "updated \(pnl.fetchedAt.formatted(.relative(presentation: .named)))"
        ].joined(separator: " · ")
    }

    private func metric(
        _ title: String,
        value: Decimal?,
        currency: FiatCurrency,
        showsDirection: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
            if let value, showsDirection {
                let direction = WalletPnLDirection(value: value)
                Label(
                    formatted(value, currency: currency),
                    systemImage: direction.systemImage)
                    .font(.headline)
                    .foregroundStyle(direction.color)
                    .accessibilityLabel(
                        "\(title), \(direction.accessibilityLabel), \(formatted(value, currency: currency))")
            } else {
                Text(value.map { formatted($0, currency: currency) } ?? "—")
                    .font(.headline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func assetBreakdown(
        _ rows: [WalletPnLAssetRow],
        currency: FiatCurrency) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Asset breakdown")
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        ForEach([
                            "Asset", "Avg buy", "Avg sell", "Total", "Realized",
                            "Unrealized", "Invested", "Fees", "Coverage"
                        ], id: \.self) {
                            Text($0).font(.caption.weight(.semibold))
                        }
                    }
                    Divider().gridCellColumns(9)
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.implementationID).textSelection(.enabled)
                            valueCell(row.averageBuyPrice, currency: currency)
                            valueCell(row.averageSellPrice, currency: currency)
                            valueCell(row.totalGain, currency: currency)
                            valueCell(row.realizedGain, currency: currency)
                            valueCell(row.unrealizedGain, currency: currency)
                            valueCell(row.totalInvested, currency: currency)
                            valueCell(row.totalFee, currency: currency)
                            Text(row.completenessLabel)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func valueCell(
        _ value: Decimal?,
        currency: FiatCurrency) -> some View {
        Text(value.map { formatted($0, currency: currency) } ?? "—")
    }

    private func formatted(_ value: Decimal, currency: FiatCurrency) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(
            .currency(code: currency.displayCode))
    }
}

private extension PortfolioAnalyticsFailure {
    var title: String {
        switch self {
        case .preparing:
            "Zerion is preparing PnL"
        case .planUnavailable:
            "Analytics plan required"
        case .invalidCredential:
            "Check Zerion API key"
        case .rateLimited:
            "Zerion quota reached"
        case .unsupportedAggregation:
            "Select a wallet"
        case .invalidRequest, .unavailableForScope, .generic:
            "PnL unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .preparing:
            "clock.arrow.circlepath"
        case .planUnavailable:
            "creditcard"
        case .invalidCredential:
            "key"
        case .rateLimited:
            "hourglass"
        case .unsupportedAggregation:
            "wallet.bifold"
        case .invalidRequest, .unavailableForScope, .generic:
            "exclamationmark.triangle"
        }
    }
}

private extension WalletPnLDirection {
    @MainActor
    var color: Color {
        switch self {
        case .gain: .green
        case .loss: .red
        case .unchanged: PortuTheme.dashboardSecondaryText
        }
    }
}

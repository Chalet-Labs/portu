import ComposableArchitecture
import PortuCore
import SwiftData
import SwiftUI

struct PerformanceView: View {
    let store: StoreOf<AppFeature>

    @Query private var accounts: [Account]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Account", selection: Binding(
                    get: { store.performance.selectedAccountId },
                    set: { store.send(.performance(.accountSelected($0))) })) {
                        Text("All Accounts").tag(nil as UUID?)
                        ForEach(accounts.filter(\.isActive), id: \.id) { account in
                            Text(account.name).tag(account.id as UUID?)
                        }
                    }
                    .frame(width: 200)

                Spacer()

                Picker("Range", selection: Binding(
                    get: { store.performance.selectedRange },
                    set: { store.send(.performance(.timeRangeChanged($0))) })) {
                        ForEach(ChartTimeRange.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)

                Spacer()

                Picker("Mode", selection: Binding(
                    get: { store.performance.chartMode },
                    set: { store.send(.performance(.chartModeChanged($0))) })) {
                        ForEach(PerformanceChartMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
            }
            .padding()

            switch store.performance.chartMode {
            case .value:
                ValueChartMode(
                    accountId: store.performance.selectedAccountId,
                    startDate: store.performance.selectedRange.startDate)
            case .assets:
                AssetsChartMode(
                    accountId: store.performance.selectedAccountId,
                    startDate: store.performance.selectedRange.startDate,
                    store: store)
            case .pnl:
                PnLChartMode(
                    accountId: store.performance.selectedAccountId,
                    startDate: store.performance.selectedRange.startDate,
                    store: store)
            }

            Divider()

            PerformanceBottomPanel(
                accountId: store.performance.selectedAccountId,
                startDate: store.performance.selectedRange.startDate)
        }
        .navigationTitle("Performance")
    }
}

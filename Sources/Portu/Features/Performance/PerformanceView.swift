import SwiftUI
import SwiftData
import PortuCore

struct PerformanceView: View {
    @Query private var accounts: [Account]

    @State private var selectedAccountId: UUID? = nil  // nil = all accounts
    @State private var selectedRange: TimeRange = .oneMonth
    @State private var chartMode: ChartMode = .value

    enum ChartMode: String, CaseIterable {
        case value = "Value"
        case assets = "Assets"
        case pnl = "PnL"
    }

    enum TimeRange: String, CaseIterable {
        case oneWeek = "1W", oneMonth = "1M", threeMonths = "3M"
        case oneYear = "1Y", ytd = "YTD", custom = "Custom"

        var startDate: Date {
            let cal = Calendar.current
            let now = Date.now
            return switch self {
            case .oneWeek: cal.date(byAdding: .weekOfYear, value: -1, to: now)!
            case .oneMonth: cal.date(byAdding: .month, value: -1, to: now)!
            case .threeMonths: cal.date(byAdding: .month, value: -3, to: now)!
            case .oneYear: cal.date(byAdding: .year, value: -1, to: now)!
            case .ytd: cal.date(from: cal.dateComponents([.year], from: now))!
            case .custom: cal.date(byAdding: .month, value: -1, to: now)! // Default; overridden by date picker
            }
        }
    }

    // When chartMode == .custom, show date pickers for custom start/end
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var customEndDate = Date.now

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            HStack {
                // Account filter
                Picker("Account", selection: $selectedAccountId) {
                    Text("All Accounts").tag(nil as UUID?)
                    ForEach(accounts.filter(\.isActive), id: \.id) { account in
                        Text(account.name).tag(account.id as UUID?)
                    }
                }
                .frame(width: 200)

                Spacer()

                // Time range
                Picker("Range", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                // Chart mode
                Picker("Mode", selection: $chartMode) {
                    ForEach(ChartMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding()

            // Chart
            switch chartMode {
            case .value:
                ValueChartMode(
                    accountId: selectedAccountId,
                    startDate: selectedRange.startDate
                )
            case .assets:
                AssetsChartMode(
                    accountId: selectedAccountId,
                    startDate: selectedRange.startDate
                )
            case .pnl:
                PnLChartMode(
                    accountId: selectedAccountId,
                    startDate: selectedRange.startDate
                )
            }

            Divider()

            // Bottom panels
            PerformanceBottomPanel(
                accountId: selectedAccountId,
                startDate: selectedRange.startDate
            )
        }
        .navigationTitle("Performance")
    }
}

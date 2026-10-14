import PortuUI
import SwiftUI

struct AssetHoldingsSummary: View {
    let holdings: AssetHoldings
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Holdings Summary")
                .font(DashboardStyle.sectionTitleFont)
                .foregroundStyle(PortuTheme.dashboardText)

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Accounts").font(.caption).foregroundStyle(PortuTheme.dashboardSecondaryText)
                    Text("\(holdings.accountCount)")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                }
                VStack(alignment: .leading) {
                    Text("Total Amount").font(.caption).foregroundStyle(PortuTheme.dashboardSecondaryText)
                    Text(AssetDetailFormat.amount(holdings.totalAmount))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                }
                VStack(alignment: .leading) {
                    Text("Total Value").font(.caption).foregroundStyle(PortuTheme.dashboardSecondaryText)
                    Text(AssetDetailFormat.currency(holdings.totalValue, code: currencyCode))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                }
            }

            if !holdings.chains.isEmpty {
                Text("On Networks").font(.subheadline.weight(.medium))
                    .foregroundStyle(PortuTheme.dashboardText)
                ForEach(holdings.chains) { chain in
                    HStack {
                        Text(chain.name)
                        Spacer()
                        Text(AssetDetailFormat.share(chain.share))
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        Text(AssetDetailFormat.currency(chain.value, code: currencyCode))
                            .font(DashboardStyle.monoTableFont)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

import SwiftUI
import PortuUI

struct AssetPositionsTable: View {
    private static let allContextsLabel = "All Contexts"
    private static let allNetworksLabel = "All Networks"

    let rows: [AssetDetailPositionRow]

    @State private var selectedContext = Self.allContextsLabel
    @State private var selectedNetwork = Self.allNetworksLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                SectionHeader(
                    "Positions",
                    subtitle: "Current positions containing this asset across all active accounts"
                )

                Spacer()

                filterControls
            }

            if filteredRows.isEmpty {
                ContentUnavailableView {
                    Label("No Positions", systemImage: "tablecells")
                } description: {
                    Text("Adjust the filters or sync more accounts to populate the position drill-down.")
                }
                .frame(minHeight: 280)
            } else {
                Table(filteredRows) {
                    TableColumn("Account") { row in
                        Text(row.accountName)
                    }
                    TableColumn("Platform") { row in
                        Text(row.platformName)
                    }
                    TableColumn("Context") { row in
                        Text(row.contextLabel)
                    }
                    TableColumn("Network") { row in
                        Text(row.networkName)
                    }
                    TableColumn("Amount") { row in
                        Text(row.amount.formatted())
                    }
                    TableColumn("USD Balance") { row in
                        CurrencyText(row.usdBalance)
                    }
                }
                .frame(minHeight: 280, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var filterControls: some View {
        HStack(spacing: 12) {
            Picker("Context", selection: $selectedContext) {
                ForEach(contextOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .frame(maxWidth: 180)

            Picker("Network", selection: $selectedNetwork) {
                ForEach(networkOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .frame(maxWidth: 200)
        }
    }

    private var contextOptions: [String] {
        [Self.allContextsLabel] + Array(Set(rows.map(\.contextLabel))).sorted()
    }

    private var networkOptions: [String] {
        [Self.allNetworksLabel] + Array(Set(rows.map(\.networkName))).sorted()
    }

    private var filteredRows: [AssetDetailPositionRow] {
        rows.filter { row in
            let matchesContext = selectedContext == Self.allContextsLabel || row.contextLabel == selectedContext
            let matchesNetwork = selectedNetwork == Self.allNetworksLabel || row.networkName == selectedNetwork
            return matchesContext && matchesNetwork
        }
    }
}

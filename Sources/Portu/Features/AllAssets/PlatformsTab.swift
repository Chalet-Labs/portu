import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PlatformsTab: View {
    @Environment(AppState.self) private var appState
    var sources = ValuationSources()
    @Query private var allTokens: [PositionToken]

    private var currencyCode: String {
        appState.currencyCode
    }

    var body: some View {
        let data = sources.platforms(allTokens)
        Table(data.entries) {
            TableColumn("Platform") { entry in
                switch entry {
                case let .row(row):
                    Text(row.name).fontWeight(.medium).foregroundStyle(PortuTheme.dashboardText)
                case let .hidden(line):
                    Text(line.title).foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
            }
            TableColumn("Share %") { entry in
                Text(AllAssetsFormat.share(entry.row?.share ?? entry.hidden?.share))
                    .font(DashboardStyle.monoTableFont)
            }
            TableColumn("# Networks") { entry in Text(entry.row.map { "\($0.networkCount)" } ?? "") }
            TableColumn("# Positions") { entry in Text(entry.row.map { "\($0.positionCount)" } ?? "") }
            TableColumn("Balance") { entry in
                Text(entry.row?.balance ?? entry.hidden?.value ?? 0, format: .currency(code: currencyCode))
                    .font(DashboardStyle.monoTableFont)
            }
        }
        .dashboardTable()
    }
}

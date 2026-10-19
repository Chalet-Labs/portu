import PortuCore
import PortuUI
import SwiftUI

struct AllPositionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.activePortfolio) private var portfolio
    var sources = ValuationSources()

    @State private var filter = AllPositionsFilter.all
    @State private var showAddSheet = false

    private var currencyCode: String {
        appState.currencyCode
    }

    var body: some View {
        let page = sources.allPositions(portfolio, filter: filter)
        HSplitView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
                    DashboardPageHeader("All Positions") {
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add Position", systemImage: "plus")
                        }
                        .dashboardControl()
                    }

                    ForEach(page.sections) { section in
                        Section {
                            ForEach(section.cards) { card in
                                PositionGroupView(card: card, currencyCode: currencyCode)
                            }
                        } header: {
                            HStack {
                                Text(section.title)
                                    .font(DashboardStyle.sectionTitleFont)
                                    .foregroundStyle(PortuTheme.dashboardText)
                                Spacer()
                                Text(AllPositionsFormat.currency(section.total, code: currencyCode))
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(DashboardStyle.pagePadding)
            }
            .frame(minWidth: 500)
            .sheet(isPresented: $showAddSheet) {
                AddPositionSheet()
                    .environment(\.colorScheme, .dark)
            }

            PositionFilterSidebar(
                typeOptions: page.typeOptions,
                protocolOptions: page.protocolOptions,
                currencyCode: currencyCode,
                selectedType: $filter.type,
                selectedProtocol: $filter.protocolFilter)
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
        }
        .dashboardPage()
    }
}

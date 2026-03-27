import SwiftData
import SwiftUI
import PortuCore
import PortuUI

struct AllPositionsView: View {
    private struct TokenSyncToken: Equatable {
        let id: UUID
        let role: TokenRole
        let amount: Decimal
        let usdValue: Decimal
        let assetID: UUID?

        init(token: PositionToken) {
            self.id = token.id
            self.role = token.role
            self.amount = token.amount
            self.usdValue = token.usdValue
            self.assetID = token.asset?.id
        }
    }

    private struct PositionSyncToken: Equatable {
        let id: UUID
        let positionType: PositionType
        let netUSDValue: Decimal
        let chain: Chain?
        let protocolID: String?
        let protocolName: String?
        let healthFactor: Double?
        let accountID: UUID?
        let accountIsActive: Bool
        let tokens: [TokenSyncToken]

        init(position: Position) {
            self.id = position.id
            self.positionType = position.positionType
            self.netUSDValue = position.netUSDValue
            self.chain = position.chain
            self.protocolID = position.protocolId
            self.protocolName = position.protocolName
            self.healthFactor = position.healthFactor
            self.accountID = position.account?.id
            self.accountIsActive = position.account?.isActive == true
            self.tokens = position.tokens
                .map(TokenSyncToken.init)
                .sorted { $0.id.uuidString < $1.id.uuidString }
        }
    }

    static let navigationTitle = "All Positions"

    @Query private var positions: [Position]
    @State private var viewModel = AllPositionsViewModel()

    private var positionsSyncToken: [PositionSyncToken] {
        positions
            .map(PositionSyncToken.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.sections.isEmpty {
                        ContentUnavailableView {
                            Label(viewModel.emptyStateTitle, systemImage: "tray.full")
                        } description: {
                            Text(viewModel.emptyStateMessage)
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(viewModel.sections) { section in
                                PositionSectionView(section: section)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 700, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            PositionFilterSidebar(
                selectedPositionFilter: $bindableViewModel.selectedFilter,
                selectedProtocol: $bindableViewModel.selectedProtocol,
                positionFilterTotals: viewModel.positionFilterTotals,
                protocolOptions: viewModel.protocolOptions
            )
        }
        .navigationTitle(Self.navigationTitle)
        .task(id: positionsSyncToken) {
            viewModel.updatePositions(positions)
        }
    }
}

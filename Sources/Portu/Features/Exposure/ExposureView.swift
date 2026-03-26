import SwiftData
import SwiftUI
import PortuCore

struct ExposureView: View {
    static let navigationTitle = "Exposure"

    @Query private var positions: [Position]
    @State private var viewModel = ExposureViewModel()

    private var positionsFingerprint: [PositionFingerprint] {
        positions
            .map(PositionFingerprint.init(position:))
            .sorted { $0.positionID.uuidString < $1.positionID.uuidString }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ExposureSummaryCards(
                rows: viewModel.categoryRows,
                netExposureExcludingStablecoins: viewModel.netExposureExcludingStablecoins
            )

            Picker("Display", selection: $viewModel.displayMode) {
                ForEach(ExposureDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            ExposureTable(
                rows: viewModel.visibleRows,
                displayMode: viewModel.displayMode
            )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(Self.navigationTitle)
        .onAppear {
            viewModel.refresh(positions: positions)
        }
        .onChange(of: positionsFingerprint) { _, _ in
            viewModel.refresh(positions: positions)
        }
    }
}

private struct PositionFingerprint: Equatable {
    let positionID: UUID
    let accountIsActive: Bool
    let tokens: [TokenFingerprint]

    init(position: Position) {
        positionID = position.id
        accountIsActive = position.account?.isActive == true
        tokens = position.tokens
            .map(TokenFingerprint.init(token:))
            .sorted { $0.tokenID.uuidString < $1.tokenID.uuidString }
    }
}

private struct TokenFingerprint: Equatable {
    let tokenID: UUID
    let role: TokenRole
    let usdValue: Decimal
    let assetID: UUID?
    let assetSymbol: String?
    let assetName: String?
    let assetCategory: AssetCategory?
    let coinGeckoID: String?

    init(token: PositionToken) {
        tokenID = token.id
        role = token.role
        usdValue = token.usdValue
        assetID = token.asset?.id
        assetSymbol = token.asset?.symbol
        assetName = token.asset?.name
        assetCategory = token.asset?.category
        coinGeckoID = token.asset?.coinGeckoId
    }
}

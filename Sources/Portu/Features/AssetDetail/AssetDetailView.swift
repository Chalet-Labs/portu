import SwiftData
import SwiftUI
import PortuCore
import PortuNetwork

struct AssetDetailView: View {
    let assetID: Asset.ID

    @Query private var assets: [Asset]
    @Query private var positions: [Position]
    @Query private var assetSnapshots: [AssetSnapshot]
    @Query private var portfolioSnapshots: [PortfolioSnapshot]

    @State private var historicalPrices: [HistoricalPricePoint] = []
    @State private var comparisonPrices: [HistoricalPricePoint] = []
    @State private var selectedMode: AssetChartMode = .price
    @State private var selectedComparison: AssetComparison?

    var body: some View {
        Group {
            if showsMissingAssetState {
                ContentUnavailableView(
                    "Asset Not Found",
                    systemImage: "questionmark.square.dashed"
                )
            } else {
                HSplitView {
                    VStack(alignment: .leading, spacing: 20) {
                        AssetPriceChart(
                            mode: $selectedMode,
                            selectedComparison: $selectedComparison,
                            priceSeries: viewModel.priceSeries,
                            valueSeries: viewModel.valueSeries,
                            amountSeries: viewModel.amountSeries,
                            comparisonSeries: comparisonSeries
                        )

                        AssetSummarySection(
                            accountCount: viewModel.accountCount,
                            totalAmount: viewModel.totalAmount,
                            totalUSDValue: viewModel.totalUSDValue,
                            networkRows: viewModel.networkRows,
                            containsPartialHistory: viewModel.containsPartialHistory
                        )

                        AssetPositionsTable(rows: viewModel.positionRows)
                    }
                    .frame(minWidth: 760, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    AssetMetadataSidebar(
                        assetName: assetName,
                        symbol: assetSymbol,
                        categoryTitle: categoryTitle,
                        coinGeckoID: primaryCoinGeckoID,
                        selectedModeTitle: selectedMode.title,
                        selectedSummaryLabel: viewModel.selectedSummaryLabel,
                        containsPartialHistory: viewModel.containsPartialHistory
                    )
                }
            }
        }
        .padding()
        .navigationTitle(assetSymbol)
        .task(id: primaryCoinGeckoID) {
            await loadHistoricalPrices()
        }
        .task(id: comparisonCoinGeckoID) {
            await loadComparisonPrices()
        }
    }

    private var viewModel: AssetDetailViewModel {
        let viewModel = AssetDetailViewModel(
            assetID: assetID,
            positions: positions,
            assetSnapshots: assetSnapshots,
            historicalPrices: historicalPrices,
            portfolioSnapshots: portfolioSnapshots
        )
        viewModel.selectedMode = selectedMode
        viewModel.selectedComparison = selectedComparison
        return viewModel
    }

    private var comparisonSeries: [PerformancePoint] {
        comparisonPrices
            .map { point in
                PerformancePoint(
                    date: point.date,
                    value: point.price,
                    usesAccountSnapshot: false
                )
            }
            .sorted { $0.date < $1.date }
    }

    private var showsMissingAssetState: Bool {
        assetRecord == nil
            && matchingAssetFromPositions == nil
            && matchingSnapshot == nil
    }

    private var primaryCoinGeckoID: String? {
        assetRecord?.coinGeckoId ?? matchingAssetFromPositions?.coinGeckoId
    }

    private var comparisonCoinGeckoID: String? {
        selectedComparison?.coinGeckoID
    }

    private var matchingAssetFromPositions: Asset? {
        positions
            .lazy
            .flatMap(\.tokens)
            .compactMap(\.asset)
            .first(where: { $0.id == assetID })
    }

    private var matchingSnapshot: AssetSnapshot? {
        assetSnapshots.first(where: { $0.assetId == assetID })
    }

    private var assetRecord: Asset? {
        assets.first(where: { $0.id == assetID })
    }

    private var assetName: String {
        assetRecord?.name
            ?? matchingAssetFromPositions?.name
            ?? matchingSnapshot?.symbol
            ?? "Unknown Asset"
    }

    private var assetSymbol: String {
        assetRecord?.symbol
            ?? matchingAssetFromPositions?.symbol
            ?? matchingSnapshot?.symbol
            ?? "Asset Detail"
    }

    private var categoryTitle: String {
        if let category = assetRecord?.category ?? matchingAssetFromPositions?.category ?? matchingSnapshot?.category {
            return category.rawValue.capitalized
        }

        return "Unknown"
    }

    private func loadHistoricalPrices() async {
        historicalPrices = []

        guard let coinGeckoID = primaryCoinGeckoID else {
            return
        }

        let priceService = PriceService()
        historicalPrices = (try? await priceService.fetchHistoricalPrices(for: coinGeckoID, days: 365)) ?? []
    }

    private func loadComparisonPrices() async {
        comparisonPrices = []

        guard let coinGeckoID = comparisonCoinGeckoID else {
            return
        }

        let priceService = PriceService()
        comparisonPrices = (try? await priceService.fetchHistoricalPrices(for: coinGeckoID, days: 365)) ?? []
    }
}

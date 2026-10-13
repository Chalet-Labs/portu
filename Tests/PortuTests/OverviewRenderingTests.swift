import Foundation
@testable import Portu
import PortuCore
import Testing

/// What the Overview renders from its seams: the hidden-balances line (F3), the 24h percentage
/// (A4), the donut's chart and legend, the Health weight list and a tab's empty state.
struct OverviewRenderingTests {
    private typealias Fixture = PortfolioValuationFixture

    private static func inputs(_ numbers: Set<Int>) -> [ValuationInput] {
        Fixture.inputs.filter { input in numbers.contains { Fixture.tokenID($0) == input.tokenId } }
    }

    // MARK: - Hidden-balances line (F3)

    @Test func `one dust row reads as a small balance`() {
        let line = OverviewPriceDisplay.hiddenBalancesLine(value: Fixture.decimal("0.5"), rowCount: 1, isAllDust: true)

        #expect(line == "+ $ 0.5 in 1 small balance")
    }

    @Test func `rows with an unpriced one read as hidden balances`() {
        let line = OverviewPriceDisplay.hiddenBalancesLine(value: Fixture.decimal("12.34"), rowCount: 3, isAllDust: false)

        #expect(line == "+ $ 12.34 in 3 hidden balances")
    }

    @Test func `a negative sum takes a minus sign`() {
        let line = OverviewPriceDisplay.hiddenBalancesLine(value: Fixture.decimal("-0.7"), rowCount: 2, isAllDust: true)

        #expect(line == "\u{2212} $ 0.7 in 2 small balances")
    }

    @Test func `a zero sum reads as a positive amount`() {
        let line = OverviewPriceDisplay.hiddenBalancesLine(value: 0, rowCount: 2, isAllDust: false)

        #expect(line == "+ $ 0 in 2 hidden balances")
    }

    @Test(arguments: [("EUR", "+ € 0.5 in 1 small balance"), ("CHF", "+ CHF 0.5 in 1 small balance")])
    func `the line uses the display currency`(currencyCode: String, expected: String) {
        let line = OverviewPriceDisplay.hiddenBalancesLine(
            value: Fixture.decimal("0.5"),
            rowCount: 1,
            isAllDust: true,
            currencyCode: currencyCode)

        #expect(line == expected)
    }

    @Test func `a large sum is compacted like every other amount`() {
        let line = OverviewPriceDisplay.hiddenBalancesLine(value: 2_500_000, rowCount: 4, isAllDust: true)

        #expect(line == "+ $ 2.5M in 4 small balances")
    }

    @Test func `the line reads the hidden sum on the list basis`() throws {
        let borrowing = OverviewPositionProjection.tab(
            .borrowing,
            context: Fixture.context(rate: Fixture.decimal("0.9")),
            positions: Fixture.positions)
        let stables = OverviewPositionProjection.tab(.idleStables, context: Fixture.context(), positions: Fixture.positions)

        let aave = try #require(borrowing.groups.first)
        let aaveHidden = try #require(aave.hidden)
        #expect(OverviewPriceDisplay.hiddenBalancesLine(aaveHidden, basis: aave.basis) == "+ $ 0.36 in 1 small balance")
        let wallet = try #require(stables.groups.first)
        let walletHidden = try #require(wallet.hidden)
        #expect(OverviewPriceDisplay.hiddenBalancesLine(walletHidden, basis: wallet.basis) == "+ $ 0.5 in 1 small balance")
    }

    // MARK: - 24h percentage (A4)

    @Test func `the 24h percentage is a dash without a positive prior total`() {
        let headline = OverviewFeature.headline(Fixture.context(inputs: Self.inputs([13])))

        #expect(OverviewPriceDisplay.changePercentage(headline.changePercentage) == "—")
    }

    @Test func `the 24h percentage shows two decimals`() {
        #expect(OverviewPriceDisplay.changePercentage(Fixture.decimal("0.0123")) == "1.23%")
        #expect(OverviewPriceDisplay.changePercentage(Fixture.decimal("-0.0456")) == "-4.56%")
        #expect(OverviewPriceDisplay.changePercentage(0) == "0.00%")
    }

    /// Only POSIX leaves out the grouping separator and the space before the sign, so this fails on
    /// any host locale if the formatter loses its fixed locale.
    @Test func `the 24h percentage ignores the host locale`() {
        #expect(OverviewPriceDisplay.changePercentage(Fixture.decimal("12.345")) == "1234.50%")
    }

    // MARK: - Top Assets donut

    @Test func `the donut charts every positive slice and the hidden gross`() {
        let topAssets = OverviewFeature.topAssets(.assets, context: Fixture.context())

        #expect(!topAssets.isEmpty)
        #expect(topAssets.chartSlices == topAssets.slices)
        #expect(topAssets.hiddenChartValue == Fixture.decimal("0.5"))
    }

    @Test func `hidden rows with no gross get a legend row and no slice`() {
        // USDC is shown; BAD's implausible onchain price leaves it unpriced, so it is hidden at 0.
        let topAssets = OverviewFeature.topAssets(.assets, context: Fixture.context(inputs: Self.inputs([1, 8])))

        #expect(topAssets.hidden?.rowCount == 1)
        #expect(topAssets.hidden?.unpricedCount == 1)
        #expect(topAssets.hiddenDisplayPercent == 0)
        #expect(topAssets.hiddenChartValue == nil)
    }

    @Test func `a visible zero value row is a legend row with no slice`() {
        let topAssets = OverviewFeature.topAssets(
            .assets,
            context: Fixture.context(settings: TokenDashboardSettings(hideUnpriced: false), inputs: Self.inputs([1, 8])))

        #expect(topAssets.slices.count == 2)
        #expect(topAssets.slices.contains { $0.value == 0 })
        #expect(topAssets.chartSlices.map(\.value) == [1000])
        #expect(topAssets.slices.map(\.displayPercent) == [100, 0])
        #expect(topAssets.hidden == nil)
    }

    @Test func `a donut whose every row is hidden still shows its hidden line`() {
        let topAssets = OverviewFeature.topAssets(.assets, context: Fixture.context(inputs: Self.inputs([4])))

        #expect(topAssets.slices.isEmpty)
        #expect(!topAssets.isEmpty)
        #expect(topAssets.hiddenChartValue == Fixture.decimal("0.5"))
        #expect(topAssets.hiddenDisplayPercent == 100)
    }

    @Test func `a donut with nothing to show is empty`() {
        let topAssets = OverviewFeature.topAssets(.assets, context: Fixture.context(inputs: []))

        #expect(topAssets.isEmpty)
    }

    // MARK: - Health weight list

    @Test func `the collapsed health list previews the top five with their unrounded weights`() {
        let health = PortfolioHealthFeature.health(Fixture.context())
        let list = health.weightList(showAll: false)

        #expect(!list.isExpanded)
        #expect(list.rows.map(\.weight) == Array(health.weights.prefix(5)))
        #expect(list.rows.map(\.share) == health.weights.prefix(5).map(\.percentage))
        #expect(list.hidden == nil)
        #expect(list.hiddenShare == nil)
    }

    @Test func `the expanded health list shows rounded shares that sum to one with its hidden line`() throws {
        let health = PortfolioHealthFeature.health(Fixture.context())
        let list = health.weightList(showAll: true)
        let shares = try #require(health.displayShares)

        #expect(list.isExpanded)
        #expect(list.rows.map(\.weight) == health.weights)
        #expect(list.rows.map(\.share) == shares.rows)
        #expect(list.hidden?.gross == Fixture.decimal("0.5"))
        #expect(list.hiddenShare == shares.hidden)
        #expect(Self.shareSum(list) == 1)
    }

    @Test func `a health list of five rows or fewer is shown in full`() {
        // USDC and ETH are shown; DAI is dust.
        let health = PortfolioHealthFeature.health(Fixture.context(inputs: Self.inputs([1, 2, 4])))
        let list = health.weightList(showAll: false)

        #expect(list.isExpanded)
        #expect(list.rows.map(\.weight.symbol) == ["ETH", "USDC"])
        #expect(list.hidden?.rowCount == 1)
        #expect(Self.shareSum(list) == 1)
    }

    private static func shareSum(_ list: PortfolioHealthWeightList) -> Decimal {
        let rows = list.rows.compactMap(\.share).reduce(Decimal.zero, +)
        return rows + (list.hiddenShare ?? 0)
    }

    // MARK: - Position tabs

    @Test func `a tab with only a hidden line does not show its empty message`() {
        let tab = OverviewPositionProjection.tab(
            .idleStables,
            context: Fixture.context(inputs: Self.inputs([4])),
            positions: Fixture.positions)

        #expect(tab.groups.isEmpty)
        #expect(!tab.showsEmptyState)
    }

    @Test func `a tab with nothing to show shows its empty message`() {
        let tab = OverviewPositionProjection.tab(.idleStables, context: Fixture.context(inputs: []), positions: Fixture.positions)

        #expect(tab.showsEmptyState)
    }
}

import SwiftUI
import PortuCore
import PortuUI

struct ExposureSummaryCards: View {
    let rows: [ExposureRow]
    let netExposureExcludingStablecoins: Decimal

    private var spotAssetsTotal: Decimal {
        rows.reduce(.zero) { partialResult, row in
            partialResult + row.spotAssets
        }
    }

    private var liabilitiesTotal: Decimal {
        rows.reduce(.zero) { partialResult, row in
            partialResult + row.liabilities
        }
    }

    private var spotNetTotal: Decimal {
        rows.reduce(.zero) { partialResult, row in
            partialResult + row.spotNet
        }
    }

    private var derivativesLongTotal: Decimal {
        rows.reduce(.zero) { partialResult, row in
            partialResult + row.derivativesLong
        }
    }

    private var derivativesShortTotal: Decimal {
        rows.reduce(.zero) { partialResult, row in
            partialResult + row.derivativesShort
        }
    }

    private var derivativesNetTotal: Decimal {
        derivativesLongTotal - derivativesShortTotal
    }

    private var stablecoinSpotNet: Decimal {
        rows
            .first(where: { $0.category == .stablecoin })?
            .spotNet ?? .zero
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                "Exposure Overview",
                subtitle: "Spot balances, current leverage, and stablecoin-adjusted net risk"
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    cards
                }

                VStack(spacing: 12) {
                    cards
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cards: some View {
        Group {
            StatCard(
                title: "Spot Total",
                value: spotAssetsTotal.formatted(.currency(code: "USD")),
                subtitle: "Assets across active accounts",
                detailLines: [
                    detailLine(title: "Liabilities", value: liabilitiesTotal),
                    detailLine(title: "Spot Net", value: spotNetTotal)
                ]
            )

            StatCard(
                title: "Derivatives",
                value: derivativesNetTotal.formatted(.currency(code: "USD")),
                subtitle: "Long / short exposure (future work)",
                detailLines: [
                    detailLine(title: "Longs", value: derivativesLongTotal),
                    detailLine(title: "Shorts", value: derivativesShortTotal)
                ]
            )

            StatCard(
                title: "Net Exposure",
                value: netExposureExcludingStablecoins.formatted(.currency(code: "USD")),
                subtitle: "Stablecoins neutralized",
                detailLines: [
                    detailLine(title: "Spot Net", value: spotNetTotal),
                    detailLine(title: "Stablecoins", value: stablecoinSpotNet)
                ],
                valueColor: exposureColor(for: netExposureExcludingStablecoins)
            )
        }
    }

    private func detailLine(
        title: String,
        value: Decimal
    ) -> String {
        "\(title): \(value.formatted(.currency(code: "USD")))"
    }

    private func exposureColor(
        for value: Decimal
    ) -> Color? {
        if value > .zero {
            return .green
        }

        if value < .zero {
            return .red
        }

        return nil
    }
}

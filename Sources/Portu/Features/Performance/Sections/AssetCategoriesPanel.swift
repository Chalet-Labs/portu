import SwiftUI
import PortuCore
import PortuUI

struct AssetCategoriesPanel: View {
    let rows: [CategorySummaryRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                "Asset Categories",
                subtitle: "Start vs end category value across the selected period"
            )

            if rows.isEmpty {
                emptyState("Sync more asset snapshots to compare category performance.")
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    headerRow

                    ForEach(rows) { row in
                        GridRow {
                            Text(categoryTitle(for: row.category))
                                .fontWeight(.medium)

                            Text(row.startValue, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)

                            Text(row.endValue, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)

                            changeLabel(
                                hasDefinedPercent: row.hasDefinedChangePercent,
                                percent: row.changePercent
                            )
                        }
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var headerRow: some View {
        GridRow {
            Text("Category")
            Text("Start")
            Text("End")
            Text("Change")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func categoryTitle(
        for category: AssetCategory
    ) -> String {
        category.rawValue.capitalized
    }

    private func signedPercent(
        _ value: Decimal
    ) -> String {
        let prefix = value > .zero ? "+" : ""
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(2))))%"
    }

    @ViewBuilder
    private func changeLabel(
        hasDefinedPercent: Bool,
        percent: Decimal
    ) -> some View {
        if hasDefinedPercent {
            Text(signedPercent(percent))
                .foregroundStyle(changeColor(for: percent))
        } else {
            Text("New")
                .foregroundStyle(.secondary)
        }
    }

    private func changeColor(
        for value: Decimal
    ) -> Color {
        if value < .zero {
            return .red
        }

        if value > .zero {
            return .green
        }

        return .secondary
    }

    @ViewBuilder
    private func emptyState(
        _ message: String
    ) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.quaternary.opacity(0.6))
            .frame(height: 220)
            .overlay {
                Text(message)
                    .foregroundStyle(.secondary)
            }
    }
}

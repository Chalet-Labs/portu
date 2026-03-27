import SwiftUI
import PortuUI

struct PositionSectionView: View {
    let section: PositionSectionModel
    var isNested: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader

            if section.rows.isEmpty == false {
                rowsView
            }

            if section.children.isEmpty == false {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(section.children) { child in
                        PositionSectionView(section: child, isNested: true)
                    }
                }
            }
        }
        .padding(isNested ? 16 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isNested ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .underPageBackgroundColor),
            in: RoundedRectangle(cornerRadius: isNested ? 16 : 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isNested ? 16 : 20, style: .continuous)
                .strokeBorder(.quaternary)
        )
    }

    private var sectionHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            SectionHeader(
                section.title,
                subtitle: sectionSubtitle
            )

            Spacer(minLength: 0)

            CurrencyText(section.value)
                .font(isNested ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
        }
    }

    private var rowsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(section.rows) { row in
                PositionTokenRowView(row: row)

                if row.id != section.rows.last?.id {
                    Divider()
                }
            }
        }
        .padding(.top, 4)
    }

    private var sectionSubtitle: String? {
        if let protocolName = section.protocolName {
            var parts: [String] = []

            if let chainLabel = section.chainLabel {
                parts.append(chainLabel)
            }

            if let healthFactor = section.healthFactor {
                parts.append("HF \(healthFactor.formatted(.number.precision(.fractionLength(1))))")
            }

            if parts.isEmpty {
                return protocolName
            }

            return parts.joined(separator: " | ")
        }

        if section.children.isEmpty == false {
            return section.children.count == 1 ? "1 protocol" : "\(section.children.count) protocols"
        }

        if section.rows.isEmpty == false {
            return section.rows.count == 1 ? "1 token row" : "\(section.rows.count) token rows"
        }

        return nil
    }
}

private struct PositionTokenRowView: View {
    let row: PositionTokenRowModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(row.symbol) - \(row.roleLabel)")
                    .font(.subheadline.weight(.semibold))

                Text("\(row.assetName) / \(row.accountName) / \(row.chainLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                CurrencyText(row.displayValue)
                    .font(.subheadline.weight(.semibold))

                Text("\(formattedAmount(row.displayAmount)) \(row.symbol)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func formattedAmount(_ amount: Decimal) -> String {
        amount.formatted(.number.precision(.fractionLength(0...6)))
    }
}

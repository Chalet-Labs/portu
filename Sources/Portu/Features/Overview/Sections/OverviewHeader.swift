import SwiftUI
import PortuUI

struct OverviewHeader: View {
    struct ChangePresentation: Equatable {
        let iconName: String
        let prefix: String
    }

    let viewModel: OverviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Portfolio")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    CurrencyText(viewModel.totalValue)
                        .font(.largeTitle.weight(.bold))

                    HStack(spacing: 12) {
                        ChangeBadge(
                            absoluteChange: viewModel.absoluteChange24h,
                            percentageChange: viewModel.percentageChange24h
                        )

                        Text(lastSyncedLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Sync") {
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    static func changePresentation(for value: Decimal) -> ChangePresentation {
        if value > .zero {
            return ChangePresentation(iconName: "arrow.up.right", prefix: "+")
        }
        if value < .zero {
            return ChangePresentation(iconName: "arrow.down.right", prefix: "-")
        }
        return ChangePresentation(iconName: "minus", prefix: "")
    }

    private var lastSyncedLabel: String {
        guard let latestSnapshot = viewModel.latestSnapshot else {
            return "No snapshot history yet"
        }

        return "Last synced \(latestSnapshot.timestamp.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct ChangeBadge: View {
    let absoluteChange: Decimal
    let percentageChange: Decimal

    var body: some View {
        let absolutePresentation = OverviewHeader.changePresentation(for: absoluteChange)

        HStack(spacing: 10) {
            Image(systemName: absolutePresentation.iconName)
                .imageScale(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(signedCurrency(absoluteChange))
                    .font(.headline)
                Text(signedPercent(percentageChange))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(PortuTheme.changeColor(for: absoluteChange))
        .background(.background, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signedCurrency(absoluteChange)), \(signedPercent(percentageChange))")
    }

    private func signedCurrency(_ value: Decimal) -> String {
        let absoluteValue = value < .zero ? -value : value
        let prefix = OverviewHeader.changePresentation(for: value).prefix
        return "\(prefix)\(absoluteValue.formatted(.currency(code: "USD")))"
    }

    private func signedPercent(_ value: Decimal) -> String {
        let absoluteValue = value < .zero ? -value : value
        let prefix = OverviewHeader.changePresentation(for: value).prefix
        return "\(prefix)\(absoluteValue.formatted(.number.precision(.fractionLength(2))))%"
    }
}

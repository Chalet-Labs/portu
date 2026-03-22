import SwiftUI

/// A card displaying a labeled statistic value.
public struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let detailLines: [String]
    let valueColor: Color?

    public init(
        title: String,
        value: String,
        subtitle: String? = nil,
        detailLines: [String] = [],
        valueColor: Color? = nil
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.detailLines = detailLines
        self.valueColor = valueColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(valueColor ?? .primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !detailLines.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(detailLines, id: \.self) { line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary)
        )
    }
}

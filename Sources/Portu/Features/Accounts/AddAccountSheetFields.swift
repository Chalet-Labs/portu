import PortuCore
import PortuUI
import SwiftUI

struct AddAccountInfoRow: View {
    let icon: String
    var iconColor: Color = .blue.opacity(0.88)
    let text: String
    var showsExternalLink = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 14)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(PortuTheme.dashboardSecondaryText)

            if showsExternalLink {
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardGold)
            }
        }
    }
}

struct AddAccountTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isRequired = false
    var isMonospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AddAccountFieldLabel(title: title, isRequired: isRequired)

            TextField("", text: $text, prompt: Text(placeholder))
                .textFieldStyle(.plain)
                .font(fieldFont)
                .foregroundStyle(PortuTheme.dashboardText)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .addAccountFieldSurface()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fieldFont: Font {
        isMonospaced ? .system(size: 13, design: .monospaced) : .system(size: 13)
    }
}

struct AddAccountSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isRequired = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AddAccountFieldLabel(title: title, isRequired: isRequired)

            SecureField("", text: $text, prompt: Text(placeholder))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(PortuTheme.dashboardText)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .addAccountFieldSurface()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AddAccountMenuField<Content: View>: View {
    let title: String
    let value: String
    var isRequired = false
    let content: Content

    init(
        title: String,
        value: String,
        isRequired: Bool = false,
        @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.isRequired = isRequired
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AddAccountFieldLabel(title: title, isRequired: isRequired)

            Menu {
                content
            } label: {
                HStack(spacing: 8) {
                    Text(value)
                        .font(.system(size: 13))
                        .foregroundStyle(PortuTheme.dashboardText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .contentShape(Rectangle())
                .addAccountFieldSurface()
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AddAccountFieldLabel: View {
    let title: String
    var isRequired = false

    var body: some View {
        Text(isRequired ? "\(title) *" : title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
    }
}

struct InlineSourceNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "bolt.horizontal.circle")
            .font(.system(size: 11))
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for element in row.elements {
                subviews[element.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(element.size))
                x += element.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(in maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.width == 0 ? size.width : current.width + spacing + size.width
            if nextWidth > maxWidth, !current.elements.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.elements.append(Row.Element(index: index, size: size))
            current.width = current.width == 0 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.elements.isEmpty {
            rows.append(current)
        }

        return rows
    }

    private struct Row {
        var elements: [Element] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        struct Element {
            let index: Int
            let size: CGSize
        }
    }
}

extension View {
    func addAccountFieldSurface() -> some View {
        background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PortuTheme.dashboardMutedPanelBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
    }
}

extension Chain {
    var addAccountTitle: String {
        switch self {
        case .ethereum: "Ethereum"
        case .polygon: "Polygon"
        case .arbitrum: "Arbitrum"
        case .optimism: "Optimism"
        case .base: "Base"
        case .bsc: "BNB Smart Chain"
        case .solana: "Solana"
        case .bitcoin: "Bitcoin"
        case .avalanche: "Avalanche"
        case .monad: "Monad"
        case .katana: "Katana"
        }
    }
}

extension ExchangeType {
    var addAccountTitle: String {
        switch self {
        case .binance: "Binance"
        case .coinbase: "Coinbase"
        case .kraken: "Kraken"
        }
    }
}

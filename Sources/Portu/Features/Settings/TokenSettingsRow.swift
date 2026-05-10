import Foundation
import PortuCore
import SwiftUI

struct TokenSettingsOverrideDraft: Equatable {
    var manualPriceText: String
    var coinGeckoIdText: String
    var notes: String

    init(override: TokenPricingOverrideSnapshot?) {
        self.manualPriceText = TokenSettingsFormat.optionalNumber(override?.manualPriceUSD)
        self.coinGeckoIdText = override?.coinGeckoIdOverride ?? ""
        self.notes = override?.notes ?? ""
    }
}

struct TokenSettingsRowView: View {
    let row: TokenSettingsRow
    let categories: [PortfolioCategory]
    let saveOverride: (UUID, String, String, String) -> Void
    let assignCategory: (String, UUID) -> Void
    let setIgnored: (UUID, Bool) -> Void
    let setAlwaysShow: (UUID, Bool) -> Void
    let resetOverride: (UUID) -> Bool

    @State private var manualPriceText: String
    @State private var coinGeckoIdText: String
    @State private var notes: String

    init(
        row: TokenSettingsRow,
        categories: [PortfolioCategory],
        saveOverride: @escaping (UUID, String, String, String) -> Void,
        assignCategory: @escaping (String, UUID) -> Void,
        setIgnored: @escaping (UUID, Bool) -> Void,
        setAlwaysShow: @escaping (UUID, Bool) -> Void,
        resetOverride: @escaping (UUID) -> Bool) {
        self.row = row
        self.categories = categories
        self.saveOverride = saveOverride
        self.assignCategory = assignCategory
        self.setIgnored = setIgnored
        self.setAlwaysShow = setAlwaysShow
        self.resetOverride = resetOverride
        let draft = TokenSettingsOverrideDraft(override: row.override)
        _manualPriceText = State(initialValue: draft.manualPriceText)
        _coinGeckoIdText = State(initialValue: draft.coinGeckoIdText)
        _notes = State(initialValue: draft.notes)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tokenIdentity
                .frame(width: 170, alignment: .leading)

            valueSummary
                .frame(width: 104, alignment: .leading)

            pricingSummary
                .frame(width: 118, alignment: .leading)

            overrideControls
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsDesign.subtleCardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SettingsDesign.cardStroke, lineWidth: 1))
        .onChange(of: row.override) { _, override in
            let draft = TokenSettingsOverrideDraft(override: override)
            manualPriceText = draft.manualPriceText
            coinGeckoIdText = draft.coinGeckoIdText
            notes = draft.notes
        }
    }

    private var tokenIdentity: some View {
        HStack(spacing: 10) {
            TokenSettingsLogo(row: row)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SettingsDesign.primaryText)
                    .lineLimit(1)
                Text(row.name)
                    .font(.caption)
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var valueSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TokenSettingsFormat.currency(row.value))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SettingsDesign.primaryText)
                .lineLimit(1)
            Text(TokenSettingsFormat.decimal(row.amount))
                .font(.caption)
                .foregroundStyle(SettingsDesign.secondaryText)
                .lineLimit(1)
        }
    }

    private var pricingSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(row.pricingSource.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(sourceColor)
            Text(row.visibilityStatus.rawValue)
                .font(.caption)
                .foregroundStyle(SettingsDesign.secondaryText)
            if let coinGeckoId = row.coinGeckoId {
                Text(coinGeckoId)
                    .font(.caption2)
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var overrideControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                categoryPicker
                Toggle("Ignore", isOn: Binding(
                    get: { row.override?.isIgnored ?? false },
                    set: { setIgnored(row.assetId, $0) }))
                Toggle("Always show", isOn: Binding(
                    get: { row.override?.alwaysShow ?? false },
                    set: { setAlwaysShow(row.assetId, $0) }))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(SettingsDesign.primaryText)

            HStack(spacing: 8) {
                TextField("Manual price", text: $manualPriceText)
                    .textFieldStyle(.plain)
                    .settingsInputFrame(height: 32)
                TextField("CoinGecko ID", text: $coinGeckoIdText)
                    .textFieldStyle(.plain)
                    .settingsInputFrame(height: 32)
            }

            HStack(spacing: 8) {
                TextField("Notes", text: $notes)
                    .textFieldStyle(.plain)
                    .settingsInputFrame(height: 32)

                Button("Save") {
                    saveOverride(row.assetId, manualPriceText, coinGeckoIdText, notes)
                }
                .buttonStyle(.plain)
                .settingsPrimaryButton(isDisabled: false)

                Button("Reset") {
                    if resetOverride(row.assetId) {
                        manualPriceText = ""
                        coinGeckoIdText = ""
                        notes = ""
                    } else {
                        manualPriceText = TokenSettingsFormat.optionalNumber(row.override?.manualPriceUSD)
                        coinGeckoIdText = row.override?.coinGeckoIdOverride ?? ""
                        notes = row.override?.notes ?? ""
                    }
                }
                .buttonStyle(.plain)
                .settingsIconButton(color: SettingsDesign.warningOrange)
            }
        }
    }

    @ViewBuilder
    private var categoryPicker: some View {
        if categories.isEmpty {
            Text(row.portfolioCategory.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SettingsDesign.secondaryText)
                .frame(width: 160, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                Text("Category")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettingsDesign.secondaryText)
                Picker("Category", selection: Binding(
                    get: { row.portfolioCategory.id },
                    set: { assignCategory(row.symbol, $0) })) {
                        ForEach(categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 128)
            }
        }
    }

    private var sourceColor: Color {
        switch row.pricingSource {
        case .live: SettingsDesign.successBadgeText
        case .syncTime: SettingsDesign.accentBlue
        case .manual: SettingsDesign.tokenTeal
        case .unpriced: SettingsDesign.warningOrange
        }
    }
}

private struct TokenSettingsLogo: View {
    let row: TokenSettingsRow

    var body: some View {
        Group {
            if let logoURL = row.logoURL, let url = URL(string: logoURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: 30, height: 30)
        .background(
            Circle()
                .fill(SettingsDesign.tokenGlyphBackground))
        .clipShape(Circle())
    }

    private var fallback: some View {
        Text(String(row.symbol.prefix(1)).uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(SettingsDesign.tokenTeal)
    }
}

enum ManualPriceInput {
    case empty
    case invalid(String)
    case valid(Decimal)

    var value: Decimal? {
        if case let .valid(value) = self { return value }
        return nil
    }
}

enum TokenSettingsFormat {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func currency(_ value: Decimal) -> String {
        "$ \(number(value))"
    }

    static func decimal(_ value: Decimal) -> String {
        number(value)
    }

    static func number(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        return number.formatted(.number
            .locale(locale)
            .grouping(.automatic)
            .precision(.fractionLength(0 ... maximumFractionDigits(for: abs(number)))))
    }

    static func optionalNumber(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return number(value)
    }

    static func decimal(from text: String) -> Decimal? {
        if case let .valid(value) = parseManualPrice(text) {
            return value
        }
        return nil
    }

    static func parseManualPrice(_ text: String) -> ManualPriceInput {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return .empty }
        guard let value = Decimal(string: normalized, locale: locale), value > 0 else {
            return .invalid(normalized)
        }
        return .valid(value)
    }

    private static func maximumFractionDigits(for absoluteValue: Double) -> Int {
        if absoluteValue >= 1000 { return 0 }
        if absoluteValue >= 1 { return 4 }
        if absoluteValue >= 0.0001 { return 6 }
        return 8
    }
}

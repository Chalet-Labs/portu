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
    @State private var isExpanded: Bool

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
        _isExpanded = State(initialValue: row.override != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tier 1: Identity <---> Value / Amount + Pricing Source + Expand
            HStack(alignment: .center, spacing: 10) {
                tokenIdentity

                Spacer(minLength: 12)

                valueSummary

                pricingBadge

                expandButton
            }

            // Tier 2: Category Selector <---> Visibility Toggles
            HStack(alignment: .center, spacing: 12) {
                categoryPicker

                Spacer(minLength: 12)

                visibilityToggles
            }

            // Tier 3: Expandable Overrides Drawer
            if isExpanded {
                SettingsDivider()
                expandedOverrideForm
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.panelCornerRadius, style: .continuous)
                .fill(SettingsDesign.subtleCardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.panelCornerRadius, style: .continuous)
                .stroke(isExpanded ? SettingsDesign.accentPrimary.opacity(0.40) : SettingsDesign.cardStroke, lineWidth: 1))
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

            VStack(alignment: .leading, spacing: 2) {
                Text(row.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SettingsDesign.primaryText)
                    .lineLimit(1)
                Text(row.name)
                    .font(.caption2)
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var valueSummary: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(TokenSettingsFormat.currency(row.value, currency: row.currency))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SettingsDesign.primaryText)
                .lineLimit(1)
            Text(TokenSettingsFormat.decimal(row.amount))
                .font(.caption2)
                .foregroundStyle(SettingsDesign.secondaryText)
                .lineLimit(1)
        }
    }

    private var pricingBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(row.pricingSource.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(sourceColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(sourceColor.opacity(0.15)))

            if let coinGeckoId = row.coinGeckoId {
                Text(coinGeckoId)
                    .font(.system(size: 9))
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 80, alignment: .trailing)
    }

    private var visibilityToggles: some View {
        HStack(spacing: 10) {
            Toggle("Ignore", isOn: Binding(
                get: { row.override?.isIgnored ?? false },
                set: { setIgnored(row.assetId, $0) }))
                .settingsSwitchToggle()
                .help("Hide this token from dashboard exposure and totals")

            Toggle("Always show", isOn: Binding(
                get: { row.override?.alwaysShow ?? false },
                set: { setAlwaysShow(row.assetId, $0) }))
                .settingsSwitchToggle()
                .help("Always show this token regardless of minimum value thresholds")
        }
    }

    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                if row.override != nil {
                    Circle()
                        .fill(SettingsDesign.accentPrimary)
                        .frame(width: 6, height: 6)
                }
                Image(systemName: isExpanded ? "chevron.up" : "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(isExpanded ? SettingsDesign.accentPrimary : SettingsDesign.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .fill(isExpanded ? SettingsDesign.sidebarSelection : SettingsDesign.cardBackground))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse override options" : "Expand override options")
    }

    private var expandedOverrideForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Manual Price ($ USD)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SettingsDesign.secondaryText)
                    TextField("0.00", text: $manualPriceText)
                        .textFieldStyle(.plain)
                        .settingsInputFrame(height: 30)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 3) {
                    Text("CoinGecko ID Override")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SettingsDesign.secondaryText)
                    TextField("e.g. ethereum", text: $coinGeckoIdText)
                        .textFieldStyle(.plain)
                        .settingsInputFrame(height: 30)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Notes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SettingsDesign.secondaryText)
                    TextField("Optional notes...", text: $notes)
                        .textFieldStyle(.plain)
                        .settingsInputFrame(height: 30)
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Spacer()

                if row.override != nil {
                    Button("Reset Overrides") {
                        if resetOverride(row.assetId) {
                            manualPriceText = ""
                            coinGeckoIdText = ""
                            notes = ""
                        }
                    }
                    .buttonStyle(.plain)
                    .settingsSecondaryButton(isDisabled: false)
                    .help("Reset all custom overrides for this token")
                }

                Button("Save Override") {
                    saveOverride(row.assetId, manualPriceText, coinGeckoIdText, notes)
                }
                .buttonStyle(.plain)
                .settingsPrimaryButton(isDisabled: false)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var categoryPicker: some View {
        if categories.isEmpty {
            Text(row.portfolioCategory.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SettingsDesign.secondaryText)
                .lineLimit(1)
        } else {
            HStack(spacing: 6) {
                Text("Category:")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettingsDesign.secondaryText)

                Picker("Category", selection: Binding(
                    get: { row.portfolioCategory.id },
                    set: { assignCategory(row.symbol, $0) })) {
                        ForEach(categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    .labelsHidden()
                    .font(.caption)
                    .frame(width: 130)
            }
        }
    }

    private var sourceColor: Color {
        switch row.pricingSource {
        case .live: SettingsDesign.successBadgeText
        case .syncTime: SettingsDesign.accentPrimary
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
        .frame(width: 28, height: 28)
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
        if case let .valid(value) = self {
            return value
        }
        return nil
    }
}

enum TokenSettingsFormat {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func currency(_ value: Decimal, currency: FiatCurrency = .default) -> String {
        "\(currency.symbol) \(number(value))"
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
        if normalized.isEmpty {
            return .empty
        }
        guard let value = Decimal(string: normalized, locale: locale), value > 0 else {
            return .invalid(normalized)
        }
        return .valid(value)
    }

    private static func maximumFractionDigits(for absoluteValue: Double) -> Int {
        if absoluteValue >= 1000 {
            return 0
        }
        if absoluteValue >= 1 {
            return 4
        }
        if absoluteValue >= 0.0001 {
            return 6
        }
        return 8
    }
}

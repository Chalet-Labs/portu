import OSLog
import PortuCore
import SwiftData
import SwiftUI

private let tokenSettingsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app",
    category: "TokenSettings")

struct TokenSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var positionTokens: [PositionToken]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: [SortDescriptor(\CategorySymbolRule.normalizedSymbol)])
    private var categoryRules: [CategorySymbolRule]
    @Query(sort: [SortDescriptor(\TokenPricingOverride.updatedAt, order: .reverse)])
    private var overrides: [TokenPricingOverride]

    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true

    @State private var searchText = ""
    @State private var selectedFilter: TokenSettingsFilter = .all
    @State private var saveError: String?

    var body: some View {
        let result = makeResult()

        SettingsPage(tab: .tokens, badge: .autoSave) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(
                    title: "Dashboard Visibility",
                    subtitle: "Set the global minimum value used by exposure, assets, and overview panels.") {
                        dashboardControls
                    }

                SettingsSectionCard(
                    title: "Token Overrides",
                    subtitle: "Search active tokens and save manual pricing, visibility, or category rules.") {
                        VStack(alignment: .leading, spacing: 14) {
                            filterControls(result: result)
                            tokenTable(result: result)
                        }
                    }

                SettingsInfoCard(
                    title: "Dashboard defaults",
                    message: """
                    Portu hides unpriced and sub-threshold tokens from heavy dashboard views unless a token is \
                    set to always show. Category changes apply to the symbol everywhere.
                    """)
            }
        }
        .alert("Could Not Save Token Setting", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var settings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    private var tokenEntries: [TokenEntry] {
        TokenEntry.fromActiveTokens(positionTokens, categoryResolver: categoryResolver)
    }

    private var overrideSnapshots: [TokenPricingOverrideSnapshot] {
        overrides.map(TokenPricingOverrideSnapshot.init)
    }

    private var categoryResolver: PortfolioCategoryResolver {
        PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules)
    }

    private func makeResult() -> TokenSettingsResult {
        TokenSettingsFeature.rows(
            tokens: tokenEntries,
            prices: appState.prices,
            overrides: overrideSnapshots,
            settings: settings,
            filter: selectedFilter,
            searchText: searchText,
            limit: TokenSettingsFeature.displayLimit)
    }

    private var dashboardControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Minimum value")
                        .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                        .foregroundStyle(SettingsDesign.primaryText)
                    Text("$ \(TokenSettingsFormat.number(Decimal(minimumDashboardValue)))")
                        .font(.footnote)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }
                .frame(width: 160, alignment: .leading)

                TextField(
                    "Minimum value",
                    value: $minimumDashboardValue,
                    format: .number.precision(.fractionLength(0 ... 4)))
                    .textFieldStyle(.plain)
                    .settingsInputFrame(height: SettingsMetrics.compactInputHeight)

                Stepper("", value: $minimumDashboardValue, in: 0 ... 10000, step: 1)
                    .labelsHidden()
                    .frame(width: 70)
            }

            HStack(spacing: 24) {
                Toggle("Hide unpriced", isOn: $hideUnpriced)
                    .settingsSwitchToggle()
                Toggle(TokenDashboardSettings.hideDustTitle, isOn: $hideDust)
                    .settingsSwitchToggle()
            }
        }
    }

    private func filterControls(result: TokenSettingsResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SettingsDesign.secondaryText)
                    TextField("Search tokens", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(SettingsDesign.primaryText)
                }
                .settingsInputFrame(height: SettingsMetrics.compactInputHeight)

                Picker("Filter", selection: $selectedFilter) {
                    ForEach(TokenSettingsFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            TokenSettingsCountsBar(counts: result.counts)
        }
    }

    @ViewBuilder
    private func tokenTable(result: TokenSettingsResult) -> some View {
        if result.rows.isEmpty {
            SettingsInlineNotice(
                title: "No matching tokens",
                message: nil,
                style: .action)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                TokenSettingsTableHeader()

                LazyVStack(spacing: 8) {
                    ForEach(result.rows) { row in
                        TokenSettingsRowView(
                            row: row,
                            categories: portfolioCategories,
                            saveOverride: saveOverride,
                            assignCategory: assignCategory,
                            setIgnored: setIgnored,
                            setAlwaysShow: setAlwaysShow,
                            resetOverride: resetOverride)
                            .id(row.assetId)
                    }
                }

                if result.totalMatches > result.rows.count {
                    Text("Showing \(result.rows.count) of \(result.totalMatches)")
                        .font(.footnote)
                        .foregroundStyle(SettingsDesign.secondaryText)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func saveOverride(
        assetId: UUID,
        manualPriceText: String,
        coinGeckoIdText: String,
        notes: String) {
        let parsed = TokenSettingsFormat.parseManualPrice(manualPriceText)
        if case let .invalid(raw) = parsed {
            saveError = "Could not parse '\(raw)' as a positive price."
            return
        }
        upsertOverride(assetId: assetId) { override in
            override.manualPriceUSD = parsed.value
            override.coinGeckoIdOverride = normalizedOptional(coinGeckoIdText)
            override.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func setIgnored(assetId: UUID, isIgnored: Bool) {
        upsertOverride(assetId: assetId) { override in
            override.isIgnored = isIgnored
        }
    }

    private func setAlwaysShow(assetId: UUID, alwaysShow: Bool) {
        upsertOverride(assetId: assetId) { override in
            override.alwaysShow = alwaysShow
        }
    }

    private func assignCategory(symbol: String, categoryId: UUID) {
        guard let category = portfolioCategories.first(where: { $0.id == categoryId }) else { return }
        do {
            try CategorySymbolRuleWriter.assign(
                symbol: symbol,
                to: category,
                existingRules: categoryRules,
                in: modelContext)
        } catch {
            tokenSettingsLogger.error("Failed to assign category for \(symbol, privacy: .public): \(String(describing: error), privacy: .public)")
            saveError = error.localizedDescription
        }
    }

    private func resetOverride(assetId: UUID) -> Bool {
        do {
            try TokenPricingOverrideWriter.remove(
                assetId: assetId,
                overrides: overrides,
                in: modelContext)
            return true
        } catch {
            tokenSettingsLogger.error("Failed to reset override for \(assetId, privacy: .public): \(String(describing: error), privacy: .public)")
            saveError = error.localizedDescription
            return false
        }
    }

    private func upsertOverride(
        assetId: UUID,
        update: (TokenPricingOverride) -> Void) {
        do {
            try TokenPricingOverrideWriter.upsert(
                assetId: assetId,
                overrides: overrides,
                in: modelContext,
                update: update)
        } catch {
            tokenSettingsLogger.error("Failed to save override for \(assetId, privacy: .public): \(String(describing: error), privacy: .public)")
            saveError = error.localizedDescription
        }
    }

    private func normalizedOptional(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

private struct TokenSettingsCountsBar: View {
    let counts: TokenSettingsCounts

    var body: some View {
        HStack(spacing: 8) {
            count("All", counts.all)
            count("Unpriced", counts.unpriced)
            count("Dust", counts.belowThreshold)
            count("Ignored", counts.ignored)
            count("Manual", counts.manualPrice)
            count("Mapped", counts.mappedPriceSource)
        }
    }

    private func count(_ title: String, _ value: Int) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Text("\(value)")
                .fontWeight(.bold)
        }
        .font(.caption)
        .foregroundStyle(SettingsDesign.secondaryText)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            Capsule()
                .fill(SettingsDesign.subtleCardBackground))
        .overlay(
            Capsule()
                .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }
}

private struct TokenSettingsTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            header("Token", width: 170)
            header("Value", width: 104)
            header("Pricing", width: 118)
            header("Overrides", width: nil)
        }
        .padding(.horizontal, 14)
    }

    private func header(_ title: String, width: CGFloat?) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(SettingsDesign.secondaryText)
            .frame(width: width, alignment: .leading)
    }
}

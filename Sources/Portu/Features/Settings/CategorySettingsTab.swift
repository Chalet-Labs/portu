import OSLog
import PortuCore
import SwiftData
import SwiftUI

private let categorySettingsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app",
    category: "CategorySettings")

struct CategorySettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var categories: [PortfolioCategory]
    @Query(sort: [SortDescriptor(\CategorySymbolRule.normalizedSymbol)])
    private var rules: [CategorySymbolRule]

    @State private var newCategoryName = ""
    @State private var saveError: String?

    var body: some View {
        SettingsPage(tab: .categories, badge: .autoSave) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(
                    title: "Category Rules",
                    subtitle: "Assign token symbols to the categories used across Portu.",
                    icon: .categoryRules) {
                        VStack(alignment: .leading, spacing: 14) {
                            if categories.isEmpty {
                                SettingsInlineNotice(
                                    title: "Default categories will be created automatically.",
                                    message: nil,
                                    style: .action)
                            } else {
                                ForEach(categories) { category in
                                    CategoryRuleEditor(
                                        category: category,
                                        categories: categories,
                                        rules: rules,
                                        onSaveError: { saveError = $0 })
                                }
                            }
                        }
                    }

                SettingsSectionCard(
                    title: "Create Category",
                    subtitle: "New categories are available immediately in dashboards and charts.",
                    icon: .createCategory) {
                        HStack(spacing: 12) {
                            TextField("Category name", text: $newCategoryName)
                                .textFieldStyle(.plain)
                                .settingsInputFrame(height: SettingsMetrics.compactInputHeight)

                            Button("Add") {
                                addCategory()
                            }
                            .buttonStyle(.plain)
                            .settingsPrimaryButton(isDisabled: normalizedNewCategoryName.isEmpty)
                            .disabled(normalizedNewCategoryName.isEmpty)
                        }
                    }

                SettingsInfoCard(
                    title: "Global symbol rules",
                    message: "A symbol belongs to one category everywhere. Adding an existing symbol moves it to the selected category.")
            }
        }
        .alert("Could Not Save Category Change", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var normalizedNewCategoryName: String {
        newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addCategory() {
        let name = normalizedNewCategoryName
        guard !name.isEmpty else { return }
        let nextOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
        let inserted = PortfolioCategory(
            name: name,
            sortOrder: nextOrder,
            semanticRole: .normal,
            isSystemRequired: false)
        modelContext.insert(inserted)
        do {
            try modelContext.save()
            newCategoryName = ""
        } catch {
            modelContext.delete(inserted)
            categorySettingsLogger.error("Failed to add category: \(String(describing: error), privacy: .public)")
            saveError = error.localizedDescription
        }
    }
}

private struct CategoryRuleEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var category: PortfolioCategory

    let categories: [PortfolioCategory]
    let rules: [CategorySymbolRule]
    let onSaveError: (String) -> Void

    @State private var newSymbol = ""
    @State private var categoryNameDraft = ""
    @FocusState private var isCategoryNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Category", text: $categoryNameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                        .foregroundStyle(SettingsDesign.primaryText)
                        .focused($isCategoryNameFocused)
                        .onSubmit(saveCategoryName)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    Button {
                        moveCategory(offset: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .settingsIconButton(color: SettingsDesign.accentBlue)
                    .accessibilityLabel("Move \(category.name) up")
                    .disabled(previousCategory == nil)

                    Button {
                        moveCategory(offset: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .settingsIconButton(color: SettingsDesign.accentBlue)
                    .accessibilityLabel("Move \(category.name) down")
                    .disabled(nextCategory == nil)

                    Button {
                        deleteCategory()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .settingsIconButton(color: SettingsDesign.warningOrange)
                    .accessibilityLabel("Delete \(category.name)")
                    .disabled(category.isSystemRequired)
                }
            }

            HStack(spacing: 10) {
                TextField("Add symbol", text: $newSymbol)
                    .textFieldStyle(.plain)
                    .settingsInputFrame(height: 34)

                Button("Add Symbol") {
                    addSymbol()
                }
                .buttonStyle(.plain)
                .settingsPrimaryButton(isDisabled: normalizedSymbol.isEmpty)
                .disabled(normalizedSymbol.isEmpty)
            }

            if categoryRules.isEmpty {
                Text("No symbols assigned")
                    .font(.footnote)
                    .foregroundStyle(SettingsDesign.secondaryText)
            } else {
                FlexibleSymbolGrid(rules: categoryRules) { rule in
                    remove(rule)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.panelCornerRadius, style: .continuous)
                .fill(SettingsDesign.subtleCardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.panelCornerRadius, style: .continuous)
                .stroke(SettingsDesign.cardStroke, lineWidth: 1))
        .onAppear {
            categoryNameDraft = category.name
        }
        .onChange(of: category.name) { _, name in
            if !isCategoryNameFocused {
                categoryNameDraft = name
            }
        }
        .onChange(of: isCategoryNameFocused) { _, isFocused in
            if !isFocused {
                saveCategoryName()
            }
        }
    }

    private var subtitle: String {
        switch category.semanticRole {
        case .normal: "Custom portfolio category"
        case .stablecoin: "Stablecoin category for portfolio health and net exposure"
        case .fiat: "Fiat currency category"
        case .fallback: "Fallback for unmatched symbols"
        }
    }

    private var categoryRules: [CategorySymbolRule] {
        rules
            .filter { $0.category?.id == category.id }
            .sorted { $0.normalizedSymbol.localizedStandardCompare($1.normalizedSymbol) == .orderedAscending }
    }

    private var normalizedSymbol: String {
        PortfolioCategoryDefaults.normalizeSymbol(newSymbol)
    }

    private var categoryIndex: Int? {
        categories.firstIndex { $0.id == category.id }
    }

    private var previousCategory: PortfolioCategory? {
        guard let index = categoryIndex, index > 0 else { return nil }
        return categories[index - 1]
    }

    private var nextCategory: PortfolioCategory? {
        guard let index = categoryIndex, index < categories.count - 1 else { return nil }
        return categories[index + 1]
    }

    private var fallbackCategory: PortfolioCategory? {
        categories.first { $0.semanticRole == .fallback }
            ?? categories.first { $0.id == PortfolioCategoryDefaults.fallbackCategoryID }
    }

    private func saveCategoryName() {
        do {
            try PortfolioCategoryWriter.rename(category, to: categoryNameDraft, in: modelContext)
            categoryNameDraft = category.name
        } catch {
            categoryNameDraft = category.name
            categorySettingsLogger.error("Failed to rename category: \(String(describing: error), privacy: .public)")
            onSaveError(error.localizedDescription)
        }
    }

    private func addSymbol() {
        let symbol = normalizedSymbol
        guard !symbol.isEmpty else { return }

        do {
            try CategorySymbolRuleWriter.assign(
                symbol: symbol,
                to: category,
                existingRules: rules,
                in: modelContext)
            newSymbol = ""
        } catch {
            categorySettingsLogger.error("Failed to add symbol \(symbol, privacy: .public): \(String(describing: error), privacy: .public)")
            onSaveError(error.localizedDescription)
        }
    }

    private func remove(_ rule: CategorySymbolRule) {
        do {
            try CategorySymbolRuleWriter.remove(rule, in: modelContext)
        } catch {
            categorySettingsLogger.error("Failed to remove symbol rule: \(String(describing: error), privacy: .public)")
            onSaveError(error.localizedDescription)
        }
    }

    private func moveCategory(offset: Int) {
        guard let index = categoryIndex else { return }
        let targetIndex = index + offset
        guard categories.indices.contains(targetIndex) else { return }
        let target = categories[targetIndex]
        let originalSelfOrder = category.sortOrder
        let originalTargetOrder = target.sortOrder
        category.sortOrder = originalTargetOrder
        target.sortOrder = originalSelfOrder
        do {
            try modelContext.save()
        } catch {
            category.sortOrder = originalSelfOrder
            target.sortOrder = originalTargetOrder
            categorySettingsLogger.error("Failed to reorder category: \(String(describing: error), privacy: .public)")
            onSaveError(error.localizedDescription)
        }
    }

    private func deleteCategory() {
        do {
            try PortfolioCategoryWriter.delete(
                category,
                fallbackCategory: fallbackCategory,
                rules: categoryRules,
                in: modelContext)
        } catch {
            categorySettingsLogger.error("Failed to delete category: \(String(describing: error), privacy: .public)")
            onSaveError(error.localizedDescription)
        }
    }
}

private struct FlexibleSymbolGrid: View {
    let rules: [CategorySymbolRule]
    let remove: (CategorySymbolRule) -> Void

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(rules, id: \.id) { rule in
                HStack(spacing: 6) {
                    Text(rule.normalizedSymbol)
                        .font(.caption.weight(.bold))
                    Button {
                        remove(rule)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SettingsDesign.secondaryText)
                }
                .foregroundStyle(SettingsDesign.primaryText)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    Capsule()
                        .fill(SettingsDesign.subtleCardBackground))
                .overlay(
                    Capsule()
                        .stroke(SettingsDesign.cardStroke, lineWidth: 1))
            }
        }
    }
}

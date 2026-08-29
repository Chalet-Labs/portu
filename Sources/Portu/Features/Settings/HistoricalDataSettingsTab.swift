import ComposableArchitecture
import SwiftUI

struct HistoricalDataSettingsTab: View {
    let store: StoreOf<AppFeature>

    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    var body: some View {
        SettingsPage(tab: .historicalData) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(
                    title: HistoricalPriceBackfillSettings.sectionTitle,
                    subtitle: "Cache daily prices from CoinGecko and Zerion separately from Portu snapshots.",
                    icon: .priceUpdates) {
                        VStack(alignment: .leading, spacing: 14) {
                            SettingsSwitchRow(
                                title: HistoricalPriceBackfillSettings.useBackfillTitle,
                                subtitle: "Use cached daily prices to extend charts before the first local snapshot.",
                                isOn: $historicalBackfillEnabled)

                            HStack(spacing: 10) {
                                Button {
                                    store.send(.historicalPriceBackfill(.backfillButtonTapped))
                                } label: {
                                    Label(HistoricalPriceBackfillSettings.backfillButtonTitle, systemImage: "arrow.down.circle")
                                }
                                .buttonStyle(.plain)
                                .settingsPrimaryButton(isDisabled: store.historicalPriceBackfill.status.isRunning)
                                .disabled(store.historicalPriceBackfill.status.isRunning)

                                Button {
                                    store.send(.historicalPriceBackfill(.clearCacheButtonTapped))
                                } label: {
                                    Label(HistoricalPriceBackfillSettings.clearCacheButtonTitle, systemImage: "trash")
                                }
                                .buttonStyle(.plain)
                                .settingsSecondaryButton(isDisabled: store.historicalPriceBackfill.status.isRunning)
                                .disabled(store.historicalPriceBackfill.status.isRunning)

                                Spacer(minLength: 0)
                            }

                            HistoricalBackfillStatusText(status: store.historicalPriceBackfill.status)
                        }
                    }
            }
        }
    }
}

struct HistoricalBackfillStatusText: View {
    let status: HistoricalBackfillStatus

    var body: some View {
        HistoricalBackfillStatusRow(status: status)
    }
}

enum HistoricalBackfillStatusFormatter {
    static func message(for status: HistoricalBackfillStatus) -> String {
        switch status {
        case .idle:
            "No historical backfill run in this session."
        case .running:
            "Fetching historical prices from CoinGecko and Zerion..."
        case .clearing:
            "Clearing historical price cache..."
        case let .succeeded(result):
            successMessage(for: result)
        case let .failed(message):
            "Backfill failed: \(message)"
        }
    }

    private static func successMessage(for result: HistoricalBackfillResult) -> String {
        if result.requestedAssets == 0 {
            return "No eligible assets found for historical backfill. Skipped \(result.skippedAssets) "
                + "local snapshot assets because they do not have CoinGecko IDs, onchain addresses, or pricing overrides."
        }

        let baseMessage = "Fetched \(result.fetchedAssets) assets, inserted \(result.insertedPoints), "
            + "updated \(result.updatedPoints), skipped \(result.skippedAssets)."
        guard !result.failedCoinGeckoIDs.isEmpty else { return baseMessage }

        if result.fetchedAssets == 0, result.insertedPoints == 0, result.updatedPoints == 0 {
            return "No prices fetched; failed \(result.failedCoinGeckoIDs.count) assets. Check provider access."
        }

        if result.failedCoinGeckoIDs.count == 1, let id = result.failedCoinGeckoIDs.first {
            return baseMessage + " Partial success: failed 1 asset (\(displayIdentifier(id)))."
        }

        return baseMessage
            + " Partial success: failed \(result.failedCoinGeckoIDs.count) assets. Check provider access."
    }

    private static func displayIdentifier(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 24 else { return trimmed }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 3 {
            let head = parts.dropLast().joined(separator: ":")
            let tail = String(parts.last ?? "")
            return "\(head):\(tail.prefix(6))...\(tail.suffix(4))"
        }
        return "\(trimmed.prefix(12))...\(trimmed.suffix(8))"
    }
}

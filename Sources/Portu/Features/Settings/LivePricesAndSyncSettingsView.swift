import ComposableArchitecture
import SwiftUI

struct LivePricesAndSyncSettingsView: View {
    let store: StoreOf<AppFeature>

    @AppStorage(PricePollingSettings.refreshIntervalKey)
    private var refreshInterval = PricePollingSettings.defaultRefreshIntervalSeconds
    @AppStorage(ProviderIntervalSettings.onchainLivePriceIntervalKey)
    private var onchainLivePriceInterval = ProviderIntervalSettings.defaultOnchainLivePriceIntervalSeconds
    @AppStorage(ProviderIntervalSettings.onchainPortfolioSyncIntervalKey)
    private var onchainPortfolioSyncInterval = ProviderIntervalSettings.defaultOnchainPortfolioSyncIntervalSeconds
    @AppStorage(ProviderIntervalSettings.exchangePortfolioSyncIntervalKey)
    private var exchangePortfolioSyncInterval = ProviderIntervalSettings.defaultExchangePortfolioSyncIntervalSeconds

    init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    var body: some View {
        SettingsPage(tab: .livePricesAndSync) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(
                    title: "Live Prices",
                    subtitle: "Choose automatic refresh intervals by price provider.",
                    icon: .priceUpdates) {
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsIntervalRow(
                                title: "CoinGecko live prices",
                                subtitle: "Default: 30 seconds. Longer intervals intentionally keep dashboard prices stale between refreshes.",
                                selection: $refreshInterval,
                                fallbackSeconds: PricePollingSettings.defaultRefreshIntervalSeconds,
                                options: .coinGeckoLivePrices)

                            SettingsIntervalRow(
                                title: "Zerion live price fallback",
                                subtitle: "Default: 1 hour. Used only for onchain tokens CoinGecko cannot price.",
                                selection: $onchainLivePriceInterval,
                                fallbackSeconds: ProviderIntervalSettings.defaultOnchainLivePriceIntervalSeconds,
                                options: .onchainLivePriceFallback)
                        }
                    }

                SettingsSectionCard(
                    title: "Portfolio Sync",
                    subtitle: "Control automatic portfolio sync calls by provider.",
                    icon: .priceUpdates) {
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsIntervalRow(
                                title: "Zerion portfolio sync",
                                subtitle: "Default: 6 hours. Manual only disables scheduled Zerion portfolio refreshes.",
                                selection: $onchainPortfolioSyncInterval,
                                fallbackSeconds: ProviderIntervalSettings.defaultOnchainPortfolioSyncIntervalSeconds,
                                options: .onchainPortfolioSync)

                            SettingsIntervalRow(
                                title: "Exchange portfolio sync",
                                subtitle: "Default: 1 hour. Manual only disables scheduled exchange portfolio refreshes.",
                                selection: $exchangePortfolioSyncInterval,
                                fallbackSeconds: ProviderIntervalSettings.defaultExchangePortfolioSyncIntervalSeconds,
                                options: .exchangePortfolioSync)
                        }
                    }
            }
        }
    }
}

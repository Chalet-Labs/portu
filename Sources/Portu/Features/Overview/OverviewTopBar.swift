// Sources/Portu/Features/Overview/OverviewTopBar.swift
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewTopBar: View {
    @Environment(AppState.self) private var appState
    @Query private var positions: [Position]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @Query private var tokenIdentityMappings: [TokenIdentityMapping]

    /// Only positions from active accounts
    private var activePositions: [Position] {
        positions.filter { $0.account?.isActive == true }
    }

    private var totalValue: Decimal {
        activePositions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
    }

    private var overrideMap: [UUID: TokenPricingOverrideSnapshot] {
        TokenSettingsFeature.overridesByAssetId(tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init))
    }

    private var mappingMap: [OnchainTokenIdentity: TokenIdentityMappingSnapshot] {
        TokenIdentityMappingFeature.mappingsByIdentity(tokenIdentityMappings.map(TokenIdentityMappingSnapshot.init))
    }

    private var change24h: Decimal {
        // Sum: token.amount * priceChange24h for each token, sign-adjusted by role
        var total: Decimal = 0
        for pos in activePositions {
            for token in pos.tokens {
                guard
                    let asset = token.asset,
                    let priceID = priceID(asset: asset, token: token),
                    let price = appState.prices[priceID],
                    let changePct = appState.priceChanges24h[priceID]
                else { continue }

                let contribution = token.amount * price * changePct
                if token.role.isPositive {
                    total += contribution
                } else if token.role.isBorrow {
                    total -= contribution
                }
                // reward: excluded
            }
        }
        return total
    }

    private func priceID(asset: Asset, token: PositionToken) -> String? {
        let identity = OnchainTokenIdentity(chain: asset.upsertChain, contractAddress: asset.upsertContract)
        let coinGeckoId = OverviewWatchlistStore.normalizedID(asset.coinGeckoId)
            ?? TokenIdentityMappingFeature.mappedCoinGeckoID(
                for: identity,
                mappingsByIdentity: mappingMap)
        let entry = TokenEntry(
            assetId: asset.id,
            symbol: asset.symbol,
            name: asset.name,
            category: asset.category,
            coinGeckoId: coinGeckoId,
            onchainIdentity: identity,
            role: token.role,
            amount: token.amount,
            usdValue: token.usdValue,
            logoURL: asset.logoURL)
        return TokenSettingsFeature.resolvedPriceID(
            token: entry,
            override: overrideMap[asset.id])
    }

    private var changePct: Decimal {
        let prev = totalValue - change24h
        guard prev != 0 else { return 0 }
        return change24h / prev
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(totalValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(DashboardStyle.heroValueFont)
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text(change24h, format: .currency(code: "USD"))
                        .lineLimit(1)
                    Spacer()
                    Text("$ change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(PortuTheme.changeColor(for: change24h))

                HStack(spacing: 4) {
                    Image(systemName: changePct >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption2)
                    Text(changePct, format: .percent.precision(.fractionLength(2)))
                        .lineLimit(1)
                    Spacer()
                    Text("% change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(PortuTheme.changeColor(for: changePct))
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
}

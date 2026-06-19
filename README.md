![Portu banner](docs/assets/portu-readme-banner.svg)

# Portu

Portu is a native macOS crypto portfolio dashboard for tracking wallets, exchanges, and manual holdings from one local app.

[Download latest release](https://github.com/Chalet-Labs/portu/releases/latest) | [All releases](https://github.com/Chalet-Labs/portu/releases) | [Report an issue](https://github.com/Chalet-Labs/portu/issues)

Portu is local-first. Portfolio data stays on your Mac, provider credentials are stored in Keychain, and the app has no backend and no telemetry.

## Features

- Unified overview with total portfolio value, 24h movement, allocation breakdowns, top assets, and a price watchlist.
- Wallet and DeFi position sync through Zapper.
- Exchange accounts for Kraken, Coinbase, and Binance.
- Manual accounts for assets or positions that are not available from a provider.
- Exposure, performance, all-assets, all-positions, account, and asset-detail views.
- Live and historical pricing through CoinGecko, with Zapper fallback for onchain tokens that CoinGecko cannot price.
- Historical price backfill for local performance charts.
- Token settings for CoinGecko ID overrides, pricing overrides, hidden dust, and unpriced assets.
- Custom RPC settings and configurable provider sync intervals.

## Downloads

The easiest way to try Portu is from GitHub Releases:

- [Latest release](https://github.com/Chalet-Labs/portu/releases/latest)
- [All releases](https://github.com/Chalet-Labs/portu/releases)

Release builds publish a `Portu-<version>.dmg` plus a SHA-256 checksum. The release workflow is driven by semantic-release from the `master` and `alpha` branches.

## API Keys

Users currently need a Zapper API key for wallet and DeFi sync. Create one at [build.zapper.xyz](https://build.zapper.xyz/), then add it in Portu under `Settings > API Keys > Zapper`.

Optional credentials:

- CoinGecko API key: raises price API rate limits.
- Exchange API keys: required only for Kraken, Coinbase, or Binance exchange accounts.

Use read-only exchange API credentials where the exchange supports them. Portu stores provider secrets locally in macOS Keychain.

## Getting Started

1. Download the latest DMG from [Releases](https://github.com/Chalet-Labs/portu/releases/latest).
2. Open Portu and go to `Settings > API Keys`.
3. Add your Zapper API key from [build.zapper.xyz](https://build.zapper.xyz/).
4. Add a wallet, exchange, or manual account from the Accounts view.
5. Sync the account and use Overview, Exposure, Performance, All Assets, and All Positions to inspect the portfolio.

## Build From Source

Requirements:

- macOS 15 or newer
- Xcode with Swift 6.2 support
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [just](https://github.com/casey/just)

Common commands:

```bash
just generate
just build
just test-packages
just test
```

For a full local build, launch, and process verification:

```bash
./script/build_and_run.sh --verify
```

## Architecture

Portu is generated from `project.yml` and split into three SwiftPM packages:

- `PortuCore`: models, DTOs, Keychain access, local storage protocols, and shared domain types.
- `PortuNetwork`: Zapper, CoinGecko, Kraken, Coinbase, and Binance provider clients.
- `PortuUI`: shared SwiftUI theme and reusable UI components.

The macOS app target in `Sources/Portu` owns app state, feature views, settings, and sync orchestration.

# Token Identity Mapping Design

## Summary

Portu should use an onchain token identity as the canonical key for provider price data: `(chain, contractAddress)`. CoinGecko IDs and Zapper IDs are optional provider enrichments cached under that key. The app should query providers directly by `(chain, address)` whenever the provider supports it, and save provider-specific IDs only when they unlock better or required endpoints.

This separates three concerns that are currently mixed together:

- Local token identity: chain plus normalized address.
- Provider cache: CoinGecko or Zapper IDs discovered for that identity.
- User intent: manual prices, ignored tokens, always-show, and user-entered CoinGecko overrides.

## Goals

- Make `(chain, contractAddress)` the stable key for Zapper-originated onchain assets.
- Cache CoinGecko IDs and Zapper IDs only as provider lookup accelerators, not as the primary identity.
- Keep manual token pricing and visibility settings separate from automatic provider mapping.
- Use CoinGecko by ID when a mapped ID exists because current price, 24h change, and market chart endpoints are better supported by CoinGecko coin IDs.
- Use Zapper current and historical price APIs directly by chain ID and token address for assets that cannot be mapped to CoinGecko.
- Make Overview, Performance, Exposure, and Asset Detail able to show prices for dashboard-eligible onchain assets even when no CoinGecko ID is present.
- Avoid wasting provider calls on ignored, dust, hidden, or otherwise dashboard-ineligible tokens.

## Non-Goals

- Do not infer mappings from symbol or token name automatically.
- Do not make provider mapping a manual override.
- Do not delete or rewrite existing synced `Asset` records just because a mapping changes.
- Do not require a Zapper ID if the Zapper price endpoint works with chain ID and token address.
- Do not replace local portfolio snapshots as the source of truth for holdings.

## Provider Capabilities

CoinGecko:

- The onchain token endpoint can query multiple token addresses for one network and may return `coingecko_coin_id`.
- The network list endpoint provides CoinGecko onchain network IDs used by those address endpoints.
- Once a `coingecko_coin_id` is known, Portu can use existing CoinGecko current price and historical market chart endpoints by coin ID.

Zapper:

- `fungibleTokenV2` accepts token address and chain ID and returns token metadata, current price data, 24h change, and historical price ticks.
- `fungibleTokenBatchV2` accepts an array of address and chain ID pairs and returns batch token price data.
- Current known price use cases do not require saving a Zapper token ID, but the data model should allow one if a future endpoint requires resolving `(chain, address)` to an opaque Zapper ID.

References checked on 2026-05-14:

- [CoinGecko token data by token addresses](https://docs.coingecko.com/v3.0.1/reference/tokens-data-contract-addresses)
- [CoinGecko supported networks list](https://docs.coingecko.com/reference/networks-list)
- [Zapper token prices and charts](https://build.zapper.xyz/docs/api/endpoints/onchain-prices)

## Data Model

Add a provider-owned SwiftData model in `PortuCore`.

Suggested model: `TokenIdentityMapping`.

Fields:

- `id`
- `canonicalKey`, unique, derived from normalized `chain` and `contractAddress`
- `chain`
- `contractAddress`
- `coinGeckoId`
- `zapperId`
- `coinGeckoResolvedAt`
- `zapperResolvedAt`
- `lastCoinGeckoFailureAt`
- `lastZapperFailureAt`
- `createdAt`
- `updatedAt`

The logical identity key is `(chain, contractAddress)`. `canonicalKey` exists only because it is simpler and safer to enforce uniqueness with one stored value in SwiftData.

`TokenPricingOverride` remains separate and keeps user choices:

- manual USD price
- manual CoinGecko ID override
- ignored
- always show
- notes

Automatic provider resolution must not write to `TokenPricingOverride` unless the user explicitly edits a token in Settings.

## Resolution Order

When a feature needs a token price identity, Portu should resolve it in this order:

1. Manual price override: use the manual price and skip provider calls.
2. Manual CoinGecko override: use the user-entered CoinGecko ID.
3. Asset-native CoinGecko ID: use `Asset.coinGeckoId` when present.
4. Cached mapping CoinGecko ID: use `TokenIdentityMapping.coinGeckoId`.
5. CoinGecko onchain lookup: query by `(chain, address)`, then save returned `coingecko_coin_id`.
6. Zapper direct price lookup: query by `(chainId, address)` when no CoinGecko ID exists or CoinGecko fails.
7. Zapper ID lookup: only if a needed Zapper endpoint requires an opaque Zapper ID, resolve and cache it.

Native assets that Zapper represents with a zero address should be handled explicitly by chain. For example, Ethereum zero-address ETH can map to CoinGecko `ethereum`; Base zero-address ETH can also map to `ethereum`; xDai can map to an xDai-specific ID if verified. If a native mapping is ambiguous, fall back to Zapper rather than guessing.

## Price Data Flow

The app should build price requests from dashboard-eligible token entries, not from every synced token.

1. Read active tokens, assets, token pricing overrides, and identity mappings.
2. Apply dashboard eligibility rules first: ignored tokens, hidden dust, hidden unpriced assets, zero amounts, and manual-only rows should not trigger unnecessary provider calls.
3. Split eligible assets into:
   - CoinGecko IDs to poll by ID.
   - Onchain identities that need mapping.
   - Onchain identities that need Zapper fallback pricing.
4. Resolve missing CoinGecko IDs in batches grouped by chain.
5. Persist successful mappings under `TokenIdentityMapping`.
6. Fetch current prices and 24h changes:
   - CoinGecko by coin ID for mapped assets.
   - Zapper batch by `(chainId, address)` for unmapped assets.
7. Merge results into the app price state using stable keys that chart and row logic can resolve back to the same asset identity.

Historical backfill follows the same identity rules:

- Prefer CoinGecko historical market chart when a CoinGecko ID exists.
- Fall back to Zapper historical price ticks by `(chainId, address)` when no CoinGecko ID exists.
- Store historical rows by the effective historical price key already used by chart code: CoinGecko ID for CoinGecko data, `zapper:<chain>:<address>` for Zapper data.

## Settings UX

Token Settings should show mapping state without turning automatic mapping into a user-facing requirement.

Useful row states:

- `CoinGecko mapped`: automatic or asset-provided CoinGecko ID exists.
- `Zapper priced`: Zapper fallback is available by chain and address.
- `Manual`: user entered a manual price or CoinGecko override.
- `Unpriced`: no provider can currently price it.
- `Ignored`: user excluded it.

Settings can expose the cached provider IDs in a compact detail or debug-style field, but the main workflow remains manual price, CoinGecko override, ignore, and always show.

## Error Handling

- CoinGecko mapping failure should not block Zapper fallback.
- Zapper failure should not erase existing CoinGecko mappings.
- Provider rate limits should mark a transient failure timestamp so the same token is not retried aggressively in one session.
- Empty provider responses should be treated as unresolved, not as a destructive delete of existing mappings.
- If a provider later returns a different ID for the same `(chain, address)`, update the cache only when the new ID is non-empty and normalize it first.
- Manual overrides always win over cached automatic mappings.

## Testing

PortuCore tests:

- `TokenIdentityMapping` stores a unique canonical key for `(chain, contractAddress)`.
- Address normalization is stable and lowercase for EVM-style addresses.
- Optional provider IDs can be added, cleared, and updated without changing the canonical key.

PortuNetwork tests:

- CoinGecko onchain token response parsing extracts `coingecko_coin_id` by normalized address.
- CoinGecko network mapping covers supported `Chain` cases or explicitly skips unsupported ones.
- Zapper batch/current price parsing returns price and 24h change by `(chain, address)`.
- Zapper historical ticks continue to return rows keyed by the local `zapper:<chain>:<address>` historical key.

App feature tests:

- Manual price skips provider resolution.
- Manual CoinGecko override wins over cached mapping.
- Cached CoinGecko mapping is used before calling CoinGecko onchain lookup again.
- CoinGecko lookup success persists a mapping under `(chain, address)`.
- CoinGecko lookup failure falls back to Zapper when a Zapper API key exists.
- Dashboard eligibility filtering happens before provider resolution.
- Overview price rows can show CoinGecko-mapped and Zapper-priced tokens.
- Key Changes can display 24h changes from both CoinGecko and Zapper sources.
- Historical backfill prefers CoinGecko IDs and falls back to Zapper for unmapped onchain identities.

Render and integration tests:

- Token Settings shows mapping status for mapped, Zapper-priced, manual, ignored, and unpriced tokens.
- Overview renders non-empty key changes with a store containing only Zapper-originated assets.
- Asset Detail chart uses the CoinGecko cache when mapped and Zapper historical cache when unmapped.

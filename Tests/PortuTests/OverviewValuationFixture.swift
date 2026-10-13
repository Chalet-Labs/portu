import Foundation
@testable import Portu
import PortuCore

/// One portfolio for the Overview seam specs (T2). The specs' expected numbers are worked out by
/// hand from the values here, in USD.
///
/// | Token | Position | Role | Amount | `usdValue` | Spec value (source) |
/// |---|---|---|---|---|---|
/// | USDC | Main Wallet, idle | balance | 1000 | 1000 | 1000 (live 1) |
/// | ETH | Main Wallet, idle | balance | 2 | 5800 | 6000 (live 3000, 24h +25%) |
/// | PEPE | Main Wallet, idle | balance | 1,000,000 | 9 | 10 (live 0.00001, 24h −50%) |
/// | DAI | Main Wallet, idle | balance | 0.5 | 0.5 | 0.5 dust (live 1, 24h +25%) |
/// | MNL | Main Wallet, idle | balance | 50 | 40 | 100 (manual 2; live 7 ignored) |
/// | LINK | Main Wallet, idle | balance | 10 | 150, synced day −1 | 160 (close 16 on day 0, 24h +25%) |
/// | UNI | Main Wallet, idle | balance | 10 | 70, synced day 0 | 70 (sync; the day-0 close 8 loses) |
/// | BAD | Main Wallet, idle | balance | 100 | 5000 | 0 (onchain live 10000: ratio 200, unpriced) |
/// | TINY | Main Wallet, idle | balance | 1 | 0.3 | 0.3 dust, alwaysShow (live 0.3) |
/// | DEGEN | Degen Wallet, idle | balance | 10,000 | 95 | 100 (degen-chain token mapped to `degen-base`, live 0.01) |
/// | OTC | Degen Wallet, idle | balance | 5 | 250 | 250 (sync; no price ID) |
/// | ETH | Aave V3, lending | supply | 1 | 2900 | 3000 (24h +25%) |
/// | ETH | Aave V3, lending | borrow | 0.5 | 1450 | −1500 (24h +25%) |
/// | USDT | Aave V3, lending | borrow | 0.4 | 0.4 | −0.4 dust borrow (live 1) |
/// | SOL | Lido, staking | stake | 10 | 1400 | 1500 (live 150) |
/// | SOL | Lido, staking | reward | 1 | 150 | 0 (reward) |
/// | ARB | Arbitrum Vesting, vesting | balance | 100 | 80 | 90 (live 0.9) |
/// | SCAM | Scam Wallet, idle | balance | 1000 | 50000 | 0 (ignored; live 50) |
///
/// Gross 12,280.8, debt 1500.4, net 10,780.4, 24h change 1522.1. The watchlist adds bitcoin
/// (live 60,000, 24h +10%) and dogecoin (close 0.2 only, 24h −20%), neither held.
enum OverviewValuationFixture {
    /// 2025-10-06 00:00 UTC.
    static let today = Date(timeIntervalSince1970: 1_759_708_800)

    static func day(_ offset: Int) -> Date {
        today.addingTimeInterval(TimeInterval(offset) * 86400)
    }

    static func noon(_ offset: Int) -> Date {
        day(offset).addingTimeInterval(12 * 3600)
    }

    static func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    enum AssetID {
        static let usdc = uuid(1)
        static let eth = uuid(2)
        static let pepe = uuid(3)
        static let dai = uuid(4)
        static let manual = uuid(5)
        static let link = uuid(6)
        static let uni = uuid(7)
        static let bad = uuid(8)
        static let tiny = uuid(9)
        static let degen = uuid(10)
        static let otc = uuid(11)
        static let usdt = uuid(12)
        static let sol = uuid(13)
        static let arb = uuid(14)
        static let scam = uuid(15)
    }

    enum PositionID {
        static let wallet = uuid(101)
        static let degenWallet = uuid(102)
        static let aave = uuid(103)
        static let lido = uuid(104)
        static let vesting = uuid(105)
        static let scamWallet = uuid(106)
    }

    static let mainAccount = uuid(201)
    static let degenAccount = uuid(202)

    static let badIdentity = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xbad000000000000000000000000000000000bad1")
    static let degenIdentity = OnchainTokenIdentity(chain: .degen, contractAddress: "0xde9e000000000000000000000000000000000de9")

    static let positions: [UUID: OverviewPositionMeta] = [
        PositionID.wallet: OverviewPositionMeta(id: PositionID.wallet, title: "Main Wallet", positionType: .idle, chain: .ethereum),
        PositionID.degenWallet: OverviewPositionMeta(
            id: PositionID.degenWallet,
            title: "Degen Wallet",
            positionType: .idle,
            chain: .degen),
        PositionID.aave: OverviewPositionMeta(id: PositionID.aave, title: "Aave V3", positionType: .lending, chain: .ethereum),
        PositionID.lido: OverviewPositionMeta(id: PositionID.lido, title: "Lido", positionType: .staking, chain: .solana),
        PositionID.vesting: OverviewPositionMeta(
            id: PositionID.vesting,
            title: "Arbitrum Vesting",
            positionType: .vesting,
            chain: .arbitrum),
        PositionID.scamWallet: OverviewPositionMeta(id: PositionID.scamWallet, title: "Scam Wallet", positionType: .idle, chain: .base)
    ]

    static let inputs: [ValuationInput] = [
        input(1, .wallet, token(AssetID.usdc, "USDC", "USD Coin", .stablecoin, coinGeckoId: "usd-coin", amount: 1000, usdValue: 1000)),
        input(2, .wallet, token(AssetID.eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", amount: 2, usdValue: 5800)),
        input(3, .wallet, token(AssetID.pepe, "PEPE", "Pepe", .meme, coinGeckoId: "pepe", amount: 1_000_000, usdValue: 9)),
        input(4, .wallet, token(AssetID.dai, "DAI", "Dai", .stablecoin, coinGeckoId: "dai", amount: decimal("0.5"), usdValue: decimal("0.5"))),
        input(5, .wallet, token(AssetID.manual, "MNL", "Manual Coin", .defi, coinGeckoId: "manual-coin", amount: 50, usdValue: 40)),
        input(6, .wallet, token(
            AssetID.link, "LINK", "Chainlink", .defi, coinGeckoId: "chainlink", amount: 10, usdValue: 150, syncedAt: noon(-1))),
        input(7, .wallet, token(AssetID.uni, "UNI", "Uniswap", .defi, coinGeckoId: "uniswap", amount: 10, usdValue: 70)),
        input(8, .wallet, token(AssetID.bad, "BAD", "Bad Price", .other, onchainIdentity: badIdentity, amount: 100, usdValue: 5000)),
        input(9, .wallet, token(AssetID.tiny, "TINY", "Tiny", .other, coinGeckoId: "tiny-coin", amount: 1, usdValue: decimal("0.3"))),
        input(10, .degenWallet, token(AssetID.degen, "DEGEN", "Degen", .meme, onchainIdentity: degenIdentity, amount: 10000, usdValue: 95)),
        input(11, .degenWallet, token(AssetID.otc, "OTC", "Desk Token", .other, amount: 5, usdValue: 250)),
        input(12, .aave, token(AssetID.eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", role: .supply, amount: 1, usdValue: 2900)),
        input(13, .aave, token(
            AssetID.eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", role: .borrow, amount: decimal("0.5"), usdValue: 1450)),
        input(14, .aave, token(
            AssetID.usdt, "USDT", "Tether", .stablecoin, coinGeckoId: "tether", role: .borrow,
            amount: decimal("0.4"), usdValue: decimal("0.4"))),
        input(15, .lido, token(AssetID.sol, "SOL", "Solana", .major, coinGeckoId: "solana", role: .stake, amount: 10, usdValue: 1400)),
        input(16, .lido, token(AssetID.sol, "SOL", "Solana", .major, coinGeckoId: "solana", role: .reward, amount: 1, usdValue: 150)),
        input(17, .vesting, token(AssetID.arb, "ARB", "Arbitrum", .governance, coinGeckoId: "arbitrum", amount: 100, usdValue: 80)),
        input(18, .scamWallet, token(AssetID.scam, "SCAM", "Scam Token", .other, coinGeckoId: "scam-token", amount: 1000, usdValue: 50000))
    ]

    static let overrides: [TokenPricingOverrideSnapshot] = [
        TokenPricingOverrideSnapshot(assetId: AssetID.manual, manualPriceUSD: 2),
        TokenPricingOverrideSnapshot(assetId: AssetID.tiny, alwaysShow: true),
        TokenPricingOverrideSnapshot(assetId: AssetID.scam, isIgnored: true)
    ]

    static let mappings = [TokenIdentityMappingSnapshot(identity: degenIdentity, coinGeckoId: "degen-base")]

    static let livePricesUSD: [String: Decimal] = [
        "usd-coin": 1,
        "ethereum": 3000,
        "pepe": decimal("0.00001"),
        "dai": 1,
        "manual-coin": 7,
        "tiny-coin": decimal("0.3"),
        badIdentity.historicalPriceID: 10000,
        "degen-base": decimal("0.01"),
        "tether": 1,
        "solana": 150,
        "arbitrum": decimal("0.9"),
        "scam-token": 50,
        "bitcoin": 60000
    ]

    static let liveChanges24h: [String: Decimal] = [
        "ethereum": decimal("0.25"),
        "pepe": decimal("-0.5"),
        "dai": decimal("0.25"),
        "bitcoin": decimal("0.1")
    ]

    static let historical = HistoricalMarketPrices(
        closesUSD: [
            "chainlink": HistoricalClose(day: day(0), price: 16),
            "uniswap": HistoricalClose(day: day(0), price: 8),
            "dogecoin": HistoricalClose(day: day(0), price: decimal("0.2"))
        ],
        changes24h: [
            "chainlink": decimal("0.25"),
            "dogecoin": decimal("-0.2")
        ])

    static let watchlistIDs = ["bitcoin", "dogecoin"]

    static func prices(
        livePricesUSD: [String: Decimal] = Self.livePricesUSD,
        liveChanges24h: [String: Decimal] = Self.liveChanges24h,
        historical: HistoricalMarketPrices = Self.historical) -> OverviewPriceInputs {
        OverviewPriceInputs(livePricesUSD: livePricesUSD, liveChanges24h: liveChanges24h, historical: historical)
    }

    /// The seam input. Specs with their own tokens pass `inputs` and, when the shared books would
    /// price those tokens, their own books.
    static func context(
        rate: Decimal = 1,
        settings: TokenDashboardSettings = .defaults,
        excluding excludedAssets: Set<UUID> = [],
        inputs: [ValuationInput] = inputs,
        livePricesUSD: [String: Decimal] = Self.livePricesUSD,
        liveChanges24h: [String: Decimal] = Self.liveChanges24h,
        historical: HistoricalMarketPrices = Self.historical) -> OverviewValuationContext {
        OverviewValuationContext(
            inputs: inputs.filter { !excludedAssets.contains($0.token.assetId) },
            overrides: overrides,
            mappings: mappings,
            settings: settings,
            usdToDisplayRate: rate,
            prices: prices(livePricesUSD: livePricesUSD, liveChanges24h: liveChanges24h, historical: historical))
    }

    /// A seam input over ad-hoc tokens, each in the main wallet, with only the books and overrides
    /// a spec passes.
    static func context(
        tokens: [TokenEntry],
        position: PositionSlot = .wallet,
        overrides: [TokenPricingOverrideSnapshot] = [],
        mappings: [TokenIdentityMappingSnapshot] = [],
        settings: TokenDashboardSettings = .defaults,
        rate: Decimal = 1,
        livePricesUSD: [String: Decimal] = [:],
        liveChanges24h: [String: Decimal] = [:],
        historical: HistoricalMarketPrices = .empty) -> OverviewValuationContext {
        OverviewValuationContext(
            inputs: tokens.enumerated().map { ValuationInput(tokenId: uuid(5000 + $0), token: $1, position: position.context) },
            overrides: overrides,
            mappings: mappings,
            settings: settings,
            usdToDisplayRate: rate,
            prices: OverviewPriceInputs(livePricesUSD: livePricesUSD, liveChanges24h: liveChanges24h, historical: historical))
    }

    // MARK: - Builders

    static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    enum PositionSlot {
        case wallet, degenWallet, aave, lido, vesting, scamWallet

        var context: PositionContext {
            switch self {
            case .wallet:
                PositionContext(positionId: PositionID.wallet, positionType: .idle, accountId: mainAccount, chain: .ethereum)
            case .degenWallet:
                PositionContext(positionId: PositionID.degenWallet, positionType: .idle, accountId: degenAccount, chain: .degen)
            case .aave:
                PositionContext(
                    positionId: PositionID.aave,
                    positionType: .lending,
                    accountId: mainAccount,
                    chain: .ethereum,
                    protocolId: "aave-v3")
            case .lido:
                PositionContext(
                    positionId: PositionID.lido,
                    positionType: .staking,
                    accountId: mainAccount,
                    chain: .solana,
                    protocolId: "lido")
            case .vesting:
                PositionContext(
                    positionId: PositionID.vesting,
                    positionType: .vesting,
                    accountId: mainAccount,
                    chain: .arbitrum,
                    protocolId: "arbitrum-vesting")
            case .scamWallet:
                PositionContext(positionId: PositionID.scamWallet, positionType: .idle, accountId: mainAccount, chain: .base)
            }
        }
    }

    /// The `PositionToken` ID of the fixture's `number`th token, in table order.
    static func tokenID(_ number: Int) -> UUID {
        uuid(300 + number)
    }

    static func input(_ tokenNumber: Int, _ position: PositionSlot, _ token: TokenEntry) -> ValuationInput {
        ValuationInput(tokenId: tokenID(tokenNumber), token: token, position: position.context)
    }

    // swiftlint:disable:next function_parameter_count
    static func token(
        _ assetId: UUID,
        _ symbol: String,
        _ name: String,
        _ category: AssetCategory,
        coinGeckoId: String? = nil,
        onchainIdentity: OnchainTokenIdentity? = nil,
        role: TokenRole = .balance,
        amount: Decimal,
        usdValue: Decimal,
        syncedAt: Date = noon(0)) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: name,
            category: category,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity,
            role: role,
            amount: amount,
            usdValue: usdValue,
            syncedAt: syncedAt)
    }
}

import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

/// The portfolio child reducer and the revaluations `AppFeature` drives (#123, spec B1, B4, V1, V2).
/// The projection is the 18-token valuation fixture, prepared; the projector and the valuator are
/// counted, and the save and settings streams are driven by the test.
@MainActor
struct PortfolioFeatureTests {
    typealias Fixture = PortfolioValuationFixture

    static let now = Fixture.noon(0)
    static let projection = PortfolioProjection.fixture()
    private static let usdPrices = PortfolioPriceInputs(
        livePricesUSD: Fixture.livePricesUSD,
        liveChanges24h: Fixture.liveChanges24h,
        usdToDisplayRate: 1,
        currency: .usd)

    // MARK: - V2: the valued output equals today's pipeline

    /// The headline values the holdings and polling ranks the candidates; here the holdings leave out
    /// the first token, so valuing the wrong list would show.
    @Test func `the headline and polling ids equal today's overview pipeline`() {
        let settings = DashboardSettings(dashboard: .defaults, isHistoricalBackfillEnabled: true, watchlistIDs: Fixture.watchlistIDs)
        var projection = PortfolioProjection.fixture(historical: Fixture.historical)
        projection.holdings = Array(projection.holdings.dropFirst())

        let output = PortfolioValuator.compute(PortfolioValuationRequest(
            projection: projection,
            prices: Self.usdPrices,
            settings: settings))

        let holdingsToday = Fixture.context(inputs: Array(Fixture.inputs.dropFirst()))
        let candidatesToday = Fixture.context(liveChanges24h: [:])
        #expect(output.headline == OverviewFeature.headline(holdingsToday))
        #expect(output.headline != OverviewFeature.headline(Fixture.context()), "the dropped holding moves the headline")
        #expect(output.pricePollingIDs == OverviewFeature.pricePollingIDs(candidatesToday, watchlistIDs: Fixture.watchlistIDs))
        #expect(output.currencyCode == FiatCurrency.usd.displayCode)
        #expect(output.pricePollingIDs.count > Fixture.watchlistIDs.count, "holdings are polled too")
    }

    @Test func `the polling ids keep today's ranking when live prices reorder the holdings`() {
        var prices = Self.usdPrices
        prices.livePricesUSD["pepe"] = 1
        let settings = DashboardSettings(dashboard: .defaults, isHistoricalBackfillEnabled: true, watchlistIDs: [])

        let output = PortfolioValuator.compute(PortfolioValuationRequest(
            projection: .fixture(historical: Fixture.historical),
            prices: prices,
            settings: settings))

        let today = Fixture.context(livePricesUSD: prices.livePricesUSD, liveChanges24h: [:])
        #expect(output.pricePollingIDs == OverviewFeature.pricePollingIDs(today, watchlistIDs: []))
        #expect(output.pricePollingIDs.first == "pepe", "the larger live value ranks first")
    }

    // MARK: - V1/V3: one revaluation per price tick, in an effect, no rebuild

    /// The per-tick valuation missed its 16 ms main-thread budget on the real store (31–33 ms), so it
    /// runs in an effect and the reducer stores only the result (spec V3's fallback). `TestStore`
    /// runs effects on the main serial executor, so the thread itself is pinned by the Release
    /// signposts, not here.
    @Test func `a price tick revalues once in an effect and rebuilds nothing`() async {
        let counts = Counts()
        let store = Self.store(counts: counts, projection: Self.projection)

        await store.send(.pricesReceived(PriceUpdate(prices: ["ethereum": 3100], changes24h: [:]))) {
            $0.livePricesUSD["ethereum"] = 3100
            $0.lastPriceUpdate = Self.now
        }
        await store.receive(\.portfolio.revalued) {
            $0.portfolio.valued = Self.expected(prices: $0.portfolioPriceInputs, settings: $0.portfolio.settings)
        }

        #expect(counts.valuations == 1)
        #expect(counts.builds == 0)
    }

    /// The bad onchain price stays implausible, so the output is unchanged: the tick still revalues
    /// once, and the equal result is not written.
    @Test func `an onchain fallback tick revalues once and leaves an unchanged output alone`() async {
        let counts = Counts()
        let store = Self.store(counts: counts, projection: Self.projection)
        let identity = Fixture.badIdentity

        await store.send(.onchainFallbackPricesReceived(
            PriceUpdate(prices: [identity.historicalPriceID: 9000], changes24h: [:]),
            identities: [identity])) {
                $0.livePricesUSD[identity.historicalPriceID] = 9000
                $0.lastPriceUpdate = Self.now
                $0.onchainFallbackFetchedAt[identity] = Self.now
            }
        await store.receive(\.portfolio.revalued)

        #expect(counts.valuations == 1)
        #expect(counts.builds == 0)
    }

    /// A tick arrives while the previous revaluation is still running: the newer one cancels it, so
    /// only the latest prices are ever stored.
    @Test func `the latest revaluation wins`() async {
        let clock = TestClock()
        let calls = Mutex(0)
        let store = TestStore(initialState: Self.state(projection: Self.projection)) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.currentDate.now = { Self.now }
            $0.portfolioValuator.value = { request in
                let call = calls.withLock { value in
                    value += 1
                    return value
                }
                if call == 1 {
                    // Still valuing when the next tick lands.
                    try? await clock.sleep(for: .seconds(1))
                }
                return PortfolioValuator.compute(request)
            }
        }

        await store.send(.pricesReceived(PriceUpdate(prices: ["ethereum": 3100], changes24h: [:]))) {
            $0.livePricesUSD["ethereum"] = 3100
            $0.lastPriceUpdate = Self.now
        }
        await store.send(.pricesReceived(PriceUpdate(prices: ["ethereum": 3200], changes24h: [:]))) {
            $0.livePricesUSD["ethereum"] = 3200
        }
        await store.receive(\.portfolio.revalued) {
            $0.portfolio.valued = Self.expected(prices: $0.portfolioPriceInputs, settings: $0.portfolio.settings)
        }
        await clock.advance(by: .seconds(1))

        // Exhaustive: the first tick's `revalued`, had it been sent, would fail the test.
        #expect(calls.withLock { $0 } == 2)
    }

    /// The book is USD; a price update in any other currency changes nothing, as before (V1).
    @Test func `a non usd price update revalues nothing`() async {
        let counts = Counts()
        let store = Self.store(counts: counts, projection: Self.projection)

        await store.send(.pricesReceived(PriceUpdate(currency: .chf, prices: ["ethereum": 2800], changes24h: [:])))

        #expect(counts.valuations == 0)
    }

    @Test func `before the first build a price tick values nothing`() async {
        let counts = Counts()
        let store = Self.store(counts: counts, projection: nil)

        await store.send(.pricesReceived(PriceUpdate(prices: ["ethereum": 3100], changes24h: [:]))) {
            $0.livePricesUSD["ethereum"] = 3100
            $0.lastPriceUpdate = Self.now
        }

        #expect(counts.valuations == 0)
        #expect(store.state.portfolio.valued == nil)
    }

    // MARK: - V1/B1: currency and rate

    @Test func `a display currency switch revalues once and rebuilds nothing`() async {
        let counts = Counts()
        let store = Self.store(counts: counts, projection: Self.projection, currency: .chf, rate: Fixture.decimal("0.9"))

        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
        }
        await store.receive(\.portfolio.revalued) {
            $0.portfolio.valued = Self.expected(prices: $0.portfolioPriceInputs, settings: $0.portfolio.settings)
        }

        #expect(counts.valuations == 1)
        #expect(counts.builds == 0)
        #expect(store.state.portfolio.projection == Self.projection, "the projection, USD book included, is unchanged")
        #expect(store.state.portfolio.valued?.currencyCode == FiatCurrency.usd.displayCode)
    }

    @Test func `a rate refresh revalues once and rebuilds nothing`() async {
        let counts = Counts()
        let store = Self.store(counts: counts, projection: Self.projection, currency: .chf, rate: Fixture.decimal("0.9"))

        await store.send(.currentCurrencyConversionRateReceived(.chf, .success(Fixture.decimal("0.95")))) {
            $0.currentUSDToDisplayRate = Fixture.decimal("0.95")
        }
        await store.receive(\.portfolio.revalued) {
            $0.portfolio.valued = Self.expected(prices: $0.portfolioPriceInputs, settings: $0.portfolio.settings)
        }

        #expect(counts.valuations == 1)
        #expect(counts.builds == 0)
    }

    // MARK: - B1/B4: building

    @Test func `launch builds once and revalues the new projection`() async {
        let counts = Counts()
        let store = Self.store(counts: counts, projection: nil, built: Self.projection)

        let task = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.projectionBuilt) {
            $0.portfolio.projection = Self.projection
        }
        await store.receive(\.portfolio.delegate.revaluationNeeded)
        await store.receive(\.portfolio.revalued) {
            $0.portfolio.valued = Self.expected(prices: $0.portfolioPriceInputs, settings: $0.portfolio.settings)
        }
        await task.cancel()

        #expect(counts.builds == 1)
        #expect(counts.requests == [PortfolioProjectionRequest(
            isHistoricalBackfillEnabled: HistoricalPriceBackfillSettings.defaultIsEnabled,
            now: Self.now)])
        #expect(counts.valuations == 1)
    }

    @Test func `a burst of saves to read entities builds once after the debounce`() async {
        let counts = Counts()
        let saves = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let clock = TestClock()
        let store = Self.store(counts: counts, projection: Self.projection, built: Self.projection, saves: saves.stream, clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)

        let task = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.projectionBuilt)
        counts.reset()

        saves.continuation.yield(.entities(["Position"]))
        saves.continuation.yield(.entities(["PositionToken", "Asset"]))
        saves.continuation.yield(.entities(["CategorySymbolRule"]))
        await clock.advance(by: .milliseconds(299))
        #expect(counts.builds == 0)
        await clock.advance(by: .milliseconds(1))
        await store.receive(\.portfolio.projectionBuilt)
        await task.cancel()

        #expect(counts.builds == 1)
    }

    @Test func `a save touching no read entity builds nothing`() async {
        let counts = Counts()
        let saves = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let clock = TestClock()
        let store = Self.store(counts: counts, projection: Self.projection, built: Self.projection, saves: saves.stream, clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)

        let task = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.projectionBuilt)
        counts.reset()

        saves.continuation.yield(.entities(["CurrencyConversionRatePoint", "AssetSnapshot", "PortfolioSnapshot"]))
        await clock.advance(by: .seconds(1))
        await task.cancel()

        #expect(counts.builds == 0)
    }

    @Test func `an equal build stores nothing and revalues nothing`() async {
        let counts = Counts()
        let store = Self.store(counts: counts, projection: Self.projection, built: Self.projection)

        await store.send(.portfolio(.rebuildRequested))
        await store.receive(\.portfolio.projectionBuilt)

        #expect(counts.builds == 1)
        #expect(counts.valuations == 0)
    }

    /// A failed rebuild keeps the projection the headline shows, records the failure for the slice,
    /// and schedules no retry: the next save or setting change retries.
    @Test func `a failed build keeps the current projection and records the failure`() async {
        let counts = Counts()
        let store = Self.store(counts: counts, projection: Self.projection, failing: true)

        await store.send(.portfolio(.rebuildRequested))
        await store.receive(\.portfolio.projectionBuildFailed) {
            $0.portfolio.buildError = #"PortfolioProjectorError(message: "store unavailable")"#
        }

        #expect(store.state.portfolio.projection == Self.projection)
        #expect(counts.valuations == 0)
    }

    /// With no projection nothing is valued or polled, so a failed first build retries on its own
    /// after `firstBuildRetry`, and a build that lands clears the failure.
    @Test func `a failed first build retries until one lands`() async {
        let clock = TestClock()
        let calls = Mutex(0)
        let projection = Self.projection
        let store = TestStore(initialState: Self.state(projection: nil)) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.currentDate.now = { Self.now }
            $0.portfolioProjector.build = { _ in
                let call = calls.withLock { value in
                    value += 1
                    return value
                }
                guard call > 1 else { throw PortfolioProjectorError(message: "store unavailable") }
                return projection
            }
        }

        await store.send(.portfolio(.rebuildRequested))
        await store.receive(\.portfolio.projectionBuildFailed) {
            $0.portfolio.buildError = #"PortfolioProjectorError(message: "store unavailable")"#
        }
        #expect(store.state.portfolio.valued == nil)
        await clock.advance(by: PortfolioFeature.firstBuildRetry - .seconds(1))
        #expect(calls.withLock { $0 } == 1)

        await clock.advance(by: .seconds(1))
        await store.receive(\.portfolio.rebuildRequested)
        await store.receive(\.portfolio.projectionBuilt) {
            $0.portfolio.buildError = nil
            $0.portfolio.projection = Self.projection
        }
        await store.receive(\.portfolio.delegate.revaluationNeeded)
        await store.receive(\.portfolio.revalued) {
            $0.portfolio.valued = Self.expected(prices: $0.portfolioPriceInputs, settings: $0.portfolio.settings)
        }
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func `a newer build wins over a slower older one`() async {
        let clock = TestClock()
        let calls = Mutex(0)
        let newer = PortfolioProjection.fixture(dropping: 1)
        let store = TestStore(initialState: Self.state(projection: Self.projection)) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.currentDate.now = { Self.now }
            $0.portfolioProjector.build = { _ in
                let call = calls.withLock { value in
                    value += 1
                    return value
                }
                if call == 1 {
                    try await clock.sleep(for: .seconds(5))
                    return .fixture(dropping: 2)
                }
                return newer
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.portfolio(.rebuildRequested))
        await store.send(.portfolio(.rebuildRequested))
        await store.receive(\.portfolio.projectionBuilt)
        await clock.advance(by: .seconds(10))
        await store.finish()

        #expect(store.state.portfolio.projection == newer)
    }

    @Test func `the day rolling over rebuilds without a save`() async {
        let counts = Counts()
        let clock = TestClock()
        let store = Self.store(counts: counts, projection: Self.projection, built: Self.projection, clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)

        let task = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.projectionBuilt)
        counts.reset()

        // `now` is noon, so the next UTC midnight is 12 hours away.
        await clock.advance(by: .seconds(12 * 3600 - 1))
        #expect(counts.builds == 0)
        await clock.advance(by: .seconds(1))
        await store.receive(\.portfolio.projectionBuilt)
        await task.cancel()

        #expect(counts.builds == 1)
    }

    // MARK: - Harness

    final class Counts: Sendable {
        private let state = Mutex((builds: 0, valuations: 0, requests: [PortfolioProjectionRequest]()))

        var builds: Int {
            state.withLock { $0.builds }
        }

        var valuations: Int {
            state.withLock { $0.valuations }
        }

        var requests: [PortfolioProjectionRequest] {
            state.withLock { $0.requests }
        }

        func built(_ request: PortfolioProjectionRequest) {
            state.withLock {
                $0.builds += 1
                $0.requests.append(request)
            }
        }

        func valued() {
            state.withLock { $0.valuations += 1 }
        }

        func reset() {
            state.withLock { $0 = (0, 0, []) }
        }
    }

    static func state(
        projection: PortfolioProjection?,
        currency: FiatCurrency = .usd,
        rate: Decimal = 1) -> AppFeature.State {
        var state = AppFeature.State()
        state.selectedCurrency = currency
        state.currentUSDToDisplayRate = rate
        // Today's historical FX is already fetched, so a rate refresh starts no top-up.
        state.historicalFXLastRefreshDayByCurrency[currency] = HistoricalPriceCalendar.utcStartOfDay(for: now)
        state.livePricesUSD = Fixture.livePricesUSD
        state.priceChanges24h = Fixture.liveChanges24h
        state.portfolio.projection = projection
        if projection != nil {
            state.portfolio.valued = expected(prices: state.portfolioPriceInputs, settings: state.portfolio.settings, projection: projection)
        }
        return state
    }

    static func store(
        counts: Counts,
        projection: PortfolioProjection?,
        built: PortfolioProjection = .empty,
        failing: Bool = false,
        currency: FiatCurrency = .usd,
        rate: Decimal = 1,
        saves: AsyncStream<ModelSaveEvent> = AsyncStream { $0.finish() },
        settings: AsyncStream<DashboardSettings>? = nil,
        current: @escaping @Sendable () -> DashboardSettings = { .defaults },
        clock: TestClock<Duration> = TestClock()) -> TestStoreOf<AppFeature> {
        TestStore(initialState: state(projection: projection, currency: currency, rate: rate)) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.currentDate.now = { Self.now }
            $0.modelSave.saves = { saves }
            $0.dashboardSettings.current = current
            if let settings {
                $0.dashboardSettings.changes = { settings }
            }
            $0.portfolioProjector.build = { request in
                counts.built(request)
                if failing {
                    throw PortfolioProjectorError(message: "store unavailable")
                }
                return built
            }
            $0.portfolioValuator.value = { request in
                counts.valued()
                return PortfolioValuator.compute(request)
            }
            $0.displayCurrencyPreference.save = { _ in }
        }
    }

    static func expected(
        prices: PortfolioPriceInputs,
        settings: DashboardSettings,
        projection: PortfolioProjection? = projection) -> PortfolioValuedOutput? {
        projection.map { PortfolioValuator.compute(PortfolioValuationRequest(projection: $0, prices: prices, settings: settings)) }
    }
}

extension PortfolioProjection {
    /// The 18-token valuation fixture as a prepared projection: every input both as a holding and
    /// as a polling candidate. `dropping` leaves out that many leading inputs, so two fixtures differ.
    static func fixture(dropping count: Int = 0, historical: HistoricalMarketPrices = .empty) -> PortfolioProjection {
        let prepared = PortfolioValuation.prepare(
            Array(PortfolioValuationFixture.inputs.dropFirst(count)),
            overrides: PortfolioValuationFixture.overrides,
            mappings: PortfolioValuationFixture.mappings)
        var projection = PortfolioProjection.empty
        projection.holdings = prepared
        projection.pollingCandidates = prepared
        projection.overrides = PortfolioValuationFixture.overrides
        projection.mappings = PortfolioValuationFixture.mappings
        projection.historical = historical
        return projection
    }
}

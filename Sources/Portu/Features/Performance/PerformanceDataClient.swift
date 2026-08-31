import ComposableArchitecture
import Foundation
import SwiftData

// swiftformat:disable redundantSendable

struct PerformanceDataClientError: Error, Equatable, Sendable {
    var message: String
}

/// Off-main Performance data boundary. The closure is deliberately not `@MainActor`: the
/// whole point of #97 is that row materialisation and aggregation never touch the main
/// thread, so the reducer awaits this from a plain `.run` effect.
struct PerformanceDataClient {
    var load: @Sendable (PerformanceDataRequest) async throws -> PerformanceDataSnapshot
}

extension PerformanceDataClient: DependencyKey {
    /// `PortuApp` replaces this with `.live(modelContainer:)` at Store creation; the
    /// bare dependency has no container to bind to. A missed override throws so the
    /// reducer can surface it as a data-load error instead of trapping the app.
    static let liveValue = Self(
        load: { _ in
            throw PerformanceDataClientError(
                message: "PerformanceDataClient.liveValue must be overridden at Store creation")
        })

    static let testValue = Self(load: { _ in .empty })
}

extension DependencyValues {
    var performanceData: PerformanceDataClient {
        get { self[PerformanceDataClient.self] }
        set { self[PerformanceDataClient.self] = newValue }
    }
}

extension PerformanceDataClient {
    private static let fetcherCreationQueue = DispatchQueue(
        label: "com.portu.performance-data-fetcher",
        qos: .userInitiated)

    /// `@ModelActor` binds its `ModelContext` executor to the queue where it is
    /// initialized. A detached Swift task is not enough because the cooperative
    /// executor may still run that initialization on the main thread. Constructing on
    /// this dedicated dispatch queue makes the off-main invariant deterministic.
    static func makeFetcher(modelContainer: ModelContainer) async -> PerformanceDataFetcher {
        await withCheckedContinuation { continuation in
            fetcherCreationQueue.async {
                continuation.resume(
                    returning: PerformanceDataFetcher(modelContainer: modelContainer))
            }
        }
    }

    static func live(modelContainer: ModelContainer) -> Self {
        let fetcherTask = Task {
            await makeFetcher(modelContainer: modelContainer)
        }
        return Self(
            load: { request in
                do {
                    let fetcher = await fetcherTask.value
                    return try await fetcher.load(request)
                } catch {
                    // `localizedDescription` flattens a plain Swift error into "The
                    // operation couldn't be completed"; keep the error's own text.
                    throw PerformanceDataClientError(message: String(describing: error))
                }
            })
    }
}

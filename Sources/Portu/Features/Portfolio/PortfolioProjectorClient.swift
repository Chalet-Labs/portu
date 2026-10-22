import ComposableArchitecture
import Foundation
import PortuCore
import SwiftData

// swiftformat:disable redundantSendable

struct PortfolioProjectorError: Error, Equatable, Sendable {
    var message: String
}

/// The read model's store boundary (#123). The closure is not `@MainActor`: the build fetches and
/// walks the store on the projector's own executor, and the reducer awaits it from a `.run` effect.
struct PortfolioProjectorClient {
    var build: @Sendable (PortfolioProjectionRequest) async throws -> PortfolioProjection
}

extension PortfolioProjectorClient: DependencyKey {
    /// `PortuApp` replaces this with `.live(modelContainer:)` at Store creation. A missed override
    /// throws, so the dashboard keeps its no-projection state instead of trapping.
    static let liveValue = Self(build: { _ in
        throw PortfolioProjectorError(message: "PortfolioProjectorClient.liveValue must be overridden at Store creation")
    })

    static let testValue = Self(build: { _ in .empty })
}

extension DependencyValues {
    var portfolioProjector: PortfolioProjectorClient {
        get { self[PortfolioProjectorClient.self] }
        set { self[PortfolioProjectorClient.self] = newValue }
    }
}

extension PortfolioProjectorClient {
    private static let projectorCreationQueue = DispatchQueue(
        label: "com.portu.portfolio-projector",
        qos: .userInitiated)

    /// `@ModelActor` binds its `ModelContext` executor to the queue it is created on; a detached task
    /// may still create it on the main thread. See `PerformanceDataClient.makeFetcher`.
    static func makeProjector(modelContainer: ModelContainer) async -> PortfolioProjector {
        await withCheckedContinuation { continuation in
            projectorCreationQueue.async {
                continuation.resume(returning: PortfolioProjector(modelContainer: modelContainer))
            }
        }
    }

    static func live(modelContainer: ModelContainer) -> Self {
        let projectorTask = Task {
            await makeProjector(modelContainer: modelContainer)
        }
        return Self(build: { request in
            let projector = await projectorTask.value
            return try await projector.build(request)
        })
    }
}

extension PortfolioProjection {
    /// An empty store's projection.
    static let empty = PortfolioProjection(
        holdings: [],
        activeTokens: [],
        positionGroups: [],
        positionMeta: [:],
        assets: [:],
        accounts: [:],
        overrides: [],
        mappings: [],
        categories: PortfolioCategoryResolver.defaults.categories,
        watchlistCandidates: [],
        historical: .empty)
}

import ComposableArchitecture
import Foundation
import SwiftData

/// What one `ModelContext.didSave` touched, by entity name.
enum ModelSaveEvent: Equatable, Sendable {
    /// Nothing narrower is known, so an observer has to assume its data changed.
    case all
    case entities(Set<String>)

    /// Reads the identifiers SwiftData attaches to a save. A save that carries none, or that
    /// invalidated every identifier, can't be narrowed down and counts as `.all`.
    init(userInfo: [AnyHashable: Any]?) {
        guard
            let userInfo,
            userInfo[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] == nil
        else {
            self = .all
            return
        }
        let changeKinds: [ModelContext.NotificationKey] = [
            .insertedIdentifiers,
            .updatedIdentifiers,
            .deletedIdentifiers
        ]
        let names = changeKinds.flatMap { kind in
            (userInfo[kind.rawValue] as? [PersistentIdentifier] ?? []).map(\.entityName)
        }
        self = names.isEmpty ? .all : .entities(Set(names))
    }

    func touches(_ entityNames: Set<String>) -> Bool {
        switch self {
        case .all: true
        case let .entities(touched): !touched.isDisjoint(with: entityNames)
        }
    }
}

struct ModelSaveClient: Sendable {
    /// Each call returns a stream of the saves that happen after it, until the stream ends.
    var saves: @Sendable () -> AsyncStream<ModelSaveEvent>

    /// Reports saves from every context of `container`, the main one and the background
    /// writers (sync, backfill, caches) alike. Saves to any other container are ignored.
    static func live(container: ModelContainer) -> Self {
        Self(saves: {
            AsyncStream { continuation in
                nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                    forName: ModelContext.didSave,
                    object: nil,
                    queue: nil) { notification in
                        guard (notification.object as? ModelContext)?.container === container else { return }
                        continuation.yield(ModelSaveEvent(userInfo: notification.userInfo))
                    }
                continuation.onTermination = { _ in
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        })
    }

    /// Reports nothing and ends at once, for builds and tests with no container to watch.
    static let inert = Self(saves: { AsyncStream { $0.finish() } })
}

extension ModelSaveClient: DependencyKey {
    static let liveValue = Self.inert
    static let testValue = Self.inert
}

extension DependencyValues {
    var modelSave: ModelSaveClient {
        get { self[ModelSaveClient.self] }
        set { self[ModelSaveClient.self] = newValue }
    }
}

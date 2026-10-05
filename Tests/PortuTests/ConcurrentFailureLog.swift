import Synchronization

/// Collects check failures from worker threads, where `#expect` is awkward to call from.
final class ConcurrentFailureLog: Sendable {
    private let entries = Mutex<[String]>([])

    var all: [String] {
        entries.withLock { $0 }
    }

    func record(_ message: String) {
        entries.withLock { $0.append(message) }
    }

    func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            record(message())
        }
    }
}

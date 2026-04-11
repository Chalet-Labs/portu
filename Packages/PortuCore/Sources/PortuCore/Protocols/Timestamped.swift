import Foundation

/// Shared protocol for snapshot models that have a timestamp for pruning.
public protocol Timestamped {
    var timestamp: Date { get }
}

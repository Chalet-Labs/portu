import SwiftUI

public struct SyncStatusBadge: View {
    public enum Status: Equatable, Sendable {
        case idle
        case syncing(progress: Double)
        case completedWithErrors(failedAccounts: [String])
        case error(String)
    }

    public let status: Status

    public init(status: Status) {
        self.status = status
    }

    public var tint: Color {
        switch status {
        case .idle:
            PortuTheme.neutralColor
        case .syncing:
            .accentColor
        case .completedWithErrors:
            PortuTheme.warning
        case .error:
            PortuTheme.lossColor
        }
    }

    public var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.35))
            )
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var title: String {
        switch status {
        case .idle:
            return "Idle"
        case .syncing(let progress):
            let percentage = Int((progress * 100).rounded())
            return "Syncing \(percentage)%"
        case .completedWithErrors(let failedAccounts):
            let count = failedAccounts.count
            return "\(count) account\(count == 1 ? "" : "s") failed"
        case .error:
            return "Sync failed"
        }
    }

    private var symbolName: String {
        switch status {
        case .idle:
            return "circle"
        case .syncing:
            return "arrow.trianglehead.2.counterclockwise"
        case .completedWithErrors:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }

    private var helpText: String {
        switch status {
        case .idle:
            return "No sync activity"
        case .syncing(let progress):
            let percentage = Int((progress * 100).rounded())
            return "Sync in progress (\(percentage)%)"
        case .completedWithErrors(let failedAccounts):
            return "Accounts with sync errors: \(failedAccounts.joined(separator: ", "))"
        case .error(let message):
            return message
        }
    }
}

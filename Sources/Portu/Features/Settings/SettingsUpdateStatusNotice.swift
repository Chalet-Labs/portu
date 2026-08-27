import SwiftUI

/// Non-modal inline notice for the Updates section of General Settings.
/// Renders nothing when status is `.available` with no failure.
struct SettingsUpdateStatusNotice: View {
    let status: UpdaterStatus
    let onDismiss: (() -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        switch noticeKind {
        case .none:
            EmptyView()
        case let .failure(failure):
            failureNotice(failure)
        case let .externallyManaged(owner):
            externallyManagedNotice(owner: owner)
        case let .staticUnavailable(reason):
            staticUnavailableNotice(reason: reason)
        }
    }

    // MARK: - Sub-views

    private func failureNotice(_ failure: UpdaterFailure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsInlineNotice(
                title: "Update not installed",
                message: failure.message,
                style: .error)

            HStack(spacing: 8) {
                Button {
                    openURL(UpdaterFailure.recoveryURL)
                } label: {
                    Label("Open GitHub Releases", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .settingsSecondaryButton(isDisabled: false)
                .accessibilityLabel("Open the GitHub Releases page to install Portu manually")

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Dismiss")
                    }
                    .buttonStyle(.plain)
                    .settingsSecondaryButton(isDisabled: false)
                    .accessibilityLabel("Dismiss this update failure notice")
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func externallyManagedNotice(owner: String) -> some View {
        SettingsInlineNotice(
            title: "\(owner) manages updates",
            message: "This build is managed by \(owner). Use \(owner) to check for and install new versions of Portu.",
            style: .action)
    }

    private func staticUnavailableNotice(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsInlineNotice(
                title: "Updates unavailable",
                message: reason,
                style: .action)

            HStack(spacing: 8) {
                Button {
                    openURL(UpdaterFailure.recoveryURL)
                } label: {
                    Label("Open GitHub Releases", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .settingsSecondaryButton(isDisabled: false)
                .accessibilityLabel("Open the GitHub Releases page to download a Portu release build")

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - State resolution

    private enum NoticeKind {
        case none
        case failure(UpdaterFailure)
        case externallyManaged(String)
        case staticUnavailable(String)
    }

    private var noticeKind: NoticeKind {
        if let failure = status.failure {
            return .failure(failure)
        }
        switch status.availability {
        case .available:
            return .none
        case let .externallyManaged(owner):
            return .externallyManaged(owner)
        case let .unavailable(reason):
            return .staticUnavailable(reason)
        }
    }
}

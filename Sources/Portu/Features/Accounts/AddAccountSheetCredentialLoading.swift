extension AddAccountSheet {
    @MainActor
    func loadCredentialsIfNeeded() async {
        guard !didLoadCredentials, mode.isEditing, let account, account.kind == .exchange else { return }
        didLoadCredentials = true
        defer { isLoadingCredentials = false }
        var loadedDraft = draft
        let loadError = await loadedDraft.loadExchangeCredentials(
            accountID: account.id,
            secretStore: secretStore)
        draft = loadedDraft
        if loadError == nil {
            // Re-baseline so loaded credentials don't read as unsaved user edits.
            baselineDraft = draft
        }
    }

    @MainActor
    func retryCredentialLoad() {
        guard !isLoadingCredentials else { return }
        didLoadCredentials = false
        isLoadingCredentials = true
        Task { @MainActor in
            await loadCredentialsIfNeeded()
        }
    }
}

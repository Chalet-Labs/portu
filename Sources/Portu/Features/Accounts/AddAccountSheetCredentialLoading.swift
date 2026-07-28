extension AddAccountSheet {
    @MainActor
    func loadCredentialsIfNeeded() async {
        guard !didLoadCredentials, mode.isEditing, let account, account.kind == .exchange else { return }
        didLoadCredentials = true
        isLoadingCredentials = true
        defer { isLoadingCredentials = false }
        var loadedDraft = draft
        let loadResult = await loadedDraft.loadExchangeCredentials(
            accountID: account.id,
            secretStore: secretStore,
            preservingEditsSince: baselineDraft)
        draft = loadedDraft
        if let storedCredentials = loadResult.storedCredentials {
            baselineDraft.exchangeAPIKey = storedCredentials.apiKey ?? ""
            baselineDraft.exchangeAPISecret = storedCredentials.apiSecret ?? ""
            baselineDraft.exchangePassphrase = storedCredentials.passphrase ?? ""
            baselineDraft.exchangeCredentialsLoaded = true
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

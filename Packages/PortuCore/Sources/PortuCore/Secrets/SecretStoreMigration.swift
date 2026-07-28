public enum SecretStoreMigration {
    /// Copies each plaintext value to the secure store, reads it back, and only
    /// then removes that individual plaintext value. A failure leaves the
    /// current source value intact and propagates an actionable keychain error.
    public static func migrate(
        keys: [KeychainKey],
        from source: any SecretStore,
        to destination: any SecretStore) throws(KeychainError) {
        var firstError: KeychainError?
        for key in keys {
            do {
                try migrate(key: key, from: source, to: destination)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private static func migrate(
        key: KeychainKey,
        from source: any SecretStore,
        to destination: any SecretStore) throws(KeychainError) {
        guard let sourceValue = try source.get(key: key) else {
            return
        }

        if try destination.get(key: key) != nil {
            // A readable secure value is authoritative, including when it is
            // newer than the legacy plaintext value.
            try source.delete(key: key)
            return
        }

        try destination.set(key: key, value: sourceValue)
        guard try destination.get(key: key) == sourceValue else {
            throw .encodingFailed
        }
        try source.delete(key: key)
    }
}

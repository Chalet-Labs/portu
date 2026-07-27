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

        if let destinationValue = try destination.get(key: key) {
            guard destinationValue == sourceValue else {
                // Preserve both values rather than overwriting a newer secure
                // credential or deleting the only recoverable plaintext copy.
                return
            }
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

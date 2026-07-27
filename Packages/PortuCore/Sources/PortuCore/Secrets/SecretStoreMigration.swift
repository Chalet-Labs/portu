public enum SecretStoreMigration {
    /// Copies each plaintext value to the secure store, reads it back, and only
    /// then removes that individual plaintext value. A failure leaves the
    /// current source value intact and propagates an actionable keychain error.
    public static func migrate(
        keys: [KeychainKey],
        from source: any SecretStore,
        to destination: any SecretStore) throws(KeychainError) {
        for key in keys {
            guard let sourceValue = try source.get(key: key) else {
                continue
            }

            if let destinationValue = try destination.get(key: key) {
                guard destinationValue == sourceValue else {
                    // Preserve both values rather than overwriting a newer secure
                    // credential or deleting the only recoverable plaintext copy.
                    continue
                }
                try source.delete(key: key)
                continue
            }

            try destination.set(key: key, value: sourceValue)
            guard try destination.get(key: key) == sourceValue else {
                throw .encodingFailed
            }
            try source.delete(key: key)
        }
    }
}

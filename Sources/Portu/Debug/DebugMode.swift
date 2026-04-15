#if DEBUG

    import Foundation

    enum DebugMode {
        static let enabledKey = "debugServerEnabled"
        static let portKey = "debugServerPort"
        static let defaultPort: UInt16 = 9999

        static func isEnabled(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            defaults: UserDefaults = .standard) -> Bool {
            arguments.contains("--debug-server")
                || defaults.bool(forKey: enabledKey)
        }

        static func port(defaults: UserDefaults = .standard) -> UInt16 {
            let stored = defaults.integer(forKey: portKey)
            guard stored > 0, stored <= UInt16.max else { return defaultPort }
            return UInt16(stored)
        }
    }

#endif

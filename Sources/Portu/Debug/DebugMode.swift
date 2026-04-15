#if DEBUG

    import Foundation

    enum DebugMode {
        static func isEnabled(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            defaults: UserDefaults = .standard) -> Bool {
            arguments.contains("--debug-server")
                || defaults.bool(forKey: "debugServerEnabled")
        }

        static func port(defaults: UserDefaults = .standard) -> UInt16 {
            let stored = defaults.integer(forKey: "debugServerPort")
            guard stored > 0, stored <= UInt16.max else { return 9999 }
            return UInt16(stored)
        }
    }

#endif

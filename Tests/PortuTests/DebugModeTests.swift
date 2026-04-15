#if DEBUG
    import Foundation
    @testable import Portu
    import Testing

    struct DebugModeTests {
        // MARK: - isEnabled

        @Test func `enabled when launch arg present`() {
            let result = DebugMode.isEnabled(
                arguments: ["Portu", "--debug-server"],
                defaults: cleanDefaults())
            #expect(result)
        }

        @Test func `enabled when user defaults toggled`() {
            let defaults = cleanDefaults()
            defaults.set(true, forKey: DebugMode.enabledKey)
            let result = DebugMode.isEnabled(arguments: [], defaults: defaults)
            #expect(result)
        }

        @Test func `disabled when neither set`() {
            let result = DebugMode.isEnabled(
                arguments: [],
                defaults: cleanDefaults())
            #expect(!result)
        }

        @Test func `enabled when both set`() {
            let defaults = cleanDefaults()
            defaults.set(true, forKey: DebugMode.enabledKey)
            let result = DebugMode.isEnabled(
                arguments: ["Portu", "--debug-server"],
                defaults: defaults)
            #expect(result)
        }

        // MARK: - port

        @Test func `port defaults to 9999`() {
            #expect(DebugMode.port(defaults: cleanDefaults()) == DebugMode.defaultPort)
        }

        @Test func `port reads from defaults`() {
            let defaults = cleanDefaults()
            defaults.set(8080, forKey: DebugMode.portKey)
            #expect(DebugMode.port(defaults: defaults) == 8080)
        }

        @Test func `port ignores zero`() {
            let defaults = cleanDefaults()
            defaults.set(0, forKey: DebugMode.portKey)
            #expect(DebugMode.port(defaults: defaults) == DebugMode.defaultPort)
        }

        @Test func `port ignores negative`() {
            let defaults = cleanDefaults()
            defaults.set(-1, forKey: DebugMode.portKey)
            #expect(DebugMode.port(defaults: defaults) == DebugMode.defaultPort)
        }

        @Test func `port ignores values above UInt16 max`() {
            let defaults = cleanDefaults()
            defaults.set(Int(UInt16.max) + 1, forKey: DebugMode.portKey)
            #expect(DebugMode.port(defaults: defaults) == DebugMode.defaultPort)
        }

        // MARK: - Helpers

        private func cleanDefaults() -> UserDefaults {
            let suite = "com.portu.test.DebugMode.\(UUID().uuidString)"
            return UserDefaults(suiteName: suite)!
        }
    }
#endif

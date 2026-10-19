import Foundation
import SwiftUI

@main
enum PortuMain {
    @MainActor
    static func main() {
        if isTestHost() {
            TestHostApp.main()
        } else {
            PortuApp.main()
        }
    }

    static func isTestHost(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}

/// The XCTest host: no window, no store and no startup work, so a test run never
/// opens or migrates the user's data.
struct TestHostApp: App {
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

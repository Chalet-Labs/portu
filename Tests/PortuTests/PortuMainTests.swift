@testable import Portu
import Testing

struct PortuMainTests {
    static let environments: [([String: String], Bool)] = [
        (["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"], true),
        ([:], false),
        (["HOME": "/Users/tester"], false)
    ]

    @Test(arguments: environments)
    func `the test host is detected from the xctest configuration path`(
        environment: [String: String],
        isTestHost: Bool) {
        #expect(PortuMain.isTestHost(environment: environment) == isTestHost)
    }

    @Test func `the running test process is the test host`() {
        #expect(PortuMain.isTestHost())
    }
}

import Foundation
@testable import Portu
import Testing

// MARK: - Mock Protocol for Integration Tests

private final class LoggerTestProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var shouldFail = false
    nonisolated(unsafe) static var responseBody = Data("test-response-body".utf8)

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".local") == true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if Self.shouldFail {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func waitForEntries(
    in buffer: NetworkLogBuffer = .shared,
    count: Int,
    timeout: TimeInterval = 1.0) async throws {
    let deadline = Date.now.addingTimeInterval(timeout)
    while await buffer.entryCount < count, Date.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    let actual = await buffer.entryCount
    if actual < count {
        Issue.record("Timed out waiting for \(count) log entries; got \(actual) after \(timeout)s")
    }
}

// MARK: - Integration Tests

@Suite(.serialized) struct NetworkLoggerTests {
    init() async {
        await NetworkLogBuffer.shared.clear()
        LoggerTestProtocol.shouldFail = false
        LoggerTestProtocol.responseBody = Data("test-response-body".utf8)
        NetworkLogger.forwardingProtocolClasses = [LoggerTestProtocol.self]
    }

    @Test func `request through debug session gets logged`() async throws {
        defer { NetworkLogger.forwardingProtocolClasses = [] }
        let session = NetworkLogger.debugSession()
        var request = try URLRequest(url: #require(URL(string: "https://test.local/api/v1/data")))
        request.httpMethod = "POST"
        request.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(data == LoggerTestProtocol.responseBody)

        try await waitForEntries(count: 1)

        let entries = await NetworkLogBuffer.shared.entries()
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.url == "https://test.local/api/v1/data")
        #expect(entry.method == "POST")
        #expect(entry.statusCode == 200)
        #expect(entry.headers["Authorization"] == "***")
        #expect(entry.responseSizeBytes == LoggerTestProtocol.responseBody.count)
    }

    @Test func `failed request logs nil status code and error`() async throws {
        defer { NetworkLogger.forwardingProtocolClasses = [] }
        LoggerTestProtocol.shouldFail = true

        let session = NetworkLogger.debugSession()
        do {
            _ = try await session.data(from: #require(URL(string: "https://test.local/fail")))
            Issue.record("Expected network error")
        } catch {
            #expect(error is URLError)
        }

        try await waitForEntries(count: 1)

        let entries = await NetworkLogBuffer.shared.entries()
        #expect(entries.count == 1)
        #expect(entries[0].statusCode == nil)
        #expect(entries[0].errorDescription != nil)
    }

    @Test func `response body is not captured`() async throws {
        defer { NetworkLogger.forwardingProtocolClasses = [] }
        LoggerTestProtocol.responseBody = Data(repeating: 0xFF, count: 4096)

        let session = NetworkLogger.debugSession()
        _ = try await session.data(from: #require(URL(string: "https://test.local/large")))

        try await waitForEntries(count: 1)

        let entries = await NetworkLogBuffer.shared.entries()
        #expect(entries.count == 1)
        #expect(entries[0].responseSizeBytes == 4096)
    }

    @Test func `multiple requests all logged`() async throws {
        defer { NetworkLogger.forwardingProtocolClasses = [] }
        let session = NetworkLogger.debugSession()

        for i in 0 ..< 3 {
            _ = try await session.data(from: #require(URL(string: "https://test.local/req/\(i)")))
        }

        try await waitForEntries(count: 3)

        let entries = await NetworkLogBuffer.shared.entries()
        #expect(entries.count == 3)
        #expect(entries[0].url == "https://test.local/req/0")
        #expect(entries[1].url == "https://test.local/req/1")
        #expect(entries[2].url == "https://test.local/req/2")
    }

    @Test func `debug session works identically to shared`() async throws {
        defer { NetworkLogger.forwardingProtocolClasses = [] }
        let session = NetworkLogger.debugSession()
        let (data, response) = try await session.data(from: #require(URL(string: "https://test.local/identity")))
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(data == LoggerTestProtocol.responseBody)
    }
}

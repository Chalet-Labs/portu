import Foundation
@testable import PortuNetwork
import Testing

private final class PacingSleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedDurations: [Duration] = []

    var durations: [Duration] {
        lock.withLock { recordedDurations }
    }

    func sleep(for duration: Duration) async throws {
        lock.withLock {
            recordedDurations.append(duration)
        }
    }
}

@Suite(.serialized)
struct ZerionAPIClientTests {
    init() {
        ZerionAPIClientMockURLProtocol.reset()
    }

    @Test func `GET uses fixed Zerion v1 host basic authentication and encoded filters`() async throws {
        defer { ZerionAPIClientMockURLProtocol.reset() }
        ZerionAPIClientMockURLProtocol.respond { request in
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "api.zerion.io")
            #expect(request.url?.path == "/v1/chains")
            #expect(request.url?.absoluteString.hasPrefix("https://api.zerion.io/v1/chains/?") == true)
            #expect(request.url?.query?.contains("filter%5Bchain_ids%5D=ethereum,base") == true)
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic dGVzdC1rZXk6")
            return .init(data: Data(#"{"data":[]}"#.utf8), statusCode: 200, headers: [:])
        }

        let client = ZerionAPIClient(apiKey: { "test-key" }, session: makeZerionAPIClientMockSession())
        let response: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(
            path: "chains/",
            queryItems: [URLQueryItem(name: "filter[chain_ids]", value: "ethereum,base")])

        #expect(response.data.isEmpty)
    }

    @Test func `missing key fails before a request`() async {
        defer { ZerionAPIClientMockURLProtocol.reset() }
        let client = ZerionAPIClient(apiKey: { " \n" }, session: makeZerionAPIClientMockSession())

        await #expect(throws: ZerionError.missingAPIKey) {
            let _: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(path: "chains/")
        }
        #expect(ZerionAPIClientMockURLProtocol.requests.isEmpty)
    }

    @Test(
        arguments: [
            (401, ZerionError.unauthorized),
            (402, ZerionError.paymentRequired),
            (404, ZerionError.notFound),
            (429, ZerionError.rateLimited(remainingSecond: 0, remainingDay: 12, remainingMonth: 250, reset: "42")),
            (503, ZerionError.temporarilyUnavailable(retryAfter: 7))
        ])
    func `structured HTTP errors retain status-specific metadata`(status: Int, expected: ZerionError) async {
        defer { ZerionAPIClientMockURLProtocol.reset() }
        ZerionAPIClientMockURLProtocol.respond { _ in
            .init(
                data: Data(#"{"errors":[{"title":"Nope","detail":"Try later"}]}"#.utf8),
                statusCode: status,
                headers: [
                    "X-RateLimit-Remaining-Second": "0",
                    "X-RateLimit-Remaining-Day": "12",
                    "X-RateLimit-Remaining-Month": "250",
                    "X-RateLimit-Reset": "42",
                    "Retry-After": "7"
                ])
        }
        let client = ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAPIClientMockSession(),
            maximumRetryAttempts: 0)

        await #expect(throws: expected) {
            let _: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(path: "chains/")
        }
    }

    @Test func `foreign or insecure pagination links are rejected`() async throws {
        let client = ZerionAPIClient(apiKey: { "test-key" }, session: makeZerionAPIClientMockSession())

        await #expect(throws: ZerionError.untrustedURL) {
            let _: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(
                next: #require(URL(string: "https://attacker.example/steal")))
        }
        await #expect(throws: ZerionError.untrustedURL) {
            let _: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(
                next: #require(URL(string: "http://api.zerion.io/v1/chains/")))
        }
        #expect(ZerionAPIClientMockURLProtocol.requests.isEmpty)
    }

    @Test func `transient server errors are retried with a bounded attempt count`() async throws {
        defer { ZerionAPIClientMockURLProtocol.reset() }
        ZerionAPIClientMockURLProtocol.respond { _ in
            let statuses = [500, 502, 504, 200]
            let status = statuses[ZerionAPIClientMockURLProtocol.requests.count - 1]
            return .init(
                data: Data(status == 200 ? #"{"data":[]}"#.utf8 : #"{"errors":[]}"#.utf8),
                statusCode: status,
                headers: [:])
        }
        let client = ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAPIClientMockSession(),
            minimumRequestInterval: .zero,
            maximumRetryAttempts: 3)

        let response: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(path: "chains/")

        #expect(response.data.isEmpty)
        #expect(ZerionAPIClientMockURLProtocol.requests.count == 4)
    }

    @Test func `request pacing reserves later slots before sleeping`() async throws {
        defer { ZerionAPIClientMockURLProtocol.reset() }
        let sleepRecorder = PacingSleepRecorder()
        let client = ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAPIClientMockSession(),
            minimumRequestInterval: .seconds(1),
            pacingNow: { .zero },
            pacingSleep: { try await sleepRecorder.sleep(for: $0) })

        for _ in 0 ..< 3 {
            let _: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(path: "chains/")
        }

        #expect(sleepRecorder.durations == [.seconds(1), .seconds(2)])
    }

    @Test func `organization quota headers are retained in a rate limit error`() async {
        defer { ZerionAPIClientMockURLProtocol.reset() }
        ZerionAPIClientMockURLProtocol.respond { _ in
            .init(
                data: Data(#"{"errors":[]}"#.utf8),
                statusCode: 429,
                headers: [
                    "RateLimit-Org-Second-Remaining": "0",
                    "RateLimit-Org-Day-Remaining": "12",
                    "RateLimit-Org-Month-Remaining": "250",
                    "RateLimit-Org-Second-Reset": "42"
                ])
        }
        let client = ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAPIClientMockSession(),
            maximumRetryAttempts: 0)

        await #expect(throws: ZerionError.rateLimited(
            remainingSecond: 0,
            remainingDay: 12,
            remainingMonth: 250,
            reset: "42")) {
            let _: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(path: "chains/")
        }
    }

    @Test func `JSON API error details are decoded for a rejected request`() async {
        defer { ZerionAPIClientMockURLProtocol.reset() }
        ZerionAPIClientMockURLProtocol.respond { _ in
            .init(
                data: Data(#"{"errors":[{"title":"Invalid filter","detail":"chain_ids is unsupported"}]}"#.utf8),
                statusCode: 400,
                headers: [:])
        }
        let client = ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAPIClientMockSession(),
            maximumRetryAttempts: 0)

        await #expect(throws: ZerionError.apiError(
            statusCode: 400,
            title: "Invalid filter",
            detail: "chain_ids is unsupported")) {
            let _: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(path: "chains/")
        }
    }

    @Test func `exhausted daily quota is not retried`() async {
        defer { ZerionAPIClientMockURLProtocol.reset() }
        ZerionAPIClientMockURLProtocol.respond { _ in
            .init(
                data: Data(#"{"errors":[]}"#.utf8),
                statusCode: 429,
                headers: [
                    "RateLimit-Org-Day-Remaining": "0",
                    "Retry-After": "1"
                ])
        }
        let client = ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAPIClientMockSession(),
            minimumRequestInterval: .zero)

        await #expect(throws: (any Error).self) {
            let _: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(path: "chains/")
        }
        #expect(ZerionAPIClientMockURLProtocol.requests.count == 1)
    }

    @Test func `retry after beyond the time cap is not waited or retried`() async {
        defer { ZerionAPIClientMockURLProtocol.reset() }
        ZerionAPIClientMockURLProtocol.respond { _ in
            .init(
                data: Data(#"{"errors":[]}"#.utf8),
                statusCode: 503,
                headers: ["Retry-After": "3600"])
        }
        let client = ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionAPIClientMockSession(),
            minimumRequestInterval: .zero,
            maximumRetryDelaySeconds: 10)

        await #expect(throws: ZerionError.temporarilyUnavailable(retryAfter: 3600)) {
            let _: ZerionCollectionEnvelope<ZerionEmptyResource> = try await client.get(path: "chains/")
        }
        #expect(ZerionAPIClientMockURLProtocol.requests.count == 1)
    }
}

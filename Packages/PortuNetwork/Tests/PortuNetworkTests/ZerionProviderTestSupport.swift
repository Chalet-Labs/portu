import Foundation
@testable import PortuNetwork

final class ZerionMockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let data: Data
        let statusCode: Int
        let headers: [String: String]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> Response)?
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.withLock { capturedRequests }
    }

    static func reset() {
        lock.withLock {
            handler = nil
            capturedRequests = []
        }
    }

    static func respond(using handler: @escaping @Sendable (URLRequest) throws -> Response) {
        lock.withLock { self.handler = handler }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler = Self.lock.withLock {
            Self.capturedRequests.append(request)
            return Self.handler
        }

        do {
            let stub = try handler?(request) ?? Response(data: Data(#"{"data":[]}"#.utf8), statusCode: 200, headers: [:])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: nil,
                headerFields: stub.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeZerionMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ZerionMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

final class ZerionAPIClientMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> ZerionMockURLProtocol.Response)?
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.withLock { capturedRequests }
    }

    static func reset() {
        lock.withLock {
            handler = nil
            capturedRequests = []
        }
    }

    static func respond(
        using handler: @escaping @Sendable (URLRequest) throws -> ZerionMockURLProtocol.Response) {
        lock.withLock { self.handler = handler }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler = Self.lock.withLock {
            Self.capturedRequests.append(request)
            return Self.handler
        }
        do {
            let stub = try handler?(request) ?? .init(
                data: Data(#"{"data":[]}"#.utf8),
                statusCode: 200,
                headers: [:])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: nil,
                headerFields: stub.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeZerionAPIClientMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ZerionAPIClientMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

final class ZerionAnalyticsMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler:
        (@Sendable (URLRequest) throws -> ZerionMockURLProtocol.Response)?
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.withLock { capturedRequests }
    }

    static func reset() {
        lock.withLock {
            handler = nil
            capturedRequests = []
        }
    }

    static func respond(
        using handler: @escaping @Sendable (URLRequest) throws -> ZerionMockURLProtocol.Response) {
        lock.withLock { self.handler = handler }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler = Self.lock.withLock {
            Self.capturedRequests.append(request)
            return Self.handler
        }
        do {
            let stub = try handler?(request) ?? .init(
                data: Data(#"{"data":[]}"#.utf8),
                statusCode: 200,
                headers: [:])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: nil,
                headerFields: stub.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeZerionAnalyticsMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ZerionAnalyticsMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

extension String {
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}

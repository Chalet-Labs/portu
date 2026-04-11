import Foundation

// MARK: - NetworkLogEntry

struct NetworkLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let url: String
    let method: String
    let statusCode: Int?
    let responseSizeBytes: Int
    let elapsed: TimeInterval
    let headers: [String: String]
    var errorDescription: String? = nil

    private static let sensitiveHeaderNames: Set<String> = [
        "authorization", "api-key", "api-sign", "api-secret",
        "cookie", "set-cookie"
    ]

    static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        var result = headers
        for key in headers.keys where sensitiveHeaderNames.contains(key.lowercased()) {
            result[key] = "***"
        }
        return result
    }
}

// MARK: - NetworkLogBuffer

actor NetworkLogBuffer {
    static let shared = NetworkLogBuffer()

    private var buffer: [NetworkLogEntry?]
    private var writeIndex = 0
    private var filled = 0
    private let capacity: Int

    init(capacity: Int = 500) {
        precondition(capacity > 0, "NetworkLogBuffer capacity must be positive")
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    func append(_ entry: NetworkLogEntry) {
        buffer[writeIndex] = entry
        writeIndex = (writeIndex + 1) % capacity
        filled = min(filled + 1, capacity)
    }

    func entries(since: Date? = nil, limit: Int? = nil) -> [NetworkLogEntry] {
        guard filled > 0 else { return [] }
        let start = filled < capacity ? 0 : writeIndex
        var result: [NetworkLogEntry] = []
        result.reserveCapacity(filled)
        for i in 0 ..< filled {
            let index = (start + i) % capacity
            if let entry = buffer[index] {
                if let since, entry.timestamp < since { continue }
                result.append(entry)
            }
        }
        guard let limit else { return result }
        guard limit > 0 else { return [] }
        return Array(result.suffix(limit))
    }

    var entryCount: Int {
        filled
    }

    func clear() {
        buffer = Array(repeating: nil, count: capacity)
        writeIndex = 0
        filled = 0
    }
}

// MARK: - NetworkLogger

/// URLProtocol serializes startLoading, stopLoading, and all URLSessionDataDelegate
/// callbacks on its own private queue, so mutable instance state is single-threaded.
final class NetworkLogger: URLProtocol, @unchecked Sendable {
    private static let handledKey = "NetworkLogger.handled"
    private var internalSession: URLSession?
    private var internalTask: URLSessionDataTask?
    private var startTime: Date?
    private var responseSizeCounter = 0

    #if DEBUG
        /// Test hook: protocol classes prepended to the internal forwarding session.
        /// Globally registered protocols don't apply to URLSession(configuration:) sessions,
        /// so tests inject a mock responder here instead.
        nonisolated(unsafe) static var forwardingProtocolClasses: [AnyClass] = []
    #endif

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme, scheme == "http" || scheme == "https" else {
            return false
        }
        return URLProtocol.property(forKey: handledKey, in: request) == nil
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        startTime = Date()
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)
        let config = URLSessionConfiguration.default
        #if DEBUG
            if !Self.forwardingProtocolClasses.isEmpty {
                config.protocolClasses = Self.forwardingProtocolClasses + (config.protocolClasses ?? [])
            }
        #endif
        internalSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        internalTask = internalSession?.dataTask(with: mutable as URLRequest)
        internalTask?.resume()
    }

    override func stopLoading() {
        internalTask?.cancel()
        internalSession?.invalidateAndCancel()
        internalSession = nil
    }

    static func debugSession() -> URLSession {
        let config = URLSessionConfiguration.default
        // Replace (not prepend) — this session is fully owned by the logger.
        config.protocolClasses = [NetworkLogger.self]
        return URLSession(configuration: config)
    }
}

// MARK: - URLSessionDataDelegate

extension NetworkLogger: URLSessionDataDelegate {
    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        responseSizeCounter += data.count
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        let headers = request.allHTTPHeaderFields ?? [:]

        let entry = NetworkLogEntry(
            id: UUID(),
            timestamp: startTime ?? Date(),
            url: request.url?.absoluteString ?? "unknown",
            method: request.httpMethod ?? "GET",
            statusCode: statusCode,
            responseSizeBytes: responseSizeCounter,
            elapsed: elapsed,
            headers: NetworkLogEntry.redactHeaders(headers),
            errorDescription: error?.localizedDescription)

        // URLSessionDataDelegate is synchronous — bridge to the actor asynchronously.
        // Entries appear after the next runloop turn; tests use waitForEntries() polling.
        Task { await NetworkLogBuffer.shared.append(entry) }

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }

        internalSession?.finishTasksAndInvalidate()
        internalSession = nil
    }
}

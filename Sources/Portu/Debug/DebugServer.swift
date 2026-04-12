#if DEBUG

    import ComposableArchitecture
    import Foundation
    import Network
    import os
    import SwiftData

    @MainActor
    final class DebugServer {
        private let port: UInt16
        private var listener: NWListener?
        private var startingListener: NWListener?
        private var routes: [String: [String: @Sendable (HTTPRequest) -> HTTPResponse]] = [:]
        private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
        private let startTime = ContinuousClock.now
        private let logger = Logger(subsystem: "com.portu.app", category: "DebugServer")

        // Stored for future endpoints (sub-issues #3, #4)
        private let modelContainer: ModelContainer?
        private let store: StoreOf<AppFeature>?

        init(
            port: UInt16 = 9999,
            modelContainer: ModelContainer? = nil,
            store: StoreOf<AppFeature>? = nil) {
            self.port = port
            self.modelContainer = modelContainer
            self.store = store
            registerBuiltInRoutes()
        }

        // MARK: - Lifecycle

        func start() async throws {
            guard listener == nil, startingListener == nil else { return }

            let params = NWParameters.tcp

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw DebugServerError.invalidPort(port)
            }
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

            let newListener = try NWListener(using: params)
            startingListener = newListener
            defer { startingListener = nil }

            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    // Safety: `resumed` is only mutated from the .main queue (see newListener.start below),
                    // so concurrent access cannot occur. nonisolated(unsafe) suppresses the Swift 6 diagnostic.
                    nonisolated(unsafe) var resumed = false

                    newListener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            if !resumed {
                                resumed = true
                                continuation.resume()
                            }
                        case let .failed(error):
                            if !resumed {
                                resumed = true
                                continuation.resume(throwing: error)
                            }
                        case .cancelled:
                            if !resumed {
                                resumed = true
                                continuation.resume(throwing: DebugServerError.cancelled)
                            }
                        default:
                            break
                        }
                    }

                    newListener.newConnectionHandler = { [weak self] connection in
                        Task { @MainActor in
                            guard let self, self.listener != nil || self.startingListener != nil else {
                                connection.cancel()
                                return
                            }
                            self.activeConnections[ObjectIdentifier(connection)] = connection
                            self.handleConnection(connection)
                        }
                    }

                    newListener.start(queue: .main)
                }
            } catch {
                newListener.cancel()
                throw error
            }

            guard startingListener === newListener else {
                newListener.cancel()
                throw DebugServerError.cancelled
            }
            listener = newListener
            let boundPort = port
            logger.info("Debug server listening on 127.0.0.1:\(boundPort)")
        }

        func stop() {
            for connection in activeConnections.values {
                connection.cancel()
            }
            activeConnections.removeAll()
            startingListener?.cancel()
            startingListener = nil
            listener?.cancel()
            listener = nil
            logger.info("Debug server stopped")
        }

        // MARK: - Routing

        func addRoute(_ method: String, _ path: String, handler: @Sendable @escaping (HTTPRequest) -> HTTPResponse) {
            routes[path, default: [:]][method] = handler
        }

        // MARK: - Built-in Routes

        private func registerBuiltInRoutes() {
            let capturedStartTime = startTime
            addRoute("GET", "/health") { _ in
                let uptime = ContinuousClock.now - capturedStartTime
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
                return Self.jsonResponse(statusCode: 200, body: [
                    "status": "ok",
                    "version": version,
                    "uptime": uptime.seconds
                ])
            }
        }

        // MARK: - Connection Handling

        private func finishConnection(_ connection: NWConnection) {
            activeConnections.removeValue(forKey: ObjectIdentifier(connection))
            connection.cancel()
        }

        private func handleConnection(_ connection: NWConnection) {
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    // Only .failed needs cleanup here — .cancelled is covered by stop() via activeConnections.removeAll()
                    guard case .failed = state else { return }
                    if let self {
                        self.finishConnection(connection)
                    } else {
                        connection.cancel()
                    }
                }
            }

            connection.start(queue: .main)

            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, _, error in
                Task { @MainActor in
                    guard let self else {
                        connection.cancel()
                        return
                    }

                    if let error {
                        self.logger.debug("Connection receive error: \(error)")
                        self.finishConnection(connection)
                        return
                    }

                    guard let data = content, let request = HTTPParser.parse(data) else {
                        self.sendResponse(
                            Self.jsonResponse(statusCode: 400, body: ["error": "Bad request"]),
                            on: connection)
                        return
                    }

                    let response: HTTPResponse = if
                        let pathRoutes = self.routes[request.path],
                        let handler = pathRoutes[request.method] {
                        handler(request)
                    } else {
                        Self.jsonResponse(statusCode: 404, body: ["error": "Not found"])
                    }

                    self.sendResponse(response, on: connection)
                }
            }
        }

        private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
            var header = "HTTP/1.1 \(response.statusCode) \(response.statusText)\r\n"
            header += "Content-Type: application/json\r\n"
            header += "Content-Length: \(response.body.count)\r\n"
            header += "Connection: close\r\n"
            header += "\r\n"

            var payload = Data(header.utf8)
            payload.append(response.body)

            connection.send(content: payload, completion: .contentProcessed { [weak self, logger] error in
                if let error {
                    logger.debug("Connection send error: \(error)")
                }
                Task { @MainActor in
                    if let self {
                        self.finishConnection(connection)
                    } else {
                        connection.cancel()
                    }
                }
            })
        }

        // MARK: - Helpers

        nonisolated private static func jsonResponse(statusCode: Int, body: [String: any Sendable]) -> HTTPResponse {
            guard let data = try? JSONSerialization.data(withJSONObject: body) else {
                assertionFailure("DebugServer: failed to serialize JSON response")
                return HTTPResponse(statusCode: 500, body: Data("{\"error\":\"serialization failed\"}".utf8))
            }
            return HTTPResponse(statusCode: statusCode, body: data)
        }
    }

    // MARK: - Errors

    enum DebugServerError: LocalizedError {
        case invalidPort(UInt16)
        case cancelled

        var errorDescription: String? {
            switch self {
            case let .invalidPort(port):
                "Invalid port: \(port)"
            case .cancelled:
                "Server start cancelled"
            }
        }
    }

    // MARK: - Duration Extension

    private extension Duration {
        var seconds: Double {
            let (secs, attosecs) = components
            return Double(secs) + Double(attosecs) * 1e-18
        }
    }

#endif

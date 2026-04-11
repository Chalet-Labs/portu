#if DEBUG

    import Foundation
    import Network
    import os

    @MainActor
    final class DebugServer {
        private let port: UInt16
        private var listener: NWListener?
        private var routes: [String: [String: @Sendable (HTTPRequest) -> HTTPResponse]] = [:]
        private let startTime = ContinuousClock.now
        private let logger = Logger(subsystem: "com.portu.app", category: "DebugServer")

        init(port: UInt16 = 9999) {
            self.port = port
            registerBuiltInRoutes()
        }

        // MARK: - Lifecycle

        func start() async throws {
            let params = NWParameters.tcp

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw DebugServerError.invalidPort(port)
            }
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

            let newListener = try NWListener(using: params)
            listener = newListener

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                nonisolated(unsafe) var resumed = false

                newListener.stateUpdateHandler = { [weak self] state in
                    guard self != nil else { return }
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
                        break
                    default:
                        break
                    }
                }

                newListener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        self?.handleConnection(connection)
                    }
                }

                newListener.start(queue: .main)
            }

            let boundPort = port
            logger.info("Debug server listening on 127.0.0.1:\(boundPort)")
        }

        func stop() {
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

        private func handleConnection(_ connection: NWConnection) {
            connection.start(queue: .main)

            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, _, error in
                Task { @MainActor in
                    guard let self else {
                        connection.cancel()
                        return
                    }

                    if error != nil {
                        connection.cancel()
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

            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }

        // MARK: - Helpers

        nonisolated private static func jsonResponse(statusCode: Int, body: [String: any Sendable]) -> HTTPResponse {
            let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
            return HTTPResponse(statusCode: statusCode, body: data)
        }
    }

    // MARK: - Errors

    enum DebugServerError: LocalizedError {
        case invalidPort(UInt16)

        var errorDescription: String? {
            switch self {
            case let .invalidPort(port):
                "Invalid port: \(port)"
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

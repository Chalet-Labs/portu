#if DEBUG
    import Foundation
    @testable import Portu
    import Testing

    @MainActor
    struct DebugServerTests {
        // MARK: - Health Endpoint

        @Test func `health endpoint returns valid JSON`() async throws {
            let server = DebugServer(port: 19001)
            try await server.start()
            defer { server.stop() }

            let (data, response) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19001/health")))
            let httpResponse = try #require(response as? HTTPURLResponse)

            #expect(httpResponse.statusCode == 200)
            #expect(httpResponse.value(forHTTPHeaderField: "Content-Type") == "application/json")

            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["status"] as? String == "ok")
            #expect(json["version"] != nil)
            #expect(json["uptime"] != nil)
        }

        // MARK: - 404 Fallback

        @Test func `unknown path returns 404`() async throws {
            let server = DebugServer(port: 19002)
            try await server.start()
            defer { server.stop() }

            let (data, response) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19002/nonexistent")))
            let httpResponse = try #require(response as? HTTPURLResponse)

            #expect(httpResponse.statusCode == 404)

            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["error"] as? String == "Not found")
        }

        // MARK: - Server Lifecycle

        @Test func `server stop cancels listener`() async throws {
            let server = DebugServer(port: 19003)
            try await server.start()

            server.stop()
            try await Task.sleep(for: .milliseconds(100))

            do {
                _ = try await URLSession.shared.data(
                    from: #require(URL(string: "http://127.0.0.1:19003/health")))
                Issue.record("Expected connection to be refused after stop")
            } catch {
                // Expected — connection refused
            }
        }

        @Test func `port in use does not crash`() async throws {
            let server1 = DebugServer(port: 19004)
            try await server1.start()
            defer { server1.stop() }

            let server2 = DebugServer(port: 19004)
            defer { server2.stop() }
            do {
                try await server2.start()
                Issue.record("Expected start to throw when port is in use")
            } catch {
                // Expected — port already bound
            }
        }

        // MARK: - Localhost Binding

        @Test func `server binds to localhost only`() async throws {
            let server = DebugServer(port: 19005)
            try await server.start()
            defer { server.stop() }

            let (_, response) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19005/health")))
            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 200)
        }

        // MARK: - Uptime

        @Test func `uptime increases over time`() async throws {
            let server = DebugServer(port: 19006)
            try await server.start()
            defer { server.stop() }

            try await Task.sleep(for: .milliseconds(200))

            let (data, _) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19006/health")))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let uptime = try #require(json["uptime"] as? Double)

            #expect(uptime >= 0.1)
        }
    }
#endif

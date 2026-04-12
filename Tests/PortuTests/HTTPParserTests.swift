#if DEBUG
    import Foundation
    @testable import Portu
    import Testing

    struct HTTPParserTests {
        // MARK: - Valid GET Requests

        @Test func `parses simple GET request`() {
            let raw = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request != nil)
            #expect(request?.method == "GET")
            #expect(request?.path == "/health")
            #expect(request?.queryParams.isEmpty == true)
        }

        @Test func `parses GET with query parameters`() {
            let raw = "GET /accounts?type=wallet&chain=ethereum HTTP/1.1\r\nHost: localhost\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request != nil)
            #expect(request?.path == "/accounts")
            #expect(request?.queryParams["type"] == "wallet")
            #expect(request?.queryParams["chain"] == "ethereum")
        }

        @Test func `parses GET with single query parameter`() {
            let raw = "GET /search?q=bitcoin HTTP/1.1\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request?.path == "/search")
            #expect(request?.queryParams["q"] == "bitcoin")
        }

        @Test func `parses GET with empty query value`() {
            let raw = "GET /filter?active= HTTP/1.1\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request?.path == "/filter")
            #expect(request?.queryParams["active"]?.isEmpty == true)
        }

        @Test func `parses root path`() {
            let raw = "GET / HTTP/1.1\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request?.method == "GET")
            #expect(request?.path == "/")
        }

        // MARK: - Other HTTP Methods

        @Test func `parses POST method`() {
            let raw = "POST /data HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request?.method == "POST")
            #expect(request?.path == "/data")
        }

        @Test func `parses DELETE method`() {
            let raw = "DELETE /accounts/1 HTTP/1.1\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request?.method == "DELETE")
            #expect(request?.path == "/accounts/1")
        }

        // MARK: - Malformed Requests

        @Test func `returns nil for empty data`() {
            let request = HTTPParser.parse(Data())
            #expect(request == nil)
        }

        @Test func `returns nil for garbage data`() {
            let request = HTTPParser.parse(Data("not http at all".utf8))
            #expect(request == nil)
        }

        @Test func `returns nil for missing path`() {
            let request = HTTPParser.parse(Data("GET\r\n\r\n".utf8))
            #expect(request == nil)
        }

        @Test func `returns nil for missing HTTP version`() {
            let request = HTTPParser.parse(Data("GET /health\r\n\r\n".utf8))
            #expect(request == nil)
        }

        @Test func `returns nil for invalid HTTP version`() {
            let request = HTTPParser.parse(Data("GET / GARBAGE\r\n\r\n".utf8))
            #expect(request == nil)
        }

        @Test func `returns nil for missing header terminator`() {
            // No \r\n\r\n — incomplete request
            let request = HTTPParser.parse(Data("GET /health HTTP/1.1\r\nHost: localhost".utf8))
            #expect(request == nil)
        }

        // MARK: - Edge Cases

        @Test func `handles URL-encoded query values`() {
            let raw = "GET /search?q=hello%20world HTTP/1.1\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request?.path == "/search")
            // Raw value — decoding is caller's responsibility
            #expect(request?.queryParams["q"] == "hello%20world")
        }

        @Test func `handles query key without value`() {
            let raw = "GET /filter?verbose HTTP/1.1\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request?.path == "/filter")
            // Key present with empty string value
            #expect(request?.queryParams["verbose"]?.isEmpty == true)
        }

        @Test func `handles deeply nested path`() {
            let raw = "GET /api/v1/accounts/123/positions HTTP/1.1\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request?.path == "/api/v1/accounts/123/positions")
        }

        @Test func `rejects request line longer than 8192 bytes`() {
            let longPath = String(repeating: "a", count: 8200)
            let raw = "GET /\(longPath) HTTP/1.1\r\n\r\n"
            let request = HTTPParser.parse(Data(raw.utf8))

            #expect(request == nil)
        }
    }
#endif

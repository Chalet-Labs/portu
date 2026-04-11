import Foundation
@testable import Portu
import Testing

struct NetworkLogEntryTests {
    @Test func `entry captures all metadata`() {
        let entry = NetworkLogEntry(
            id: UUID(),
            timestamp: Date(),
            url: "https://api.example.com/v1/data",
            method: "POST",
            statusCode: 200,
            responseSizeBytes: 1024,
            elapsed: 0.5,
            headers: ["Content-Type": "application/json"])
        #expect(entry.url == "https://api.example.com/v1/data")
        #expect(entry.method == "POST")
        #expect(entry.statusCode == 200)
        #expect(entry.responseSizeBytes == 1024)
        #expect(entry.elapsed == 0.5)
        #expect(entry.errorDescription == nil)
    }

    @Test func `redacts authorization header`() {
        let redacted = NetworkLogEntry.redactHeaders(["Authorization": "Bearer sk-12345"])
        #expect(redacted["Authorization"] == "***")
    }

    @Test func `redacts API key header`() {
        let redacted = NetworkLogEntry.redactHeaders(["API-Key": "my-secret-key"])
        #expect(redacted["API-Key"] == "***")
    }

    @Test func `redacts API sign header`() {
        let redacted = NetworkLogEntry.redactHeaders(["API-Sign": "hmac-signature"])
        #expect(redacted["API-Sign"] == "***")
    }

    @Test func `redacts API secret header`() {
        let redacted = NetworkLogEntry.redactHeaders(["API-Secret": "my-secret"])
        #expect(redacted["API-Secret"] == "***")
    }

    @Test func `preserves non sensitive headers`() {
        let redacted = NetworkLogEntry.redactHeaders([
            "Content-Type": "application/json",
            "Accept": "text/html"
        ])
        #expect(redacted["Content-Type"] == "application/json")
        #expect(redacted["Accept"] == "text/html")
    }

    @Test func `mixed sensitive and non sensitive headers`() {
        let redacted = NetworkLogEntry.redactHeaders([
            "Authorization": "Bearer token",
            "Content-Type": "application/json",
            "API-Key": "key123"
        ])
        #expect(redacted["Authorization"] == "***")
        #expect(redacted["Content-Type"] == "application/json")
        #expect(redacted["API-Key"] == "***")
    }

    @Test func `case insensitive header redaction`() {
        let redacted = NetworkLogEntry.redactHeaders([
            "authorization": "Bearer token",
            "api-key": "key"
        ])
        #expect(redacted["authorization"] == "***")
        #expect(redacted["api-key"] == "***")
    }

    @Test func `redacts cookie headers`() {
        let redacted = NetworkLogEntry.redactHeaders([
            "Cookie": "session=abc123",
            "Set-Cookie": "token=xyz",
            "Accept": "text/html"
        ])
        #expect(redacted["Cookie"] == "***")
        #expect(redacted["Set-Cookie"] == "***")
        #expect(redacted["Accept"] == "text/html")
    }

    @Test func `empty headers returns empty`() {
        let redacted = NetworkLogEntry.redactHeaders([:])
        #expect(redacted.isEmpty)
    }

    @Test func `entry round trips codable`() throws {
        let entry = NetworkLogEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1000),
            url: "https://example.com",
            method: "GET",
            statusCode: 200,
            responseSizeBytes: 512,
            elapsed: 1.0,
            headers: ["Content-Type": "application/json"])
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(NetworkLogEntry.self, from: data)
        #expect(decoded.id == entry.id)
        #expect(decoded.url == entry.url)
        #expect(decoded.method == entry.method)
        #expect(decoded.statusCode == entry.statusCode)
        #expect(decoded.responseSizeBytes == entry.responseSizeBytes)
    }

    @Test func `nil status code for failed request`() {
        let entry = NetworkLogEntry(
            id: UUID(),
            timestamp: Date(),
            url: "https://example.com",
            method: "GET",
            statusCode: nil,
            responseSizeBytes: 0,
            elapsed: 0.1,
            headers: [:],
            errorDescription: "The Internet connection appears to be offline.")
        #expect(entry.statusCode == nil)
        #expect(entry.errorDescription == "The Internet connection appears to be offline.")
    }
}

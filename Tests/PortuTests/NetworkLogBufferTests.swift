import Foundation
@testable import Portu
import Testing

struct NetworkLogBufferTests {
    private func makeEntry(
        timestamp: Date = Date(),
        url: String = "https://example.com",
        method: String = "GET",
        statusCode: Int? = 200,
        responseSizeBytes: Int = 100,
        elapsed: TimeInterval = 0.5,
        headers: [String: String] = [:]) -> NetworkLogEntry {
        NetworkLogEntry(
            id: UUID(),
            timestamp: timestamp,
            url: url,
            method: method,
            statusCode: statusCode,
            responseSizeBytes: responseSizeBytes,
            elapsed: elapsed,
            headers: headers)
    }

    @Test func `empty buffer returns empty array`() async {
        let buffer = NetworkLogBuffer(capacity: 10)
        let entries = await buffer.entries()
        #expect(entries.isEmpty)
        #expect(await buffer.entryCount == 0)
    }

    @Test func `append and retrieve single entry`() async {
        let buffer = NetworkLogBuffer(capacity: 10)
        let entry = makeEntry(url: "https://example.com/api")
        await buffer.append(entry)
        let entries = await buffer.entries()
        #expect(entries.count == 1)
        #expect(entries[0].url == "https://example.com/api")
        #expect(await buffer.entryCount == 1)
    }

    @Test func `append multiple entries`() async {
        let buffer = NetworkLogBuffer(capacity: 10)
        for i in 0 ..< 5 {
            await buffer.append(makeEntry(url: "https://example.com/\(i)"))
        }
        let entries = await buffer.entries()
        #expect(entries.count == 5)
        #expect(await buffer.entryCount == 5)
    }

    @Test func `overflow evicts oldest`() async {
        let buffer = NetworkLogBuffer(capacity: 3)
        await buffer.append(makeEntry(url: "https://first.com"))
        await buffer.append(makeEntry(url: "https://second.com"))
        await buffer.append(makeEntry(url: "https://third.com"))
        await buffer.append(makeEntry(url: "https://fourth.com"))

        let entries = await buffer.entries()
        #expect(entries.count == 3)
        #expect(entries[0].url == "https://second.com")
        #expect(entries[1].url == "https://third.com")
        #expect(entries[2].url == "https://fourth.com")
        #expect(await buffer.entryCount == 3)
    }

    @Test func `overflow wraps multiple times`() async {
        let buffer = NetworkLogBuffer(capacity: 3)
        for i in 0 ..< 10 {
            await buffer.append(makeEntry(url: "https://example.com/\(i)"))
        }
        let entries = await buffer.entries()
        #expect(entries.count == 3)
        #expect(entries[0].url == "https://example.com/7")
        #expect(entries[1].url == "https://example.com/8")
        #expect(entries[2].url == "https://example.com/9")
    }

    @Test func `entries filtered by since`() async {
        let buffer = NetworkLogBuffer(capacity: 10)
        let base = Date(timeIntervalSince1970: 1000)
        await buffer.append(makeEntry(timestamp: base, url: "https://old.com"))
        await buffer.append(makeEntry(timestamp: base.addingTimeInterval(10), url: "https://mid.com"))
        await buffer.append(makeEntry(timestamp: base.addingTimeInterval(20), url: "https://new.com"))

        let entries = await buffer.entries(since: base.addingTimeInterval(5))
        #expect(entries.count == 2)
        #expect(entries[0].url == "https://mid.com")
        #expect(entries[1].url == "https://new.com")
    }

    @Test func `entries with limit`() async {
        let buffer = NetworkLogBuffer(capacity: 10)
        for i in 0 ..< 5 {
            await buffer.append(makeEntry(url: "https://example.com/\(i)"))
        }
        let entries = await buffer.entries(limit: 2)
        #expect(entries.count == 2)
        #expect(entries[0].url == "https://example.com/3")
        #expect(entries[1].url == "https://example.com/4")
    }

    @Test func `entries with since and limit`() async {
        let buffer = NetworkLogBuffer(capacity: 10)
        let base = Date(timeIntervalSince1970: 1000)
        for i in 0 ..< 5 {
            await buffer.append(makeEntry(
                timestamp: base.addingTimeInterval(Double(i) * 10),
                url: "https://example.com/\(i)"))
        }
        // since=15 keeps entries at t=20,30,40 → limit=2 takes last two
        let entries = await buffer.entries(since: base.addingTimeInterval(15), limit: 2)
        #expect(entries.count == 2)
        #expect(entries[0].url == "https://example.com/3")
        #expect(entries[1].url == "https://example.com/4")
    }

    @Test func `limit zero returns empty`() async {
        let buffer = NetworkLogBuffer(capacity: 10)
        await buffer.append(makeEntry(url: "https://example.com"))
        let entries = await buffer.entries(limit: 0)
        #expect(entries.isEmpty)
    }

    @Test func `clear resets buffer`() async {
        let buffer = NetworkLogBuffer(capacity: 10)
        for _ in 0 ..< 5 {
            await buffer.append(makeEntry())
        }
        await buffer.clear()
        #expect(await buffer.entryCount == 0)
        #expect(await buffer.entries().isEmpty)
    }

    @Test func `limit larger than count returns all`() async {
        let buffer = NetworkLogBuffer(capacity: 10)
        await buffer.append(makeEntry(url: "https://only.com"))
        let entries = await buffer.entries(limit: 100)
        #expect(entries.count == 1)
        #expect(entries[0].url == "https://only.com")
    }
}

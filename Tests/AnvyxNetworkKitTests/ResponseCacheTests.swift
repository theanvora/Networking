//
//  ResponseCacheTests.swift
//  Networking
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
@testable import AnvyxNetworkKit

/// Serves a scripted sequence of responses and records every request.
private actor ScriptedTransport: HTTPTransport {
    struct Scripted { let status: Int; let headers: [String: String]; let body: Data }

    private var queue: [Scripted]
    private(set) var requests: [URLRequest] = []

    init(_ queue: [Scripted]) { self.queue = queue }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let scripted = queue.isEmpty ? Scripted(status: 200, headers: [:], body: Data()) : queue.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: scripted.status,
                                       httpVersion: nil, headerFields: scripted.headers)!
        return (scripted.body, response)
    }
}

private struct Item: Decodable, Equatable { let id: Int; let name: String }

final class ResponseCacheTests: XCTestCase {

    private let base = URL(string: "https://example.com")!
    private func body(_ name: String) -> Data { #"{"id":1,"name":"\#(name)"}"#.data(using: .utf8)! }

    func testFreshResponseServedFromCacheWithoutNetwork() async throws {
        let transport = ScriptedTransport([
            .init(status: 200, headers: ["ETag": "v1", "Cache-Control": "max-age=60"], body: body("a")),
        ])
        let client = APIClient(baseURL: base, transport: transport, cache: InMemoryResponseCache())
        let endpoint = Endpoint<Item>(path: "items/1")

        let first: Item = try await client.send(endpoint)
        let second: Item = try await client.send(endpoint)

        XCTAssertEqual(first, Item(id: 1, name: "a"))
        XCTAssertEqual(second, first)
        let count = await transport.requests.count
        XCTAssertEqual(count, 1, "the fresh second GET must not hit the network")
    }

    func testStaleRevalidatesAnd304ReturnsCachedData() async throws {
        let transport = ScriptedTransport([
            .init(status: 200, headers: ["ETag": "v1", "Cache-Control": "no-cache"], body: body("a")),
            .init(status: 304, headers: [:], body: Data()),
        ])
        let client = APIClient(baseURL: base, transport: transport, cache: InMemoryResponseCache())
        let endpoint = Endpoint<Item>(path: "items/1")

        _ = try await client.send(endpoint) as Item
        let second: Item = try await client.send(endpoint)

        XCTAssertEqual(second, Item(id: 1, name: "a"), "304 serves the cached body")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "If-None-Match"), "v1")
    }

    func testRevalidationWith200UpdatesCache() async throws {
        let transport = ScriptedTransport([
            .init(status: 200, headers: ["ETag": "v1", "Cache-Control": "no-cache"], body: body("a")),
            .init(status: 200, headers: ["ETag": "v2", "Cache-Control": "no-cache"], body: body("b")),
        ])
        let client = APIClient(baseURL: base, transport: transport, cache: InMemoryResponseCache())
        let endpoint = Endpoint<Item>(path: "items/1")

        let first: Item = try await client.send(endpoint)
        let second: Item = try await client.send(endpoint)

        XCTAssertEqual(first, Item(id: 1, name: "a"))
        XCTAssertEqual(second, Item(id: 1, name: "b"), "a fresh 200 replaces the cached body")
    }

    func testNoStoreIsNotCached() async throws {
        let transport = ScriptedTransport([
            .init(status: 200, headers: ["Cache-Control": "no-store"], body: body("a")),
            .init(status: 200, headers: ["Cache-Control": "no-store"], body: body("b")),
        ])
        let client = APIClient(baseURL: base, transport: transport, cache: InMemoryResponseCache())
        let endpoint = Endpoint<Item>(path: "items/1")

        _ = try await client.send(endpoint) as Item
        let second: Item = try await client.send(endpoint)

        XCTAssertEqual(second, Item(id: 1, name: "b"))
        let count = await transport.requests.count
        XCTAssertEqual(count, 2, "no-store responses must always hit the network")
    }

    func testFreshnessExpiryRevalidates() async {
        // maxAge 0 (no-cache) → the entry is never fresh, so a validator is sent next time.
        let entry = CachedResponse(data: Data(), etag: "e", lastModified: nil, storedAt: Date(), maxAge: 0)
        XCTAssertFalse(entry.isFresh(now: Date()))
        let live = CachedResponse(data: Data(), etag: nil, lastModified: nil, storedAt: Date(), maxAge: 60)
        XCTAssertTrue(live.isFresh(now: Date()))
    }
}

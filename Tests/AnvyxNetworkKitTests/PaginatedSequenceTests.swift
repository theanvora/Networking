//
//  PaginatedSequenceTests.swift
//  Networking
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
@testable import AnvyxNetworkKit

/// Serves pre-scripted pages (cursor = page index) and counts fetches.
private actor PageServer {
    private let pages: [Page<Int, Int>]
    private(set) var fetchCount = 0

    init(_ pages: [Page<Int, Int>]) { self.pages = pages }

    func page(after cursor: Int?) -> Page<Int, Int> {
        fetchCount += 1
        return pages[cursor ?? 0]
    }
}

final class PaginatedSequenceTests: XCTestCase {

    func testCollectsAllElementsInOrder() async throws {
        let server = PageServer([
            Page(elements: [1, 2], next: 1),
            Page(elements: [3, 4], next: 2),
            Page(elements: [5], next: nil),
        ])
        let sequence = PaginatedSequence<Int, Int> { await server.page(after: $0) }

        let all = try await sequence.collect()
        XCTAssertEqual(all, [1, 2, 3, 4, 5])
        let fetches = await server.fetchCount
        XCTAssertEqual(fetches, 3)
    }

    func testStopsFetchingOnceEnoughConsumed() async throws {
        let server = PageServer([
            Page(elements: [1, 2], next: 1),
            Page(elements: [3, 4], next: 2),
            Page(elements: [5], next: nil),
        ])
        let sequence = PaginatedSequence<Int, Int> { await server.page(after: $0) }

        var collected: [Int] = []
        for try await value in sequence.prefix(3) { collected.append(value) }

        XCTAssertEqual(collected, [1, 2, 3])
        let fetches = await server.fetchCount
        XCTAssertEqual(fetches, 2, "the third page is never fetched")
    }

    func testEmptyResultYieldsNothing() async throws {
        let server = PageServer([Page(elements: [], next: nil)])
        let sequence = PaginatedSequence<Int, Int> { await server.page(after: $0) }

        let all = try await sequence.collect()
        XCTAssertTrue(all.isEmpty)
        let fetches = await server.fetchCount
        XCTAssertEqual(fetches, 1)
    }

    func testSkipsEmptyIntermediatePage() async throws {
        let server = PageServer([
            Page(elements: [1], next: 1),
            Page(elements: [], next: 2),   // empty, but more follow
            Page(elements: [2], next: nil),
        ])
        let sequence = PaginatedSequence<Int, Int> { await server.page(after: $0) }

        let all = try await sequence.collect()
        XCTAssertEqual(all, [1, 2])
        let fetches = await server.fetchCount
        XCTAssertEqual(fetches, 3)
    }

    func testPropagatesFetchErrors() async {
        struct Boom: Error {}
        let sequence = PaginatedSequence<Int, Int> { _ in throw Boom() }

        do {
            _ = try await sequence.collect()
            XCTFail("expected the fetch error to propagate")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }
}

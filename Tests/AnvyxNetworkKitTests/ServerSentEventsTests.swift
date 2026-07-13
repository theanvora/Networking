//
//  ServerSentEventsTests.swift
//  Networking
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
@testable import AnvyxNetworkKit

final class ServerSentEventsTests: XCTestCase {

    // MARK: - SSEParser (pure state machine)

    func testParsesSimpleDataEvent() {
        var parser = SSEParser()
        XCTAssertNil(parser.consume("data: hello"))
        let event = parser.consume("")
        XCTAssertEqual(event, SSEEvent(data: "hello"))
    }

    func testJoinsMultipleDataLines() {
        var parser = SSEParser()
        _ = parser.consume("data: line1")
        _ = parser.consume("data: line2")
        XCTAssertEqual(parser.consume("")?.data, "line1\nline2")
    }

    func testEventTypeAndId() {
        var parser = SSEParser()
        _ = parser.consume("event: update")
        _ = parser.consume("id: 42")
        _ = parser.consume("data: x")
        let event = parser.consume("")
        XCTAssertEqual(event?.event, "update")
        XCTAssertEqual(event?.id, "42")
        XCTAssertEqual(event?.data, "x")
    }

    func testCommentAndDatalessBlockDoNotDispatch() {
        var parser = SSEParser()
        XCTAssertNil(parser.consume(": a comment"))
        XCTAssertNil(parser.consume("event: ping"))   // no data
        XCTAssertNil(parser.consume(""), "a block with no data must not dispatch")
    }

    func testLastEventIdPersistsAcrossEvents() {
        var parser = SSEParser()
        _ = parser.consume("id: 7")
        _ = parser.consume("data: a")
        let first = parser.consume("")
        _ = parser.consume("data: b")           // no new id
        let second = parser.consume("")
        XCTAssertEqual(first?.id, "7")
        XCTAssertEqual(second?.id, "7")
    }

    func testRetryField() {
        var parser = SSEParser()
        _ = parser.consume("retry: 3000")
        _ = parser.consume("data: x")
        XCTAssertEqual(parser.consume("")?.retry, 3000)
    }

    func testValueWithoutSpaceAfterColon() {
        var parser = SSEParser()
        _ = parser.consume("data:nospace")
        XCTAssertEqual(parser.consume("")?.data, "nospace")
    }

    // MARK: - Async stream

    func testStreamYieldsEventsInOrder() async throws {
        let lines = ["data: one", "", "event: tick", "data: two", "", "data: three"]  // last one unterminated
        let source = AsyncStream<String> { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }

        var collected: [SSEEvent] = []
        for try await event in ServerSentEvents.events(from: source) {
            collected.append(event)
        }

        XCTAssertEqual(collected, [
            SSEEvent(data: "one"),
            SSEEvent(event: "tick", data: "two"),
            SSEEvent(data: "three"),   // flushed at end of stream
        ])
    }
}

//
//  ProgressTransferTests.swift
//  Networking
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
@testable import AnvyxNetworkKit

final class ProgressTransferTests: XCTestCase {

    private func byteStream(_ payload: [UInt8]) -> AsyncStream<UInt8> {
        AsyncStream { continuation in
            for byte in payload { continuation.yield(byte) }
            continuation.finish()
        }
    }

    // MARK: - TransferProgress math

    func testFractionMath() {
        XCTAssertEqual(TransferProgress(completedBytes: 0, totalBytes: 100).fraction, 0)
        XCTAssertEqual(TransferProgress(completedBytes: 50, totalBytes: 100).fraction, 0.5)
        XCTAssertEqual(TransferProgress(completedBytes: 100, totalBytes: 100).fraction, 1)
        XCTAssertEqual(TransferProgress(completedBytes: 150, totalBytes: 100).fraction, 1, "caps at 1")
        XCTAssertNil(TransferProgress(completedBytes: 10, totalBytes: -1).fraction, "unknown total")
    }

    // MARK: - Download core

    func testEmitsMonotonicProgressThenData() async throws {
        let payload = [UInt8](repeating: 0xAB, count: 1000)
        let events = ProgressTransfer.events(from: byteStream(payload), expectedLength: 1000)

        var lastFraction = 0.0
        var progressCount = 0
        var finalData: Data?
        for try await event in events {
            switch event {
            case .progress(let p):
                progressCount += 1
                let fraction = try XCTUnwrap(p.fraction)
                XCTAssertGreaterThanOrEqual(fraction, lastFraction, "progress must not go backwards")
                lastFraction = fraction
            case .finished(let data):
                finalData = data
            }
        }

        XCTAssertEqual(finalData, Data(payload))
        XCTAssertEqual(lastFraction, 1.0, accuracy: 0.0001)
        XCTAssertGreaterThan(progressCount, 1, "throttled progress should still report multiple times")
    }

    func testUnknownLengthStillFinishesWithData() async throws {
        let payload = [UInt8](repeating: 7, count: 300)
        let events = ProgressTransfer.events(from: byteStream(payload), expectedLength: -1)

        var finalData: Data?
        for try await event in events {
            if case .progress(let p) = event { XCTAssertNil(p.fraction) }
            if case .finished(let data) = event { finalData = data }
        }
        XCTAssertEqual(finalData?.count, 300)
    }

    func testEmptyPayloadEmitsFinishedEmpty() async throws {
        let events = ProgressTransfer.events(from: byteStream([]), expectedLength: 0)
        var finished = false
        for try await event in events {
            if case .finished(let data) = event { finished = true; XCTAssertTrue(data.isEmpty) }
        }
        XCTAssertTrue(finished)
    }
}

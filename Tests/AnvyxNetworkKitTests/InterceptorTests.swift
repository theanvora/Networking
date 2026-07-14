//
//  InterceptorTests.swift
//  Networking
//
//  Created by AnhPT on 14/07/2026.
//

import XCTest
@testable import AnvyxNetworkKit

final class InterceptorTests: XCTestCase {
    private func request() -> URLRequest { URLRequest(url: URL(string: "https://example.com")!) }

    func testBearerTokenAdapterSetsHeader() async throws {
        let adapter = BearerTokenAdapter { "abc123" }
        let adapted = try await adapter.adapt(request())
        XCTAssertEqual(adapted.value(forHTTPHeaderField: "Authorization"), "Bearer abc123")
    }

    func testBearerTokenAdapterSkipsWhenNoToken() async throws {
        let adapter = BearerTokenAdapter { nil }
        let adapted = try await adapter.adapt(request())
        XCTAssertNil(adapted.value(forHTTPHeaderField: "Authorization"))
    }

    func testRetrierRetriesRetryableStatus() async {
        let retrier = ExponentialBackoffRetrier(maxAttempts: 3, baseDelay: 0.1)
        let decision = await retrier.shouldRetry(request(), dueTo: .unacceptableStatus(code: 503, data: Data()), attempt: 0)
        XCTAssertEqual(decision, .retry(afterDelay: 0.1))
    }

    func testRetrierStopsOnNonRetryableStatus() async {
        let retrier = ExponentialBackoffRetrier(maxAttempts: 3)
        let decision = await retrier.shouldRetry(request(), dueTo: .unacceptableStatus(code: 404, data: Data()), attempt: 0)
        XCTAssertEqual(decision, .doNotRetry)
    }

    func testRetrierStopsAtMaxAttempts() async {
        let retrier = ExponentialBackoffRetrier(maxAttempts: 2, baseDelay: 0.1)
        let decision = await retrier.shouldRetry(request(), dueTo: .unacceptableStatus(code: 500, data: Data()), attempt: 5)
        XCTAssertEqual(decision, .doNotRetry)
    }
}

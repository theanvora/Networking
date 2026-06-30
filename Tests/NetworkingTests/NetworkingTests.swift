//
//  NetworkingTests.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import XCTest
@testable import Networking

final class NetworkingTests: XCTestCase {
    func testEndpointDefaults() {
        let endpoint = Endpoint<EmptyResponse>(path: "ping")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertTrue(endpoint.query.isEmpty)
        XCTAssertNil(endpoint.body)
    }

    func testJSONBodyHelper() {
        struct Payload: Encodable { let name: String }
        let endpoint = Endpoint<EmptyResponse>(path: "users", method: .post)
            .body(json: Payload(name: "anvora"))
        XCTAssertNotNil(endpoint.body)
        XCTAssertEqual(endpoint.headers["Content-Type"], "application/json")
    }
}

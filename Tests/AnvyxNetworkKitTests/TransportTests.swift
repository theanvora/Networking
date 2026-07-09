//
//  TransportTests.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import XCTest
@testable import AnvyxNetworkKit

/// A stub transport — proves the client is testable without hitting the network.
private struct StubTransport: HTTPTransport {
    let status: Int
    let body: Data
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

private struct Item: Decodable, Equatable { let id: Int; let name: String }

final class TransportTests: XCTestCase {
    func testDecodesInjectedResponse() async throws {
        let json = #"{"id":1,"name":"anvora"}"#.data(using: .utf8)!
        let client = APIClient(baseURL: URL(string: "https://example.com")!,
                               transport: StubTransport(status: 200, body: json))
        let item: Item = try await client.send(Endpoint(path: "items/1"))
        XCTAssertEqual(item, Item(id: 1, name: "anvora"))
    }

    func testThrowsOnUnacceptableStatus() async {
        let client = APIClient(baseURL: URL(string: "https://example.com")!,
                               transport: StubTransport(status: 404, body: Data()))
        do {
            let _: Item = try await client.send(Endpoint(path: "missing"))
            XCTFail("expected error")
        } catch let error as APIError {
            guard case .unacceptableStatus(let code, _) = error else { return XCTFail("wrong error") }
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("unexpected error type")
        }
    }
}

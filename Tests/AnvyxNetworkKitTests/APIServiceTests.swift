//
//  APIServiceTests.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import XCTest
@testable import AnvyxNetworkKit

private struct FixedTransport: HTTPTransport {
    let body: Data
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

private struct User: Decodable, Equatable { let id: Int; let name: String }

/// The narrow protocol a view model would depend on (Clean Architecture port).
private protocol UserProviding: Sendable {
    func user(id: Int) async throws -> User
}

/// Concrete service layered on `APIClient` via `APIService`.
private struct UserService: APIService, UserProviding {
    let client: APIClient
    func user(id: Int) async throws -> User {
        try await send(Endpoint(path: "users/\(id)"))
    }
}

final class APIServiceTests: XCTestCase {
    func testDomainServiceReturnsDecodedModel() async throws {
        let json = #"{"id":7,"name":"anvora"}"#.data(using: .utf8)!
        let client = APIClient(baseURL: URL(string: "https://example.com")!, transport: FixedTransport(body: json))
        let service: UserProviding = UserService(client: client)

        let user = try await service.user(id: 7)
        XCTAssertEqual(user, User(id: 7, name: "anvora"))
    }
}

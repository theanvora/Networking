//
//  APIService.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import Foundation

/// Base for a domain service layer over `APIClient`. Conform a per-feature service
/// to it, expose typed domain methods, and forward through `send` / `data` without
/// repeating client plumbing.
///
/// ```swift
/// struct UserService: APIService {
///     let client: APIClient
///     func user(id: Int) async throws -> User {
///         try await send(Endpoint(path: "users/\(id)"))
///     }
/// }
/// ```
///
/// Call sites should depend on a narrow protocol they own (e.g. `UserProviding`),
/// which the concrete service conforms to — keeping view models decoupled from
/// `APIClient` and easy to stub in tests.
public protocol APIService: Sendable {
    var client: APIClient { get }
}

public extension APIService {
    @discardableResult
    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        try await client.send(endpoint)
    }

    /// Raw response bytes (images, files, non-JSON).
    func data<Response>(for endpoint: Endpoint<Response>) async throws -> Data {
        try await client.sendForData(endpoint)
    }
}

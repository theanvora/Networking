//
//  HTTP.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// A typed description of a single request. Generic over the `Response` it decodes to.
public struct Endpoint<Response: Decodable>: Sendable {
    public var path: String
    public var method: HTTPMethod
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data?

    public init(
        path: String,
        method: HTTPMethod = .get,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// Convenience for a JSON-encoded body.
    public func body<T: Encodable>(json value: T, encoder: JSONEncoder = JSONEncoder()) -> Endpoint {
        var copy = self
        copy.body = try? encoder.encode(value)
        copy.headers["Content-Type"] = "application/json"
        return copy
    }
}

public enum APIError: Error, Sendable {
    case invalidURL
    case transport(String)
    case unacceptableStatus(code: Int, data: Data)
    case decoding(String)
}

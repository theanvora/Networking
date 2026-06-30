//
//  APIClient.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import Foundation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Networking", category: "network")

/// A small async/await HTTP client. Configure it with a base URL and optional
/// default headers (e.g. an auth token), then send typed `Endpoint`s.
public actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private var defaultHeaders: [String: String]

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        defaultHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
        self.defaultHeaders = defaultHeaders
    }

    /// Update a default header sent with every request (pass `nil` to remove it).
    public func setHeader(_ value: String?, for field: String) {
        defaultHeaders[field] = value
    }

    @discardableResult
    public func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try makeRequest(for: endpoint)
        log.debug("→ \(endpoint.method.rawValue) \(request.url?.absoluteString ?? endpoint.path)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            log.error("← \(http.statusCode) \(endpoint.path)")
            throw APIError.unacceptableStatus(code: http.statusCode, data: data)
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func makeRequest<Response>(for endpoint: Endpoint<Response>) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidURL }

        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        for (field, value) in defaultHeaders { request.setValue(value, forHTTPHeaderField: field) }
        for (field, value) in endpoint.headers { request.setValue(value, forHTTPHeaderField: field) }
        return request
    }
}

/// Use as the `Response` type for endpoints that return no body.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}

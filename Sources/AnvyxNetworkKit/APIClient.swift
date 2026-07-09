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
    private let transport: HTTPTransport
    private let decoder: JSONDecoder
    private var defaultHeaders: [String: String]
    private let adapters: [RequestAdapter]
    private let retrier: RequestRetrier?
    private let logsCURL: Bool

    public init(
        baseURL: URL,
        transport: HTTPTransport = URLSession.shared,
        decoder: JSONDecoder = JSONDecoder(),
        defaultHeaders: [String: String] = [:],
        adapters: [RequestAdapter] = [],
        retrier: RequestRetrier? = nil,
        logsCURL: Bool = false
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.decoder = decoder
        self.defaultHeaders = defaultHeaders
        self.adapters = adapters
        self.retrier = retrier
        self.logsCURL = logsCURL
    }

    /// Update a default header sent with every request (pass `nil` to remove it).
    public func setHeader(_ value: String?, for field: String) {
        defaultHeaders[field] = value
    }

    @discardableResult
    public func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let data = try await sendForData(endpoint)

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    /// Sends the request and returns the raw body, applying adapters and the
    /// retry policy. Use this when you need bytes (images, files) rather than JSON.
    public func sendForData<Response>(_ endpoint: Endpoint<Response>) async throws -> Data {
        var request = try makeRequest(for: endpoint)
        for adapter in adapters {
            request = try await adapter.adapt(request)
        }

        if logsCURL {
            log.debug("\(request.curlString)")
        }

        var attempt = 0
        while true {
            log.debug("→ \(endpoint.method.rawValue) \(request.url?.absoluteString ?? endpoint.path)")
            do {
                let (data, response) = try await transport.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw APIError.unacceptableStatus(code: http.statusCode, data: data)
                }
                return data
            } catch {
                let apiError = (error as? APIError) ?? .transport(error.localizedDescription)
                guard let retrier,
                      case let .retry(delay) = await retrier.shouldRetry(request, dueTo: apiError, attempt: attempt)
                else {
                    log.error("✗ \(endpoint.path): \(String(describing: apiError))")
                    throw apiError
                }
                attempt += 1
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
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

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
    private let cache: ResponseCache?
    private let logsCURL: Bool

    public init(
        baseURL: URL,
        transport: HTTPTransport = URLSession.shared,
        decoder: JSONDecoder = JSONDecoder(),
        defaultHeaders: [String: String] = [:],
        adapters: [RequestAdapter] = [],
        retrier: RequestRetrier? = nil,
        cache: ResponseCache? = nil,
        logsCURL: Bool = false
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.decoder = decoder
        self.defaultHeaders = defaultHeaders
        self.adapters = adapters
        self.retrier = retrier
        self.cache = cache
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

        // HTTP response cache (GET only): serve fresh entries without a round-trip;
        // revalidate stale ones with ETag / Last-Modified.
        let cacheKey = endpoint.method == .get ? request.url?.absoluteString : nil
        var cachedEntry: CachedResponse?
        if let cache, let cacheKey, let entry = await cache.cached(for: cacheKey) {
            if entry.isFresh(now: Date()) {
                return entry.data
            }
            cachedEntry = entry
            if let etag = entry.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let lastModified = entry.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        }

        if logsCURL {
            log.debug("\(request.curlString)")
        }

        var attempt = 0
        while true {
            log.debug("→ \(endpoint.method.rawValue) \(request.url?.absoluteString ?? endpoint.path)")
            do {
                let (data, response) = try await transport.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 200

                if status == 304, let cachedEntry {
                    if let cache, let cacheKey, let http {
                        await cache.store(Self.cacheEntry(data: cachedEntry.data, http: http, fallback: cachedEntry) ?? cachedEntry,
                                          for: cacheKey)
                    }
                    return cachedEntry.data
                }
                if !(200..<300).contains(status) {
                    throw APIError.unacceptableStatus(code: status, data: data)
                }
                if let cache, let cacheKey, let http, let entry = Self.cacheEntry(data: data, http: http, fallback: nil) {
                    await cache.store(entry, for: cacheKey)
                }
                return data
            } catch {
                let apiError = (error as? APIError) ?? .transport(error.localizedDescription)
                let effectiveRetrier = endpoint.retrier ?? retrier
                guard let effectiveRetrier,
                      case let .retry(delay) = await effectiveRetrier.shouldRetry(request, dueTo: apiError, attempt: attempt)
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

    /// Build a cache entry from a response's headers, falling back to a prior
    /// entry's validators (e.g. on a bare `304`). Returns `nil` when the response
    /// is not cacheable (`no-store`, or no validator and no lifetime).
    private static func cacheEntry(data: Data, http: HTTPURLResponse, fallback: CachedResponse?) -> CachedResponse? {
        let cacheControl = http.value(forHTTPHeaderField: "Cache-Control")?.lowercased()
        if cacheControl?.contains("no-store") == true { return nil }

        let etag = http.value(forHTTPHeaderField: "ETag") ?? fallback?.etag
        let lastModified = http.value(forHTTPHeaderField: "Last-Modified") ?? fallback?.lastModified
        var maxAge = parseMaxAge(cacheControl)
        if maxAge == nil, cacheControl?.contains("no-cache") == true { maxAge = 0 }
        if maxAge == nil { maxAge = fallback?.maxAge }

        guard etag != nil || lastModified != nil || maxAge != nil else { return nil }
        return CachedResponse(data: data, etag: etag, lastModified: lastModified, storedAt: Date(), maxAge: maxAge)
    }

    private static func parseMaxAge(_ cacheControl: String?) -> TimeInterval? {
        guard let cacheControl else { return nil }
        for directive in cacheControl.split(separator: ",") {
            let token = directive.trimmingCharacters(in: .whitespaces)
            if token.hasPrefix("max-age=") {
                return TimeInterval(token.dropFirst("max-age=".count))
            }
        }
        return nil
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

//
//  Interceptor.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import Foundation

/// Mutates every outgoing request — the place to inject auth tokens, common
/// headers, signing, etc.
public protocol RequestAdapter: Sendable {
    func adapt(_ request: URLRequest) async throws -> URLRequest
}

/// Decides whether a failed request should be retried.
public protocol RequestRetrier: Sendable {
    func shouldRetry(
        _ request: URLRequest,
        dueTo error: APIError,
        attempt: Int
    ) async -> RetryDecision
}

public enum RetryDecision: Sendable, Equatable {
    case doNotRetry
    case retry(afterDelay: TimeInterval)
}

/// Injects a bearer token (resolved lazily each request, so token refresh works).
public struct BearerTokenAdapter: RequestAdapter {
    private let token: @Sendable () async -> String?
    public init(token: @escaping @Sendable () async -> String?) {
        self.token = token
    }
    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        guard let token = await token() else { return request }
        var copy = request
        copy.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return copy
    }
}

/// Retries transport errors and configurable status codes with exponential backoff.
public struct ExponentialBackoffRetrier: RequestRetrier {
    private let maxAttempts: Int
    private let baseDelay: TimeInterval
    private let retryableStatuses: Set<Int>

    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 0.5,
        retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.retryableStatuses = retryableStatuses
    }

    public func shouldRetry(_ request: URLRequest, dueTo error: APIError, attempt: Int) async -> RetryDecision {
        guard attempt < maxAttempts - 1 else { return .doNotRetry }
        let retryable: Bool
        switch error {
        case .transport:
            retryable = true
        case .unacceptableStatus(let code, _):
            retryable = retryableStatuses.contains(code)
        case .invalidURL, .decoding:
            retryable = false
        }
        guard retryable else { return .doNotRetry }
        let delay = baseDelay * pow(2, Double(attempt))
        return .retry(afterDelay: delay)
    }
}

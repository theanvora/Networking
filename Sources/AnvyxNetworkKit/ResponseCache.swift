//
//  ResponseCache.swift
//  Networking
//
//  Created by AnhPT on 13/07/2026.
//

import Foundation

/// A stored HTTP response plus the metadata needed to reuse or revalidate it.
public struct CachedResponse: Sendable, Equatable {
    public let data: Data
    /// `ETag` validator, for `If-None-Match` revalidation.
    public let etag: String?
    /// `Last-Modified` validator, for `If-Modified-Since` revalidation.
    public let lastModified: String?
    /// When the entry was stored.
    public let storedAt: Date
    /// `Cache-Control: max-age` lifetime in seconds (`0` = always revalidate).
    public let maxAge: TimeInterval?

    public init(data: Data, etag: String?, lastModified: String?, storedAt: Date, maxAge: TimeInterval?) {
        self.data = data
        self.etag = etag
        self.lastModified = lastModified
        self.storedAt = storedAt
        self.maxAge = maxAge
    }

    /// `true` while still within its freshness lifetime — servable without a network round-trip.
    public func isFresh(now: Date) -> Bool {
        guard let maxAge else { return false }
        return now < storedAt.addingTimeInterval(maxAge)
    }
}

/// Storage backend for ``APIClient``'s HTTP response cache. Supply your own to
/// persist across launches; ``InMemoryResponseCache`` is the default.
public protocol ResponseCache: Sendable {
    func cached(for key: String) async -> CachedResponse?
    func store(_ response: CachedResponse, for key: String) async
    func removeAll() async
}

/// A simple in-memory ``ResponseCache`` with oldest-first eviction at capacity.
public actor InMemoryResponseCache: ResponseCache {
    private var storage: [String: CachedResponse] = [:]
    private let capacity: Int

    public init(capacity: Int = 100) {
        self.capacity = max(1, capacity)
    }

    public func cached(for key: String) -> CachedResponse? { storage[key] }

    public func store(_ response: CachedResponse, for key: String) {
        if storage[key] == nil, storage.count >= capacity,
           let oldest = storage.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            storage[oldest] = nil
        }
        storage[key] = response
    }

    public func removeAll() { storage.removeAll() }
}

//
//  ImageLoader.swift
//  Networking
//
//  Created by AnhPT on 03/07/2026.
//

import Foundation
import UIKit

public enum ImageLoaderError: Error {
    case decodingFailed
}

/// A pluggable image cache (memory-backed by default).
public protocol ImageCaching: Sendable {
    func image(for url: URL) -> UIImage?
    func store(_ image: UIImage, for url: URL)
}

/// `NSCache`-backed image cache (thread-safe).
public final class DefaultImageCache: ImageCaching, @unchecked Sendable {
    private let cache = NSCache<NSURL, UIImage>()

    public init(countLimit: Int = 200) {
        cache.countLimit = countLimit
    }

    public func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    public func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// Async remote image loader with an in-memory cache and **in-flight
/// de-duplication** (concurrent requests for the same URL share one download).
public actor ImageLoader {
    public static let shared = ImageLoader()

    private let cache: ImageCaching
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    public init(cache: ImageCaching = DefaultImageCache(), session: URLSession = .shared) {
        self.cache = cache
        self.session = session
    }

    /// Load `url`, returning a cached image immediately when available.
    public func image(from url: URL) async throws -> UIImage {
        if let cached = cache.image(for: url) { return cached }
        if let existing = inFlight[url] { return try await existing.value }

        let task = Task { () -> UIImage in
            let (data, _) = try await session.data(from: url)
            guard let image = UIImage(data: data) else { throw ImageLoaderError.decodingFailed }
            return image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }

        let image = try await task.value
        cache.store(image, for: url)
        return image
    }

    /// Warm the cache for `urls` (ignores failures).
    public func prefetch(_ urls: [URL]) {
        for url in urls where cache.image(for: url) == nil {
            Task { try? await image(from: url) }
        }
    }
}

@MainActor
public extension UIImageView {
    /// Load a remote image into this view (placeholder shown while loading).
    func setImage(from url: URL?, placeholder: UIImage? = nil, loader: ImageLoader = .shared) {
        image = placeholder
        guard let url else { return }
        Task { [weak self] in
            if let loaded = try? await loader.image(from: url) { self?.image = loaded }
        }
    }
}

//
//  ImageLoaderTests.swift
//  Networking
//
//  Created by AnhPT on 03/07/2026.
//

import XCTest
import UIKit
@testable import AnvyxNetworkKit

final class ImageLoaderTests: XCTestCase {

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    func testDefaultCacheStoreAndRetrieve() {
        let cache = DefaultImageCache()
        let url = URL(string: "https://example.com/a.png")!
        XCTAssertNil(cache.image(for: url))
        cache.store(image(), for: url)
        XCTAssertNotNil(cache.image(for: url))
    }

    func testLoaderReturnsCachedImage() async throws {
        let cache = DefaultImageCache()
        let url = URL(string: "https://example.com/cached.png")!
        cache.store(image(), for: url)
        let loader = ImageLoader(cache: cache)
        let result = try await loader.image(from: url)   // served from cache, no network
        XCTAssertEqual(result.size, CGSize(width: 4, height: 4))
    }
}

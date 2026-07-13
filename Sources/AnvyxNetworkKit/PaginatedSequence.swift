//
//  PaginatedSequence.swift
//  Networking
//
//  Created by AnhPT on 13/07/2026.
//

/// One page of results plus the cursor to fetch the next one (`nil` = last page).
public struct Page<Element: Sendable, Cursor: Sendable>: Sendable {
    public let elements: [Element]
    public let next: Cursor?

    public init(elements: [Element], next: Cursor?) {
        self.elements = elements
        self.next = next
    }
}

/// A lazy `AsyncSequence` over a cursor-paginated resource: it fetches the next
/// page only when the consumer has drained the current one, and stops when a page
/// reports no `next` cursor. Empty intermediate pages are skipped.
///
/// ```swift
/// let feed = PaginatedSequence<Post, String> { cursor in
///     let page: PostPage = try await client.send(Endpoint(path: "posts", query: cursor.map { ["after": $0] } ?? [:]))
///     return Page(elements: page.items, next: page.nextCursor)
/// }
/// for try await post in feed { render(post) }        // streams page-by-page
/// let firstTwenty = try await feed.prefix(20)        // fetches only what it needs
/// ```
public struct PaginatedSequence<Element: Sendable, Cursor: Sendable>: AsyncSequence, Sendable {
    private let fetch: @Sendable (Cursor?) async throws -> Page<Element, Cursor>

    /// - Parameter fetch: loads the page after `cursor` (`nil` for the first page).
    public init(_ fetch: @escaping @Sendable (Cursor?) async throws -> Page<Element, Cursor>) {
        self.fetch = fetch
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(fetch: fetch)
    }

    /// Eagerly collect every element across all pages.
    public func collect() async throws -> [Element] {
        try await reduce(into: []) { $0.append($1) }
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let fetch: @Sendable (Cursor?) async throws -> Page<Element, Cursor>
        private var buffer: [Element] = []
        private var index = 0
        private var cursor: Cursor?
        private var started = false
        private var finished = false

        init(fetch: @escaping @Sendable (Cursor?) async throws -> Page<Element, Cursor>) {
            self.fetch = fetch
        }

        public mutating func next() async throws -> Element? {
            while index >= buffer.count {
                if finished { return nil }
                if started, cursor == nil {          // drained the last page
                    finished = true
                    return nil
                }
                let page = try await fetch(cursor)
                started = true
                buffer = page.elements
                index = 0
                cursor = page.next
                if buffer.isEmpty, page.next == nil {   // empty last page
                    finished = true
                    return nil
                }
                // empty-but-more falls through and loops to fetch again.
            }
            defer { index += 1 }
            return buffer[index]
        }
    }
}

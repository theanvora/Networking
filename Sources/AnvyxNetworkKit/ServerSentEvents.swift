//
//  ServerSentEvents.swift
//  Networking
//
//  Created by AnhPT on 13/07/2026.
//

import Foundation

/// One dispatched Server-Sent Event.
public struct SSEEvent: Sendable, Equatable {
    /// The `event:` type, or `nil` for the default (`"message"`).
    public var event: String?
    /// The `data:` payload — multiple `data:` lines joined with `\n`.
    public var data: String
    /// The last-seen `id:` (persists across events per the SSE spec).
    public var id: String?
    /// The `retry:` reconnection hint in milliseconds, when present.
    public var retry: Int?

    public init(event: String? = nil, data: String, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }
}

/// An incremental parser for the `text/event-stream` line protocol (WHATWG SSE).
/// Feed it lines (newline stripped); it returns a completed ``SSEEvent`` on a blank
/// line, or `nil` while still accumulating. Pure and synchronous — fully testable.
public struct SSEParser {
    private var eventType: String?
    private var dataLines: [String] = []
    private var lastID: String?
    private var retry: Int?

    public init() {}

    public mutating func consume(_ line: String) -> SSEEvent? {
        if line.isEmpty {                              // blank line → dispatch
            defer { eventType = nil; dataLines = []; retry = nil }
            guard !dataLines.isEmpty else { return nil }   // no data → no message event
            return SSEEvent(event: eventType, data: dataLines.joined(separator: "\n"), id: lastID, retry: retry)
        }
        if line.hasPrefix(":") { return nil }          // comment

        let (field, value) = Self.parseField(line)
        switch field {
        case "event": eventType = value
        case "data":  dataLines.append(value)
        case "id" where !value.contains("\0"): lastID = value
        case "retry": if let milliseconds = Int(value) { retry = milliseconds }
        default: break                                 // unknown field ignored
        }
        return nil
    }

    /// Split `field: value`, dropping a single optional space after the colon.
    /// A line with no colon is a field name with an empty value.
    private static func parseField(_ line: String) -> (field: String, value: String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        let field = String(line[line.startIndex..<colon])
        var valueStart = line.index(after: colon)
        if valueStart < line.endIndex, line[valueStart] == " " {
            valueStart = line.index(after: valueStart)
        }
        return (field, String(line[valueStart...]))
    }
}

/// Consumes a `text/event-stream` response as an `AsyncThrowingStream` of
/// ``SSEEvent``, bridging `URLSession.bytes`.
///
/// ```swift
/// for try await event in ServerSentEvents.stream(for: request) {
///     handle(event.event ?? "message", event.data)
/// }
/// ```
public enum ServerSentEvents {

    public static func stream(
        for request: URLRequest,
        session: URLSession = .shared
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        var prepared = request
        if prepared.value(forHTTPHeaderField: "Accept") == nil {
            prepared.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        let finalRequest = prepared
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, _) = try await session.bytes(for: finalRequest)
                    try await pump(bytes.lines, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Parse events from any line sequence — the testable entry point.
    public static func events<Lines: AsyncSequence & Sendable>(
        from lines: Lines
    ) -> AsyncThrowingStream<SSEEvent, Error> where Lines.Element == String {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await pump(lines, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func pump<Lines: AsyncSequence>(
        _ lines: Lines,
        into continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    ) async throws where Lines.Element == String {
        var parser = SSEParser()
        for try await line in lines {
            if let event = parser.consume(line) { continuation.yield(event) }
        }
        if let event = parser.consume("") { continuation.yield(event) }   // flush a final unterminated event
    }
}

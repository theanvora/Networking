//
//  ProgressTransfer.swift
//  Networking
//
//  Created by AnhPT on 13/07/2026.
//

import Foundation

/// A byte-transfer progress sample.
public struct TransferProgress: Sendable, Equatable {
    public let completedBytes: Int64
    /// Expected total, or `-1` when the server doesn't advertise a length.
    public let totalBytes: Int64

    public init(completedBytes: Int64, totalBytes: Int64) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    /// Fraction complete in `0...1`, or `nil` when the total is unknown.
    public var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
}

/// An event in a progress-reporting transfer.
public enum TransferEvent: Sendable {
    case progress(TransferProgress)
    case finished(Data)
}

/// Progress-reporting downloads and uploads, bridging `URLSession` to an
/// `AsyncThrowingStream` of ``TransferEvent`` — no delegate wrangling at the call site.
///
/// ```swift
/// for try await event in ProgressTransfer.download(for: request) {
///     switch event {
///     case .progress(let p): setProgress(p.fraction ?? 0)
///     case .finished(let data): save(data)
///     }
/// }
/// ```
public enum ProgressTransfer {

    // MARK: - Download (via URLSession.bytes)

    /// Stream download progress, then the full body. Cancelling the consuming task
    /// cancels the transfer.
    public static func download(
        for request: URLRequest,
        session: URLSession = .shared
    ) -> AsyncThrowingStream<TransferEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    try await drain(bytes, expectedLength: response.expectedContentLength, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Upload (via task delegate)

    /// Upload `data`, streaming send progress then the server's response body.
    public static func upload(
        _ request: URLRequest,
        from data: Data,
        session: URLSession = .shared
    ) -> AsyncThrowingStream<TransferEvent, Error> {
        AsyncThrowingStream { continuation in
            let delegate = UploadProgressDelegate { continuation.yield(.progress($0)) }
            let task = Task {
                do {
                    let (responseData, _) = try await session.upload(for: request, from: data, delegate: delegate)
                    continuation.yield(.finished(responseData))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Testable core

    /// Accumulate `bytes`, emitting throttled progress (~1% steps) then `.finished`.
    /// Exposed for tests to drive with a mock byte sequence.
    static func events<Bytes: AsyncSequence & Sendable>(
        from bytes: Bytes,
        expectedLength: Int64
    ) -> AsyncThrowingStream<TransferEvent, Error> where Bytes.Element == UInt8 {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await drain(bytes, expectedLength: expectedLength, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func drain<Bytes: AsyncSequence>(
        _ bytes: Bytes,
        expectedLength: Int64,
        into continuation: AsyncThrowingStream<TransferEvent, Error>.Continuation
    ) async throws where Bytes.Element == UInt8 {
        var data = Data()
        if expectedLength > 0 { data.reserveCapacity(Int(expectedLength)) }
        var lastReported: Int64 = -1
        let step = expectedLength > 0 ? max(1, expectedLength / 100) : 65_536

        for try await byte in bytes {
            data.append(byte)
            let count = Int64(data.count)
            if count - lastReported >= step {
                lastReported = count
                continuation.yield(.progress(TransferProgress(completedBytes: count, totalBytes: expectedLength)))
            }
        }
        continuation.yield(.progress(TransferProgress(completedBytes: Int64(data.count), totalBytes: expectedLength)))
        continuation.yield(.finished(data))
    }
}

/// Bridges `URLSessionTaskDelegate` send-progress callbacks to a closure.
/// `@unchecked Sendable`: no mutable state; the closure is `@Sendable`.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (TransferProgress) -> Void

    init(onProgress: @escaping @Sendable (TransferProgress) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(TransferProgress(completedBytes: totalBytesSent, totalBytes: totalBytesExpectedToSend))
    }
}

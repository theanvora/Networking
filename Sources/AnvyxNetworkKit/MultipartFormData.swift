//
//  MultipartFormData.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import Foundation

/// Builds a `multipart/form-data` body for file uploads. Small bodies can be
/// materialized in memory with ``encoded()``; large uploads can be **streamed to
/// a temp file** with ``write(to:)`` / ``encodedFileURL()`` (files are copied in
/// chunks, never fully loaded), then sent via `URLSession.upload(fromFile:)`.
///
/// ```swift
/// var form = MultipartFormData()
/// form.addField(name: "title", value: "Scan")
/// form.addFile(name: "file", filename: "doc.pdf", mimeType: "application/pdf", fileURL: url)
/// let bodyFile = try form.encodedFileURL()   // streamed, low memory
/// ```
public struct MultipartFormData {
    public let boundary: String
    private var parts: [Part] = []

    private enum Part {
        case field(name: String, value: String)
        case data(name: String, filename: String, mimeType: String, data: Data)
        case file(name: String, filename: String, mimeType: String, url: URL)
    }

    public init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(name: String, value: String) {
        parts.append(.field(name: name, value: value))
    }

    /// Add a file part from in-memory data.
    public mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        parts.append(.data(name: name, filename: filename, mimeType: mimeType, data: data))
    }

    /// Add a file part **by reference** — its bytes are only read when the body is
    /// written, and streamed in chunks (never fully loaded into memory).
    public mutating func addFile(name: String, filename: String, mimeType: String, fileURL: URL) {
        parts.append(.file(name: name, filename: filename, mimeType: mimeType, url: fileURL))
    }

    // MARK: - In-memory

    /// The finalized body in memory (file-URL parts are loaded here).
    public func encoded() -> Data {
        var body = Data()
        for part in parts { body.append(header(for: part)); body.append(payload(for: part)); body.append(crlf) }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    // MARK: - Streamed to disk

    /// Write the finalized body to `destination`, streaming file-URL parts in
    /// chunks so large uploads don't spike memory.
    public func write(to destination: URL, chunkSize: Int = 1 << 16) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        for part in parts {
            try output.write(contentsOf: header(for: part))
            switch part {
            case .field, .data:
                try output.write(contentsOf: payload(for: part))
            case .file(_, _, _, let url):
                let input = try FileHandle(forReadingFrom: url)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
                    try output.write(contentsOf: chunk)
                }
            }
            try output.write(contentsOf: crlf)
        }
        try output.write(contentsOf: Data("--\(boundary)--\r\n".utf8))
    }

    /// Stream the body to a unique temp file and return its URL (delete it after
    /// the upload completes).
    public func encodedFileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-\(UUID().uuidString).tmp")
        try write(to: url)
        return url
    }

    // MARK: - Encoding helpers

    private var crlf: Data { Data("\r\n".utf8) }

    private func header(for part: Part) -> Data {
        switch part {
        case .field(let name, _):
            Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8)
        case .data(let name, let filename, let mimeType, _),
             .file(let name, let filename, let mimeType, _):
            Data(("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; " +
                  "filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n").utf8)
        }
    }

    private func payload(for part: Part) -> Data {
        switch part {
        case .field(_, let value): Data(value.utf8)
        case .data(_, _, _, let data): data
        case .file(_, _, _, let url): (try? Data(contentsOf: url)) ?? Data()
        }
    }
}

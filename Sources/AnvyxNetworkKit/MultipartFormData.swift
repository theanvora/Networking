//
//  MultipartFormData.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import Foundation

/// Builds a `multipart/form-data` body for file uploads.
///
/// ```swift
/// var form = MultipartFormData()
/// form.addField(name: "title", value: "Scan")
/// form.addFile(name: "file", filename: "doc.pdf", mimeType: "application/pdf", data: pdfData)
/// let endpoint = Endpoint<Resp>(path: "upload", method: .post,
///                               headers: ["Content-Type": form.contentType], body: form.encoded())
/// ```
public struct MultipartFormData {
    public let boundary: String
    private var body = Data()

    public init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    public mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// Returns the finalized body (appends the closing boundary).
    public func encoded() -> Data {
        var copy = body
        copy.append(Data("--\(boundary)--\r\n".utf8))
        return copy
    }

    private mutating func append(_ string: String) {
        body.append(Data(string.utf8))
    }
}

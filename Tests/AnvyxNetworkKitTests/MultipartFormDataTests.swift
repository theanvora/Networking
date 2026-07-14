//
//  MultipartFormDataTests.swift
//  Networking
//
//  Created by AnhPT on 14/07/2026.
//

import XCTest
@testable import AnvyxNetworkKit

final class MultipartFormDataTests: XCTestCase {
    func testInMemoryAndStreamedBodiesMatch() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("part-\(UUID().uuidString).txt")
        try Data("FILEBYTES".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var form = MultipartFormData(boundary: "B")
        form.addField(name: "title", value: "Scan")
        form.addFile(name: "f", filename: "d.txt", mimeType: "text/plain", fileURL: fileURL)

        let inMemory = form.encoded()
        let streamedURL = try form.encodedFileURL()
        defer { try? FileManager.default.removeItem(at: streamedURL) }
        let streamed = try Data(contentsOf: streamedURL)

        XCTAssertEqual(inMemory, streamed, "streamed body must match the in-memory body")

        let text = try XCTUnwrap(String(data: streamed, encoding: .utf8))
        XCTAssertTrue(text.contains("--B\r\n"))
        XCTAssertTrue(text.contains("name=\"title\""))
        XCTAssertTrue(text.contains("filename=\"d.txt\""))
        XCTAssertTrue(text.contains("Content-Type: text/plain"))
        XCTAssertTrue(text.contains("FILEBYTES"))
        XCTAssertTrue(text.hasSuffix("--B--\r\n"))
    }

    func testDataAndFilePartsAreEquivalent() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("eq-\(UUID().uuidString).bin")
        let bytes = Data((0..<5000).map { UInt8($0 % 256) })
        try bytes.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var a = MultipartFormData(boundary: "X")
        a.addFile(name: "f", filename: "b.bin", mimeType: "application/octet-stream", data: bytes)
        var b = MultipartFormData(boundary: "X")
        b.addFile(name: "f", filename: "b.bin", mimeType: "application/octet-stream", fileURL: fileURL)

        XCTAssertEqual(a.encoded(), b.encoded())
    }
}

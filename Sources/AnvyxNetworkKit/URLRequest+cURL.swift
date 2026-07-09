//
//  URLRequest+cURL.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import Foundation

public extension URLRequest {
    /// A copy-pasteable `curl` command for this request — invaluable when
    /// debugging or sharing a failing call.
    var curlString: String {
        var parts = ["curl"]
        if let method = httpMethod, method != "GET" {
            parts.append("-X \(method)")
        }
        allHTTPHeaderFields?
            .sorted { $0.key < $1.key }
            .forEach { parts.append("-H '\($0): \($1)'") }
        if let body = httpBody, let string = String(data: body, encoding: .utf8), !string.isEmpty {
            parts.append("-d '\(string)'")
        }
        if let url { parts.append("'\(url.absoluteString)'") }
        return parts.joined(separator: " ")
    }
}

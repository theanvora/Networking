//
//  HTTPTransport.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import Foundation

/// The seam between `APIClient` and the network. Depending on this abstraction
/// (instead of `URLSession` directly) lets you inject a stub in tests — no real
/// requests, no flakiness.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

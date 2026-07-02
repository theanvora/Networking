# Networking

A tiny, dependency-free async/await HTTP client for iOS, built around typed endpoints.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/iOS-26%2B-blue.svg)](https://developer.apple.com/ios/)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)

## Features

- **Typed endpoints** — `Endpoint<Response>` describes a request and its decoded result.
- **`async/await` client** — an `actor`-based `APIClient` with default headers and JSON decoding.
- **Structured errors** — `APIError` distinguishes transport, status, and decoding failures.

## Installation

```swift
.package(url: "https://github.com/anvyxhq/Networking.git", from: "1.0.0")
```

## Usage

```swift
import Networking

struct User: Decodable { let id: Int; let name: String }

let client = APIClient(baseURL: URL(string: "https://api.example.com")!)

// GET
let user: User = try await client.send(Endpoint(path: "users/1"))

// POST with a JSON body
struct NewUser: Encodable { let name: String }
let created: User = try await client.send(
    Endpoint<User>(path: "users", method: .post).body(json: NewUser(name: "Anvora"))
)

// Auth header for every request
await client.setHeader("Bearer \(token)", for: "Authorization")
```

## Requirements

- iOS 26.0+ · Swift 5.9+

## License

MIT

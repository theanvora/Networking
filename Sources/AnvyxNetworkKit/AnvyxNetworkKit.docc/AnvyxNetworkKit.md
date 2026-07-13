# ``AnvyxNetworkKit``

An actor-based HTTP client: typed endpoints, adapters & retriers, response caching,
pagination, progress transfers, Server-Sent Events, and image loading.

## Overview

``APIClient`` is an `actor` you configure once (base URL, default headers, adapters,
retrier, cache) then call with typed ``Endpoint``s. Everything is `Sendable` and
testable through the ``HTTPTransport`` seam.

```swift
let client = APIClient(baseURL: url, adapters: [BearerTokenAdapter { await token() }],
                       cache: InMemoryResponseCache())
let user: User = try await client.send(Endpoint(path: "me"))
for try await event in ServerSentEvents.stream(for: request) { handle(event) }
```

## Topics

### Client
- ``APIClient``
- ``Endpoint``
- ``HTTPMethod``
- ``APIError``
- ``HTTPTransport``

### Adapters & Retry
- ``RequestAdapter``
- ``BearerTokenAdapter``
- ``RequestRetrier``
- ``ExponentialBackoffRetrier``
- ``RetryDecision``

### Caching
- ``ResponseCache``
- ``InMemoryResponseCache``
- ``CachedResponse``

### Pagination & Streaming
- ``PaginatedSequence``
- ``Page``
- ``ProgressTransfer``
- ``TransferProgress``
- ``TransferEvent``
- ``ServerSentEvents``
- ``SSEEvent``
- ``SSEParser``

### Uploads & Images
- ``MultipartFormData``
- ``ImageLoader``
- ``ImageCaching``

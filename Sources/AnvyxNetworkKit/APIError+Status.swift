//
//  APIError+Status.swift
//  Networking
//
//  Created by AnhPT on 02/07/2026.
//

import Foundation

public extension APIError {
    /// The HTTP status code, if this error came from an unacceptable response.
    var statusCode: Int? {
        if case .unacceptableStatus(let code, _) = self { return code }
        return nil
    }

    /// The response body that accompanied an unacceptable status.
    var responseData: Data? {
        if case .unacceptableStatus(_, let data) = self { return data }
        return nil
    }

    var isUnauthorized: Bool { statusCode == 401 || statusCode == 403 }
    var isNotFound: Bool { statusCode == 404 }
    var isRateLimited: Bool { statusCode == 429 }
    var isServerError: Bool { (statusCode ?? 0) >= 500 }
}

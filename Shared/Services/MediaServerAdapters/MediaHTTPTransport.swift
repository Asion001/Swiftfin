//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public struct MediaHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol MediaHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> MediaHTTPResponse
}

/// Credentials never follow redirects. Users configure the final server URL explicitly.
public final class URLSessionMediaTransport: NSObject, MediaHTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private let session: URLSession

    override public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
        super.init()
    }

    public func send(_ request: URLRequest) async throws -> MediaHTTPResponse {
        let (data, response) = try await session.data(for: request, delegate: self)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return MediaHTTPResponse(data: data, statusCode: response.statusCode)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

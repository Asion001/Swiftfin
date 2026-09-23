//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Repairs `CollectionType` values that Jellyfin-compatible servers send
/// outside Jellyfin's own set.
///
/// Silo's Jellyfin listener passes its native library types straight through
/// (`movie`, `mixed`, `audiobooks`, ...). The SDK decodes the field into a
/// closed enum, so a single such library fails the entire response — the
/// library list, that library's own item and every ancestor chain through it —
/// with "The data couldn't be read because it isn't in the correct format."
enum CollectionTypeCompatibility {

    // MARK: - Values

    private static let collectionTypes = Set(CollectionType.allCases.map(\.rawValue))

    /// `/Library/VirtualFolders` decodes into `CollectionTypeOptions`, which
    /// has `mixed` but none of the view-only types.
    private static let virtualFolderTypes = Set(CollectionTypeOptions.allCases.map(\.rawValue))

    private static let pattern = try! NSRegularExpression(
        pattern: #""CollectionType"\s*:\s*"((?:[^"\\]|\\.)*)""#
    )

    private static let marker = Data(#""CollectionType""#.utf8)

    /// The Jellyfin value closest to `value`, or `nil` when there is none and
    /// the field is better left empty, which is how Jellyfin itself describes a
    /// mixed library.
    static func replacement(for value: String, isVirtualFolder: Bool) -> String? {
        let validTypes = isVirtualFolder ? virtualFolderTypes : collectionTypes
        let lowercased = value.lowercased()

        let candidate: String = switch lowercased {
        case "movie":
            "movies"
        case "series", "show", "shows", "tv", "tvshow":
            "tvshows"
        case "audiobook", "audiobooks", "book", "ebook", "ebooks", "manga", "comic", "comics":
            "books"
        case "boxset", "collection", "collections":
            "boxsets"
        case "homevideo":
            "homevideos"
        case "musicvideo":
            "musicvideos"
        case "photo":
            "photos"
        case "playlist":
            "playlists"
        default:
            lowercased
        }

        return validTypes.contains(candidate) ? candidate : nil
    }

    /// `data` with every unsupported `CollectionType` replaced, or `nil` when
    /// nothing needed changing, so a Jellyfin server's responses are never
    /// rewritten.
    static func normalized(_ data: Data, isVirtualFolder: Bool) -> Data? {
        guard data.range(of: marker) != nil,
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        let validTypes = isVirtualFolder ? virtualFolderTypes : collectionTypes
        let result = NSMutableString(string: text)
        var didChange = false

        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: result.length))

        // Replace from the end so earlier ranges stay valid.
        for match in matches.reversed() {
            let value = result.substring(with: match.range(at: 1))
            guard !validTypes.contains(value) else { continue }

            let literal = replacement(for: value, isVirtualFolder: isVirtualFolder)
                .map { #""\#($0)""# } ?? "null"

            result.replaceCharacters(in: match.range, with: #""CollectionType":\#(literal)"#)
            didChange = true
        }

        return didChange ? Data((result as String).utf8) : nil
    }
}

// MARK: - URLProtocol

/// Applies `CollectionTypeCompatibility` to JSON API responses before the SDK
/// decodes them.
///
/// The SDK builds its own `JSONDecoder` and offers no hook to replace it, so
/// the repair happens on the wire instead. Only the SDK's data requests are
/// handled — it marks every request `Accept: application/json` — and
/// responses that need no repair are forwarded unchanged.
final class CollectionTypeCompatibilityURLProtocol: URLProtocol, @unchecked Sendable {

    private static let handledKey = "CollectionTypeCompatibilityURLProtocol.handled"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    private var forwardedTask: URLSessionDataTask?

    override class func canInit(with task: URLSessionTask) -> Bool {
        // An upload carries its body outside the request, and a download can be
        // any size; neither is an API response worth buffering.
        guard task is URLSessionDataTask,
              !(task is URLSessionUploadTask),
              let request = task.currentRequest ?? task.originalRequest
        else { return false }

        return canInit(with: request)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              property(forKey: handledKey, in: request) == nil
        else { return false }

        return request.value(forHTTPHeaderField: "Accept")?.contains("application/json") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let forwarded = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: forwarded)

        let isVirtualFolder = request.url?.path.lowercased().hasSuffix("/library/virtualfolders") == true

        forwardedTask = Self.session.dataTask(with: forwarded as URLRequest) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }

            var data = data
            var response = response

            if let original = data,
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.mimeType?.contains("json") == true,
               let repaired = CollectionTypeCompatibility.normalized(original, isVirtualFolder: isVirtualFolder)
            {
                data = repaired
                response = Self.response(httpResponse, contentLength: repaired.count)
            }

            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        forwardedTask?.resume()
    }

    override func stopLoading() {
        forwardedTask?.cancel()
    }

    private static func response(_ response: HTTPURLResponse, contentLength: Int) -> URLResponse {
        guard let url = response.url else { return response }

        // The body is already decoded and has a new length, so neither of the
        // server's values still describes it.
        var headers = response.allHeaderFields.reduce(into: [String: String]()) { headers, field in
            guard let key = field.key as? String, let value = field.value as? String,
                  !["content-length", "content-encoding"].contains(key.lowercased())
            else { return }
            headers[key] = value
        }
        headers["Content-Length"] = String(contentLength)

        return HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: headers
        ) ?? response
    }
}

//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
#if SWIFT_PACKAGE
import MediaServerCore
#endif

/// Native catalog slice. Tokens remain private to this actor and are not written to disk.
public actor JellyfinCatalogAdapter: MediaCatalog {
    public typealias Domain = MediaServerDomain

    public enum Failure: Error, Equatable {
        case invalidEndpoint
        case invalidResponse
        case staleSession
        case foreignItem
        case invalidCursor
        case unauthorized
        case httpStatus(Int)
    }

    private let endpoint: URL
    private let server: Domain.ServerIdentity
    private let deviceID: UUID
    private let transport: any MediaHTTPTransport
    private var authenticationGeneration = UUID()
    private var session: (scope: Domain.SessionScope, token: String)?
    private let pageSize = 80
    private var artworkCache: [Domain.ArtworkReference: Data] = [:]
    private var artworkCacheBytes = 0

    public init(
        endpoint: URL,
        serverRecordID: UUID,
        deviceID: UUID,
        transport: any MediaHTTPTransport = URLSessionMediaTransport()
    ) throws {
        guard let parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw Failure.invalidEndpoint }
        self.endpoint = endpoint
        server = .init(recordID: serverRecordID, provider: .jellyfin)
        self.deviceID = deviceID
        self.transport = transport
    }

    public func signIn(username: String, password: String) async throws -> Domain.SessionScope {
        authenticationGeneration = UUID()
        let generation = authenticationGeneration
        session = nil
        artworkCache = [:]
        artworkCacheBytes = 0
        var request = try makeRequest(path: ["Users", "AuthenticateByName"])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginBody(Username: username, Pw: password))
        let response = try await transport.send(request)
        guard generation == authenticationGeneration else { throw Failure.staleSession }
        try Task.checkCancellation()
        try validate(response)
        let result = try JSONDecoder().decode(LoginResult.self, from: response.data)
        guard !result.AccessToken.isEmpty, !result.AccessToken.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw Failure.invalidResponse }
        let account = try Domain.AccountScope(server: server, account: .init(result.User.Id))
        let scope = Domain.SessionScope(viewing: .init(account: account))
        session = (scope, result.AccessToken)
        return scope
    }

    public func signOut() {
        authenticationGeneration = UUID()
        session = nil
        artworkCache = [:]
        artworkCacheBytes = 0
    }

    public func artwork(_ reference: Domain.ArtworkReference, in scope: Domain.SessionScope) async throws -> Data {
        guard reference.item.server == server else { throw Failure.foreignItem }
        guard let session, session.scope == scope else { throw Failure.staleSession }
        if let cached = artworkCache[reference] {
            return cached
        }
        var request = try makeRequest(path: ["Items", reference.item.item.rawValue, "Images", "Primary"], query: [
            .init(name: "tag", value: reference.tag), .init(name: "maxWidth", value: "600"),
            .init(name: "quality", value: "90"),
        ])
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue(session.token, forHTTPHeaderField: "X-Emby-Token")
        let response = try await transport.send(request)
        guard self.session?.scope == scope else { throw Failure.staleSession }
        try Task.checkCancellation()
        try validate(response)
        guard response.data.count <= 10_000_000 else { throw Failure.invalidResponse }
        if artworkCacheBytes + response.data.count > 24_000_000 {
            artworkCache = [:]
            artworkCacheBytes = 0
        }
        // Concurrent requests for the same artwork can complete in either order.
        artworkCacheBytes -= artworkCache[reference]?.count ?? 0
        artworkCache[reference] = response.data
        artworkCacheBytes += response.data.count
        return response.data
    }

    public func libraries(in scope: Domain.SessionScope) async throws -> [Domain.CatalogItem] {
        let result: ItemsResult = try await get(path: ["UserViews"], scope: scope)
        return try result.Items.map(mapItem)
    }

    public func item(_ id: Domain.MediaID, in scope: Domain.SessionScope) async throws -> Domain.CatalogItem {
        guard id.server == server else { throw Failure.foreignItem }
        let result: Item = try await get(path: ["Items", id.item.rawValue], scope: scope)
        guard result.Id == id.item.rawValue else { throw Failure.invalidResponse }
        return try mapItem(result)
    }

    public func items(
        in scope: Domain.SessionScope,
        parent: Domain.MediaID?,
        search: String = "",
        cursor: Domain.CatalogCursor? = nil
    ) async throws -> Domain.CatalogPage {
        if let parent, parent.server != server {
            throw Failure.foreignItem
        }
        var offset = 0
        if let cursor {
            guard let data = Data(base64Encoded: cursor.value), let decoded = try? JSONDecoder().decode(Cursor.self, from: data),
                  decoded.session == scope.generation, decoded.parent == parent?.item.rawValue, decoded.search == search,
                  decoded.offset >= 0 else { throw Failure.invalidCursor }
            offset = decoded.offset
        }
        var query = [
            URLQueryItem(name: "startIndex", value: String(offset)),
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "fields", value: "Overview"),
            URLQueryItem(name: "sortBy", value: "SortName"),
            URLQueryItem(name: "sortOrder", value: "Ascending"),
            URLQueryItem(name: "recursive", value: search.isEmpty ? "false" : "true")
        ]
        if let parent {
            query.append(.init(name: "parentId", value: parent.item.rawValue))
        }
        if !search.isEmpty {
            query.append(.init(name: "searchTerm", value: search))
        }
        let result: ItemsResult = try await get(path: ["Items"], query: query, scope: scope)
        guard result.TotalRecordCount.map({ $0 >= 0 }) ?? true else { throw Failure.invalidResponse }
        let (nextOffset, overflow) = offset.addingReportingOverflow(result.Items.count)
        guard !overflow else { throw Failure.invalidCursor }
        let hasNext = !result.Items.isEmpty && (result.TotalRecordCount.map { nextOffset < $0 } ?? (result.Items.count == pageSize))
        let next = try hasNext ? Domain.CatalogCursor(value: JSONEncoder().encode(Cursor(
            session: scope.generation, parent: parent?.item.rawValue, search: search, offset: nextOffset
        )).base64EncodedString()) : nil
        return try .init(items: result.Items.map(mapItem), next: next, total: result.TotalRecordCount)
    }

    private func get<T: Decodable>(path: [String], query: [URLQueryItem] = [], scope: Domain.SessionScope) async throws -> T {
        guard let session, session.scope == scope else { throw Failure.staleSession }
        var request = try makeRequest(path: path, query: query + [.init(name: "userId", value: scope.viewing.account.account.rawValue)])
        request.setValue(session.token, forHTTPHeaderField: "X-Emby-Token")
        let response = try await transport.send(request)
        guard self.session?.scope == scope else { throw Failure.staleSession }
        try Task.checkCancellation()
        try validate(response)
        return try JSONDecoder().decode(T.self, from: response.data)
    }

    private func makeRequest(path: [String], query: [URLQueryItem] = []) throws -> URLRequest {
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw Failure.invalidEndpoint }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let suffix = try path.map { component in
            guard component != ".", component != "..", let encoded = component.addingPercentEncoding(withAllowedCharacters: allowed)
            else { throw Failure.invalidResponse }
            return encoded
        }.joined(separator: "/")
        let prefix = parts.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.percentEncodedPath = "/" + (prefix.isEmpty ? "" : prefix + "/") + suffix
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw Failure.invalidEndpoint }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "MediaBrowser Client=\"Swiftfin Native\", Device=\"Mac\", DeviceId=\"\(deviceID.uuidString)\", Version=\"0.1\"",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private func validate(_ response: MediaHTTPResponse) throws {
        if response.statusCode == 401 || response.statusCode == 403 {
            throw Failure.unauthorized
        }
        guard (200 ..< 300).contains(response.statusCode) else { throw Failure.httpStatus(response.statusCode) }
    }

    private func mapItem(_ item: Item) throws -> Domain.CatalogItem {
        let id = try Domain.MediaID(server: server, item: .init(item.Id))
        let duration = try item.RunTimeTicks
            .flatMap { ticks in ticks >= 0 ? try Domain.MediaTime(seconds: Double(ticks) / 10_000_000) : nil }
        return .init(
            id: id,
            title: item.Name ?? item.Id,
            kind: item.Type ?? "Unknown",
            isFolder: item.IsFolder ?? false,
            overview: item.Overview,
            year: item.ProductionYear,
            duration: duration,
            artwork: item.ImageTags?["Primary"].map { .init(item: id, tag: $0) }
        )
    }

    // Wire spelling is intentionally confined to the adapter.
    private struct LoginBody: Encodable { let Username: String
        let Pw: String
    }

    private struct LoginResult: Decodable { let AccessToken: String
        let User: User
    }

    private struct User: Decodable { let Id: String }
    private struct ItemsResult: Decodable { let Items: [Item]
        let TotalRecordCount: Int?
    }

    private struct Item: Decodable {
        let Id: String
        let Name: String?
        let `Type`: String?
        let IsFolder: Bool?
        let Overview: String?
        let ProductionYear: Int?
        let RunTimeTicks: Int64?
        let ImageTags: [String: String]?
    }

    private struct Cursor: Codable { let session: UUID
        let parent: String?
        let search: String
        let offset: Int
    }
}

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

/// Native Silo catalog reads. Library identifiers and content identifiers are distinct resources.
/// Series navigation, signed artwork delivery and playback are separate implementation milestones.
public struct SiloCatalogAdapter: Sendable {
    public typealias Domain = MediaServerDomain
    public typealias Failure = SiloAPIClient.Failure

    public struct Library: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let kind: String
        fileprivate let scope: Domain.SessionScope
    }

    private struct LibraryResponse: Decodable {
        let id: Int
        let name: String
        let type: String
    }

    private struct Item: Decodable {
        let contentId: String
        let type: String
        let title: String
        let overview: String?
        let year: Int?
        let runtime: Int?
    }

    private struct Page: Decodable {
        let total: Int
        let totalExact: Bool
        let hasMore: Bool
        let snapshot: String?
        let items: [Item]
    }

    private struct Cursor: Codable {
        let scope: UUID
        let library: String?
        let search: String
        let offset: Int
        let snapshot: String?
    }

    private let client: SiloAPIClient
    private let pageSize = 80

    public init(client: SiloAPIClient) {
        self.client = client
    }

    public func libraries(in scope: Domain.SessionScope) async throws -> [Library] {
        let data = try await client.catalogRequest(path: ["user", "libraries"], scope: scope)
        let libraries = try SiloAPIClient.decode([LibraryResponse].self, data)
        guard libraries.allSatisfy({ $0.id > 0 }), Set(libraries.map(\.id)).count == libraries.count else { throw Failure.invalidResponse }
        return libraries.map { .init(id: String($0.id), title: $0.name, kind: $0.type, scope: scope) }
    }

    public func items(
        in scope: Domain.SessionScope,
        library: Library? = nil,
        search: String = "",
        cursor: Domain.CatalogCursor? = nil
    ) async throws -> Domain.CatalogPage {
        if let library, library.scope != scope {
            throw Failure.staleSession
        }
        var offset = 0
        var snapshot: String?
        if let cursor {
            guard let data = Data(base64Encoded: cursor.value),
                  let decoded = try? JSONDecoder().decode(Cursor.self, from: data),
                  decoded.scope == scope.generation, decoded.library == library?.id,
                  decoded.search == search, decoded.offset >= 0 else { throw Failure.invalidCursor }
            offset = decoded.offset
            snapshot = decoded.snapshot
        }
        var query = [
            URLQueryItem(name: "source", value: "query"),
            .init(name: "limit", value: String(pageSize)),
            .init(name: "offset", value: String(offset)),
            .init(name: "include_total", value: "true")
        ]
        if let library {
            query.append(.init(name: "library_id", value: library.id))
        }
        if !search.isEmpty {
            query.append(.init(name: "q", value: search))
        }
        if let snapshot {
            query.append(.init(name: "snapshot", value: snapshot))
        }
        let data = try await client.catalogRequest(path: ["catalog"], query: query, scope: scope)
        let page = try SiloAPIClient.decode(Page.self, data)
        let (nextOffset, overflow) = offset.addingReportingOverflow(page.items.count)
        guard page.total >= 0, !overflow, !page.hasMore || !page.items.isEmpty else { throw Failure.invalidResponse }
        if let snapshot, let returned = page.snapshot, snapshot != returned {
            throw Failure.invalidResponse
        }
        let next = try page.hasMore ? Domain.CatalogCursor(value: JSONEncoder().encode(Cursor(
            scope: scope.generation, library: library?.id, search: search, offset: nextOffset,
            snapshot: page.snapshot ?? snapshot
        )).base64EncodedString()) : nil
        return try .init(items: page.items.map { try map($0, scope: scope) }, next: next, total: page.totalExact ? page.total : nil)
    }

    public func item(_ id: Domain.MediaID, in scope: Domain.SessionScope) async throws -> Domain.CatalogItem {
        guard id.server == scope.viewing.account.server, id.server.provider == .silo else { throw Failure.foreignItem }
        let data = try await client.catalogRequest(path: ["catalog", "items", id.item.rawValue], scope: scope)
        let item = try SiloAPIClient.decode(Item.self, data)
        guard item.contentId == id.item.rawValue else { throw Failure.invalidResponse }
        return try map(item, scope: scope)
    }

    private func map(_ item: Item, scope: Domain.SessionScope) throws -> Domain.CatalogItem {
        guard item.runtime.map({ $0 >= 0 }) ?? true else { throw Failure.invalidResponse }
        // Silo metadata runtime is minutes; zero/omitted means unknown.
        let duration = try item.runtime.flatMap { $0 > 0 ? try Domain.MediaTime(seconds: Double($0) * 60) : nil }
        return try .init(
            id: .init(server: scope.viewing.account.server, item: .init(item.contentId)), title: item.title, kind: item.type,
            isFolder: false, overview: item.overview, year: item.year.flatMap { $0 > 0 ? $0 : nil }, duration: duration
        )
    }
}
